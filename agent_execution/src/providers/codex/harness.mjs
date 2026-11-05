import { constants, closeSync, fstatSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join, resolve } from 'node:path';
import { bindCodexInvocation, stageCodexResult } from './structured_result.mjs';

function ownedParent(path) {
  const absolute = resolve(path), stat = lstatSync(absolute);
  if (!stat.isDirectory() || stat.isSymbolicLink() || realpathSync(absolute) !== absolute || stat.uid !== process.getuid()) throw Error('unsafe-harness-parent');
  return absolute;
}
function oauthValues(auth) {
  if (!auth || typeof auth !== 'object' || auth.OPENAI_API_KEY ||
      !['access_token', 'refresh_token'].every(key => typeof auth.tokens?.[key] === 'string' && auth.tokens[key].length > 0)) {
    throw Error('subscription-oauth-required');
  }
  return Object.values(auth.tokens).filter(value => typeof value === 'string' && value.length >= 8);
}
function readPrivateAuth(path) {
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(descriptor);
    if (!stat.isFile() || stat.nlink !== 1 || stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.size < 1 || stat.size > 65536) throw Error('invalid-private-auth');
    return JSON.parse(readFileSync(descriptor, 'utf8'));
  } finally { closeSync(descriptor); }
}

/** Native Codex subscription auth stays with the trusted harness, never its executor. */
export function createCodexHarness(options) {
  const { runtime, executable, executablePath, credentialForRun, telemetry, reportUsage } = options;
  const parent = ownedParent(options.parent);
  const owner = randomUUID();
  const home = join(parent, `codex-${owner}`);
  let created = false, authWritten = false, used = false, session, endpoint, transcript = '', exitCode = null;
  let cleanupFailed = false;
  let model;
  return {
    async execute({ worker, compiled, record, deadlineMs, signal, onStarted }) {
      if (used) throw Error('harness-already-used');
      used = true;
      const config = compiled.configuration;
      // This exact version has an exercised external executor path. A new pin
      // requires the same executable contract proof, not a silent substitution.
      if (config.harness.version !== '0.164.0') throw Error('unsupported-codex-executor-version');
      if (config.limits?.enabled) throw Error('native-oauth-model-budget-unavailable');
      if (record.inputs.prompt.kind !== 'inline') throw Error('resolved-inline-prompt-required');
      const invocation = bindCodexInvocation(options.invocation, record);
      if (!/^\/[A-Za-z0-9/_-]+$/.test(worker.workspace)) throw Error('invalid-worker-workspace');
      // Codex canonicalizes --cd before connecting to the executor. The
      // composition root supplies an empty directory in its disposable controller
      // at the same path; never create or reuse an arbitrary host checkout here.
      try {
        if (options.controllerWorkspace !== worker.workspace || ownedParent(options.controllerWorkspace) !== worker.workspace) throw Error();
        const placeholder = join(worker.workspace, 'repository');
        if (ownedParent(placeholder) !== placeholder || (lstatSync(placeholder).mode & 0o077) || readdirSync(placeholder).length) throw Error();
      } catch { throw Error('invalid-controller-workspace'); }
      model = config.harness.model;
      mkdirSync(home, { mode: 0o700 }); created = true;
      writeFileSync(join(home, '.owner'), owner, { flag: 'wx', mode: 0o600 });
      let values = [];
      const chunks = [];
      const result = { exitCode: null };
      try {
        const output = stageCodexResult(invocation, home);
        if (typeof credentialForRun !== 'function') throw Error('credential-resolver-unavailable');
        const credential = await credentialForRun({ compiled, record, deadlineMs, signal });
        const auth = await credential.read();
        values = oauthValues(auth);
        writeFileSync(join(home, 'auth.json'), JSON.stringify(auth), { flag: 'wx', mode: 0o600 });
        authWritten = true;
        const env = { PATH: executablePath, HOME: home, CODEX_HOME: home };
        const version = await runtime.runTrustedProcess({ command: executable, args: ['--version'], cwd: home, env,
          timeoutMs: Math.min(10000, deadlineMs - Date.now()), maxOutputBytes: 4096, signal });
        if (version.trim() !== 'codex-cli ' + config.harness.version) throw Error('codex-version-mismatch');
        await worker.run({ command: 'mkdir', args: ['-p', worker.workspace + '/user/codex', worker.workspace + '/tmp'],
          timeoutMs: Math.min(10000, deadlineMs - Date.now()), maxOutputBytes: 4096, signal });
        const executorArgs = ['-i', 'PATH=/usr/local/bin:/usr/bin:/bin', 'HOME=' + worker.workspace + '/user',
          'CODEX_HOME=' + worker.workspace + '/user/codex', 'TMPDIR=' + worker.workspace + '/tmp', 'codex'];
        const workerVersion = await worker.run({ command: '/usr/bin/env', args: [...executorArgs, '--version'],
          timeoutMs: Math.min(10000, deadlineMs - Date.now()), maxOutputBytes: 4096, signal });
        if (workerVersion.trim() !== 'codex-cli ' + config.harness.version) throw Error('executor-version-mismatch');
        endpoint = await runtime.openWorkerStdioEndpoint(worker, {
          command: '/usr/bin/env', args: [...executorArgs, 'exec-server', '--listen', 'stdio'],
          timeoutMs: deadlineMs - Date.now(), maxInputBytes: 67108864, maxOutputBytes: 67108864, signal,
        }, { parent: options.socketParent });
        // include_local=false is essential: administrative host command APIs
        // must refuse requests instead of bypassing the worker boundary.
        writeFileSync(join(home, 'environments.toml'), [
          'default = "worker"', 'include_local = false', '[[environments]]', 'id = "worker"',
          'program = ' + JSON.stringify(endpoint.command), 'args = ' + JSON.stringify(endpoint.args),
          'cwd = ' + JSON.stringify(home), '',
        ].join('\n'), { flag: 'wx', mode: 0o600 });
        const repository = worker.workspace + '/repository';
        const gitPaths = await worker.run({ command: '/usr/bin/find',
          args: [repository, '-name', '.git', '-prune', '-print0'],
          timeoutMs: Math.min(10000, deadlineMs - Date.now()), maxOutputBytes: 65536, signal });
        const protectedPaths = new Set([repository + '/.git']);
        for (const path of gitPaths.split('\0').filter(Boolean)) {
          if (!path.startsWith(repository + '/') || !path.endsWith('/.git') ||
              path.split('/').some(part => part === '.' || part === '..') || /[\r\n]/.test(path)) {
            throw Error('invalid-git-metadata-path');
          }
          protectedPaths.add(path);
        }
        writeFileSync(join(home, 'config.toml'), [
          'model = ' + JSON.stringify(model),
          'developer_instructions = ' + JSON.stringify(config.instructions ?? ''), 'approval_policy = "never"', 'default_permissions = "ii-workshop"',
          'web_search = ' + JSON.stringify(invocation?.search ?? 'disabled'), '[features]', 'hooks = false', 'shell_snapshot = false',
          '[permissions.ii-workshop.filesystem]', '":minimal" = "read"',
          // Toolchains, package caches, HOME and TMPDIR all live inside the
          // worker's bounded workspace. Git metadata remains denied below.
          JSON.stringify(worker.workspace) + ' = "write"',
          // Dart resolves its executable through /proc/self/exe. This is the
          // worker's PID namespace; the trusted harness is outside it.
          '"/proc" = "read"',
          ...[...protectedPaths].sort().map(path => JSON.stringify(path) + ' = "deny"'),
          '[permissions.ii-workshop.filesystem.":workspace_roots"]', '"." = "write"',
          // Flutter tests bind loopback sockets. Runtime has already sealed
          // this worker's network namespace before the harness is invoked;
          // disabling sockets again here would also block those local tests.
          '[permissions.ii-workshop.network]', 'enabled = true', '',
        ].join('\n'), { flag: 'wx', mode: 0o600 });
        session = await runtime.openTrustedProcess({ command: executable,
          args: ['--no-daemon', '--ask-for-approval', 'never', 'exec', '--json', '--strict-config', '--ephemeral',
            '--skip-git-repo-check', '--ignore-rules', ...output.args, '--cd', repository, '-'],
          cwd: home, env, timeoutMs: deadlineMs - Date.now(), maxInputBytes: 1048576, maxOutputBytes: 16777216, signal });
        await session.write(Buffer.from(record.inputs.prompt.text)); session.end();
        let pending = '', announced = false;
        for await (const chunk of session.output) {
          chunks.push(Buffer.from(chunk));
          pending += Buffer.from(chunk).toString('utf8');
          if (Buffer.byteLength(pending) > 1048576) throw Error('codex-event-too-large');
          const lines = pending.split('\n'); pending = lines.pop();
          for (const line of lines) {
            let event; try { event = JSON.parse(line); } catch { continue; }
            if (!announced && event.type === 'thread.started') { await onStarted(); announced = true; }
          }
        }
        const completion = await session.completion;
        exitCode = completion.exitCode;
        if (!announced) throw Error('codex-start-unconfirmed');
        result.exitCode = exitCode;
        if (invocation && exitCode === 0) result.lastMessage = output.read();
        return result;
      } finally {
        try { await session?.close(); } catch { cleanupFailed = true; }
        try { await endpoint?.close(); } catch { cleanupFailed = true; }
        // Refreshed credential values are excluded too. Raw captured output is
        // never written to telemetry or disk before this redaction boundary.
        let safeToRetain = true;
        if (authWritten) {
          try {
            const refreshed = readPrivateAuth(join(home, 'auth.json'));
            values.push(...oauthValues(refreshed));
            // The trusted provider may stage a private refresh handoff here.
            // Persistence remains outside the harness, after worker cleanup;
            // neither the worker nor this read handle receives writer authority.
            await options.onRefreshedCredential?.(refreshed);
          } catch { cleanupFailed = true; safeToRetain = false; }
        }
        transcript = safeToRetain ? Buffer.concat(chunks).toString('utf8') : '';
        // JSON events can contain escaped token values. Redact both encodings.
        const excluded = [...new Set(values.flatMap(value => [value, JSON.stringify(value).slice(1, -1)]))]
          .sort((left, right) => right.length - left.length);
        for (const value of excluded) transcript = transcript.split(value).join('[REDACTED]');
        chunks.forEach(chunk => chunk.fill(0));
        await telemetry.retain({ executionId: record.executionId, attemptId: record.attemptId,
          inputDigest: record.inputDigest, transcript, exitCode, captureComplete: safeToRetain });
        if (invocation && (!safeToRetain || typeof result.lastMessage === 'string' &&
            excluded.some(value => result.lastMessage.includes(value)))) {
          delete result.lastMessage;
          throw Error('codex-result-unconfirmed');
        }
      }
    },
    async reportUsage() {
      return reportUsage({ transcript, exitCode, model, billingMode: 'subscription_included' });
    },
    async close() {
      try { await session?.close(); } catch { cleanupFailed = true; }
      try { await endpoint?.close(); } catch { cleanupFailed = true; }
      if (created) {
        if (realpathSync(home) !== home || readFileSync(join(home, '.owner'), 'utf8') !== owner) throw Error('harness-ownership-changed');
        rmSync(home, { recursive: true }); created = false;
      }
      if (cleanupFailed) throw Error('harness-cleanup-unconfirmed');
    },
  };
}
