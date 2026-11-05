import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createCodexHarness } from '../src/providers/codex/harness.mjs';
import { codexInvocationDigest } from '../src/providers/codex/structured_result.mjs';

function fixture(t) {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'ar-codex-'));
  const workspace = join(parent, 'workspace');
  mkdirSync(workspace, { mode: 0o700 });
  mkdirSync(join(workspace, 'repository'), { mode: 0o700 });
  const owner = randomUUID(); writeFileSync(join(parent, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  const calls = [], records = [], auth = { tokens: { access_token: 'synthetic-access', refresh_token: 'synthetic-refresh' } };
  const refreshed = { tokens: { access_token: 'synthetic-new-access', refresh_token: 'synthetic-new-refresh' } };
  const options = { parent, controllerWorkspace: workspace, socketParent: parent, executable: '/trusted/codex', executablePath: '/trusted/bin',
    credential: { read: async () => { calls.push('credential'); return auth; } },
    credentialForRun: async () => options.credential,
    telemetry: { retain: async record => records.push(record) },
    reportUsage: async report => report,
    runtime: {
      runTrustedProcess: async request => {
        assert.deepEqual(Object.keys(request.env).sort(), ['CODEX_HOME', 'HOME', 'PATH']);
        return 'codex-cli 0.164.0';
      },
      openWorkerStdioEndpoint: async (_worker, request) => {
        assert.equal(JSON.stringify(request).includes('synthetic-access'), false);
        assert.ok(request.args.includes('exec-server'));
        return { command: '/trusted/node', args: ['connector', '/private/socket'], close: async () => calls.push('endpoint-close') };
      },
      openTrustedProcess: async request => {
        const environments = readFileSync(join(request.env.CODEX_HOME, 'environments.toml'), 'utf8');
        assert.ok(environments.includes('include_local = false'));
        assert.ok(!environments.includes('synthetic-access'));
        assert.ok(!request.args.includes('--ignore-user-config'), 'would discard the pinned executor binding');
        const config = readFileSync(join(request.env.CODEX_HOME, 'config.toml'), 'utf8');
        assert.ok(config.includes('hooks = false'));
        assert.ok(config.includes('developer_instructions = "Approved runtime instructions."'));
        assert.ok(config.includes(JSON.stringify(workspace) + ' = "write"'), 'worker SDK caches must be writable');
        assert.ok(config.includes('"/proc" = "read"'), 'Dart resolves its executable in the worker PID namespace');
        assert.ok(config.includes(JSON.stringify(workspace + '/repository/.git') + ' = "deny"'));
        assert.ok(config.includes('[permissions.ii-workshop.network]\nenabled = true'));
        assert.equal(config.includes('model_provider'), false, 'native OAuth provider must be retained');
        writeFileSync(join(request.env.CODEX_HOME, 'auth.json'), JSON.stringify(refreshed), { mode: 0o600 });
        return {
          output: (async function* () {
            yield Buffer.from('{"type":"thread.started"}\n');
            yield Buffer.from('{"type":"message","text":"synthetic-access synthetic-new-access"}\n');
          })(),
          completion: Promise.resolve({ exitCode: 0 }), write: async () => {}, end: () => {},
          close: async () => calls.push('session-close'),
        };
      },
    },
  };
  const input = { worker: { workspace, run: async request => request.args.includes('--version') ? 'codex-cli 0.164.0' : '' },
    compiled: { configuration: { instructions: 'Approved runtime instructions.', harness: { version: '0.164.0', model: 'configured-model' }, limits: { enabled: false } } },
    record: { executionId: 'run-1', attemptId: 'attempt-1', inputDigest: 'input', inputs: { prompt: { kind: 'inline', text: 'frozen prompt' } } },
    deadlineMs: Date.now() + 10000, signal: new AbortController().signal, onStarted: async () => calls.push('running') };
  return { parent, calls, records, options, input };
}

test('native OAuth is retained outside executor and both original and refreshed values are redacted', async t => {
  const { parent, calls, records, options, input } = fixture(t);
  const harness = createCodexHarness(options);
  assert.deepEqual(await harness.execute(input), { exitCode: 0 });
  assert.equal(calls.filter(call => call === 'running').length, 1);
  assert.equal(records.length, 1);
  assert.equal(records[0].captureComplete, true);
  assert.equal(records[0].transcript.includes('synthetic-access'), false);
  assert.equal(records[0].transcript.includes('synthetic-new-access'), false);
  assert.ok(records[0].transcript.includes('[REDACTED]'));
  await harness.close();
  assert.deepEqual(readdirSync(parent), ['.owner', 'workspace']);
  const usage = await harness.reportUsage();
  assert.equal(usage.billingMode, 'subscription_included');
  assert.equal(usage.model, 'configured-model');
});

test('API key credentials are rejected and their failed handoff is cleaned', async t => {
  const { parent, options, input } = fixture(t);
  options.credential.read = async () => ({ OPENAI_API_KEY: 'synthetic-forbidden-key' });
  const harness = createCodexHarness(options);
  await assert.rejects(harness.execute(input), /subscription-oauth-required/);
  await harness.close();
  assert.deepEqual(readdirSync(parent), ['.owner', 'workspace']);
});

test('unproved versions and unsupported native model budgets fail before reading credentials', async t => {
  for (const fault of ['version', 'budget']) {
    const { calls, options, input } = fixture(t);
    if (fault === 'version') input.compiled.configuration.harness.version = '0.144.6';
    else input.compiled.configuration.limits.enabled = true;
    const harness = createCodexHarness(options);
    await assert.rejects(harness.execute(input), fault === 'version' ? /unsupported-codex/ : /model-budget-unavailable/);
    assert.equal(calls.includes('credential'), false);
    await harness.close();
  }
});


test('a credential read handle never supplies provider secret replacement authority', async t => {
  const { parent, records, options, input } = fixture(t);
  options.credential.replace = async () => { assert.fail('the harness must not invoke provider secret writers'); };
  const harness = createCodexHarness(options);
  await harness.execute(input);
  assert.equal(records[0].captureComplete, true);
  assert.equal(records[0].transcript.includes('synthetic-new-access'), false);
  await harness.close();
  assert.deepEqual(readdirSync(parent), ['.owner', 'workspace']);
});

test('refreshed OAuth reaches only the explicit trusted provider hook', async t => {
  const { options, input, records } = fixture(t);
  let received;
  options.onRefreshedCredential = async value => { received = value; };
  const harness = createCodexHarness(options);
  await harness.execute(input); await harness.close();
  assert.equal(received.tokens.access_token, 'synthetic-new-access');
  assert.equal(records[0].transcript.includes(received.tokens.access_token), false);
});

for (const fault of ['failure', 'cancelled']) {
  test(`the trusted refresh handoff survives native ${fault} before private home cleanup`, async t => {
    const { parent, options, input, records } = fixture(t);
    const open = options.runtime.openTrustedProcess;
    options.runtime.openTrustedProcess = async request => {
      const session = await open(request);
      session.completion = fault === 'failure' ? Promise.resolve({ exitCode: 1 }) :
        Promise.reject(Object.assign(Error('synthetic cancellation'), { name: 'AbortError' }));
      // execute reads completion after consuming output; keep rejection handled.
      session.completion.catch(() => {});
      return session;
    };
    let received;
    options.onRefreshedCredential = async value => { received = value; };
    const harness = createCodexHarness(options);
    if (fault === 'failure') assert.deepEqual(await harness.execute(input), { exitCode: 1 });
    else await assert.rejects(harness.execute(input), /synthetic cancellation/);
    assert.equal(received.tokens.refresh_token, 'synthetic-new-refresh');
    assert.equal(records[0].transcript.includes(received.tokens.access_token), false);
    await harness.close();
    assert.deepEqual(readdirSync(parent), ['.owner', 'workspace']);
  });
}

test('a failed private refresh handoff withholds capture and cleanup confirmation', async t => {
  const { parent, options, input, records } = fixture(t);
  options.onRefreshedCredential = async () => { throw Error('synthetic handoff failure'); };
  const harness = createCodexHarness(options);
  await harness.execute(input);
  assert.equal(records[0].captureComplete, false);
  assert.equal(records[0].transcript, '');
  await assert.rejects(harness.close(), /cleanup-unconfirmed/);
  assert.deepEqual(readdirSync(parent), ['.owner', 'workspace']);
});

test('unreadable refreshed auth withholds telemetry and prevents a confirmed harness receipt', async t => {
  const { parent, records, options, input } = fixture(t);
  const open = options.runtime.openTrustedProcess;
  options.runtime.openTrustedProcess = async request => {
    const session = await open(request);
    writeFileSync(join(request.env.CODEX_HOME, 'auth.json'), '{invalid refreshed auth', { mode: 0o600 });
    return session;
  };
  const harness = createCodexHarness(options);
  await harness.execute(input);
  assert.equal(records[0].transcript, '');
  assert.equal(records[0].captureComplete, false);
  await assert.rejects(harness.close(), /cleanup-unconfirmed/);
  assert.deepEqual(readdirSync(parent), ['.owner', 'workspace']);
});


test('nested repository Git metadata receives the same deny rule as the main checkout', async t => {
  const { options, input } = fixture(t);
  const open = options.runtime.openTrustedProcess;
  options.runtime.openTrustedProcess = async request => {
    const config = readFileSync(join(request.env.CODEX_HOME, 'config.toml'), 'utf8');
    assert.ok(config.includes(JSON.stringify(input.worker.workspace + '/repository/packages/nested/.git') + ' = "deny"'));
    return open(request);
  };
  input.worker.run = async request => request.command === '/usr/bin/find'
    ? input.worker.workspace + '/repository/.git\0' + input.worker.workspace + '/repository/packages/nested/.git\0'
    : request.args.includes('--version') ? 'codex-cli 0.164.0' : '';
  const harness = createCodexHarness(options);
  await harness.execute(input); await harness.close();
});


test('controller cwd must be explicitly bound, empty, and owned before credentials are read', async t => {
  for (const fault of ['missing', 'different', 'populated']) {
    const { calls, options, input } = fixture(t);
    if (fault === 'missing') delete options.controllerWorkspace;
    if (fault === 'different') options.controllerWorkspace = options.parent;
    if (fault === 'populated') writeFileSync(join(input.worker.workspace, 'repository', 'user-file'), 'preserve');
    const harness = createCodexHarness(options);
    await assert.rejects(harness.execute(input), /controller-workspace/);
    assert.equal(calls.includes('credential'), false);
    await harness.close();
    if (fault === 'populated') assert.equal(readFileSync(join(input.worker.workspace, 'repository', 'user-file'), 'utf8'), 'preserve');
  }
});

test('a hash-bound structured invocation keeps schema and last message in the trusted controller', async t => {
  const { options, input } = fixture(t);
  options.invocation = { schemaVersion: 1, search: 'live', maxOutputBytes: 1024,
    responseSchema: JSON.stringify({ type: 'object', properties: { answer: { type: 'string' } }, required: ['answer'], additionalProperties: false }) };
  input.record.inputs.components = [{ name: 'codex-invocation', version: codexInvocationDigest(options.invocation) }];
  const open = options.runtime.openTrustedProcess;
  options.runtime.openTrustedProcess = async request => {
    const schema = request.args[request.args.indexOf('--output-schema') + 1];
    const output = request.args[request.args.indexOf('--output-last-message') + 1];
    assert.equal(schema.startsWith(request.env.CODEX_HOME + '/'), true);
    assert.equal(output.startsWith(request.env.CODEX_HOME + '/'), true);
    assert.equal(readFileSync(schema, 'utf8'), options.invocation.responseSchema);
    assert.match(readFileSync(join(request.env.CODEX_HOME, 'config.toml'), 'utf8'), /web_search = "live"/);
    writeFileSync(output, '{"answer":"review only"}', { mode: 0o600 });
    return open(request);
  };
  const harness = createCodexHarness(options);
  assert.deepEqual(await harness.execute(input), { exitCode: 0, lastMessage: '{"answer":"review only"}' });
  await harness.close();
});

test('caller invocation changes fail before reading OAuth or opening an executor', async t => {
  for (const fault of ['missing', 'changed', 'duplicate', 'invalid', 'removed']) {
    const { options, input, calls } = fixture(t);
    options.invocation = { schemaVersion: 1, search: 'disabled', maxOutputBytes: 1024 };
    const binding = { name: 'codex-invocation', version: codexInvocationDigest(options.invocation) };
    input.record.inputs.components = fault === 'missing' ? [] : [binding];
    if (fault === 'changed') options.invocation.search = 'live';
    if (fault === 'duplicate') input.record.inputs.components.push(binding);
    if (fault === 'invalid') options.invocation.executable = '/host/shell';
    if (fault === 'removed') delete options.invocation;
    const harness = createCodexHarness(options);
    await assert.rejects(harness.execute(input), /codex-invocation/);
    assert.equal(calls.includes('credential'), false);
    await harness.close();
  }
});

test('structured output is bounded and never returns an OAuth value', async t => {
  for (const fault of ['oversize', 'secret', 'missing']) {
    const { options, input, records } = fixture(t);
    options.invocation = { schemaVersion: 1, search: 'disabled', maxOutputBytes: 32 };
    input.record.inputs.components = [{ name: 'codex-invocation', version: codexInvocationDigest(options.invocation) }];
    const open = options.runtime.openTrustedProcess;
    options.runtime.openTrustedProcess = async request => {
      const output = request.args[request.args.indexOf('--output-last-message') + 1];
      if (fault !== 'missing') writeFileSync(output, fault === 'secret' ? 'synthetic-new-access' : 'x'.repeat(33), { mode: 0o600 });
      return open(request);
    };
    const harness = createCodexHarness(options);
    await assert.rejects(harness.execute(input), /codex-result/);
    if (fault === 'secret') assert.equal(records[0].transcript.includes('synthetic-new-access'), false);
    await harness.close();
  }
});
