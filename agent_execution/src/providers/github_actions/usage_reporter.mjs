import { constants, closeSync, fstatSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { join } from 'node:path';

/** Invoke the installed evaluations reporter; do not reimplement its protocol. */
export function createExistingUsageReporter({ runtime, parent, script, executable, executablePath, endpoint, workspaceId, executionId }) {
  let url;
  try { url = new URL(endpoint); } catch { throw Error('usage-reporter-binding-invalid'); }
  const local = url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname);
  const stat = lstatSync(parent);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) || realpathSync(parent) !== parent ||
      !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(workspaceId ?? '') || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(executionId ?? '') ||
      !/^\/[A-Za-z0-9/_-]+$/.test(executable ?? '') || !/^\/[A-Za-z0-9/_-]+(?::\/[A-Za-z0-9/_-]+)*$/.test(executablePath ?? '') ||
      url.protocol !== 'https:' && !local || url.username || url.password || url.search || url.hash || !/^[a-f0-9]{64}$/.test(script?.sha256 ?? '')) throw Error('usage-reporter-binding-invalid');
  return ({ read }) => ({
    async report({ transcript, exitCode, model, billingMode }) {
      if (typeof transcript !== 'string' || Buffer.byteLength(transcript) > 16777216 ||
          exitCode !== null && (!Number.isSafeInteger(exitCode) || exitCode < 0) ||
          model !== undefined && !/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}$/.test(model) || billingMode !== 'subscription_included') throw Error('usage-report-invalid');
      const owner = randomUUID(), directory = mkdtempSync(join(parent, 'usage-'));
      writeFileSync(join(directory, '.owner'), owner, { mode: 0o600, flag: 'wx' });
      try {
        const descriptor = openSync(script.path, constants.O_RDONLY | constants.O_NOFOLLOW);
        try {
          const info = fstatSync(descriptor);
          if (!info.isFile() || info.uid !== process.getuid() || info.nlink !== 1 || (info.mode & 0o022) || info.size > 1048576 ||
              createHash('sha256').update(readFileSync(descriptor)).digest('hex') !== script.sha256) throw Error('usage-reporter-integrity');
        } finally { closeSync(descriptor); }
        const key = await read();
        if (!Buffer.isBuffer(key) || key.length > 4096 || !/^iiosu_v1\.[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\.[A-Za-z0-9_-]{43}$/.test(key.toString('utf8'))) throw Error('usage-credential-invalid');
        const keyFile = join(directory, 'usage.key'), logFile = join(directory, 'codex.jsonl');
        writeFileSync(keyFile, key, { flag: 'wx', mode: 0o600 }); key.fill(0);
        writeFileSync(logFile, transcript, { flag: 'wx', mode: 0o600 });
        const home = join(directory, 'home'); mkdirSync(home, { mode: 0o700 });
        const output = await runtime.runTrustedProcess({ command: executable, args: [script.path, logFile, String(exitCode ?? 1)],
          cwd: directory, env: { PATH: executablePath, HOME: home, CODEX_HOME: home,
            AGENT_USAGE_KEY_FILE: keyFile, II_OS_AGENT_USAGE_URL: endpoint, II_OS_AGENT_USAGE_WORKSPACE_ID: workspaceId,
            EVALS_EXECUTION_ORIGIN: 'cloud', II_AGENT_USAGE_SOURCE: 'codex', II_AGENT_BILLING_MODE: billingMode,
            II_AGENT_BILLING_PROVIDER: 'openai', IIF_JOB_ID: executionId, II_OS_AGENT_EXECUTION_ID: executionId, ...(model ? { II_AGENT_MODEL: model } : {}) },
          timeoutMs: 30000, maxOutputBytes: 65536 });
        const receipt = JSON.parse(output);
        if (Object.keys(receipt).sort().join(',') !== 'eventId,model,reported,source,totalTokens' || receipt.reported !== true ||
            !/^[a-f0-9]{64}$/.test(receipt.eventId) || receipt.source !== 'codex' || receipt.model !== (model ?? null) ||
            !Number.isSafeInteger(receipt.totalTokens) || receipt.totalTokens < 0) throw Error('usage-report-unconfirmed');
        return receipt;
      } catch { throw Error('usage-report-unconfirmed'); }
      finally {
        if (realpathSync(directory) !== directory || readFileSync(join(directory, '.owner'), 'utf8') !== owner) throw Error('usage-cleanup-unconfirmed');
        rmSync(directory, { recursive: true });
      }
    },
  });
}
