import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chmodSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { createStagedSecretProvider } from '../src/providers/github_actions/staged_secrets.mjs';
import { createExistingUsageReporter } from '../src/providers/github_actions/usage_reporter.mjs';
import { inputs } from './fixtures/inputs.mjs';

const digest = value => createHash('sha256').update(value).digest('hex');
async function fixture(t) {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'workflow-credentials-')), owner = randomUUID();
  writeFileSync(join(parent, '.owner'), owner, { flag: 'wx', mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  const stage = join(parent, 'stage'); mkdirSync(stage, { mode: 0o700 });
  const info = lstatSync(stage), runtime = await loadInstalledRuntime();
  const reference = { provider: 'github-actions', resource: 'fixture/project', key: 'CODEX_AUTH_JSON', assignment: 'harness.codex.oauth' };
  const auth = { tokens: { access_token: 'synthetic-access-token', refresh_token: 'synthetic-refresh-token' } };
  const bytes = JSON.stringify(auth), file = join(stage, 'codex-auth.json'); writeFileSync(file, bytes, { mode: 0o600 });
  const value = inputs(); value.configuration.credentialBindings = [reference]; value.credentials = [reference];
  const record = runtime.createExecutionInputRecord(value, { executionId: 'fixture-run', attemptId: '1' });
  const provider = createStagedSecretProvider({ runtime, record, stage: { directory: stage, device: info.dev, inode: info.ino },
    bindings: [{ reference, filename: 'codex-auth.json', sha256: digest(bytes), open: ({ read }) => ({ read: async () => JSON.parse((await read()).toString('utf8')) }) }] });
  return { parent, stage, file, runtime, record, reference, auth, provider };
}
const context = () => ({ deadlineMs: Date.now() + 10000, signal: new AbortController().signal });

test('the existing staged GitHub secret resolves through the actual runtime assignment check', async t => {
  const { runtime, record, provider, reference, auth } = await fixture(t);
  const resolver = runtime.createCredentialResolver(runtime.compileConfiguration(record.inputs.configuration), provider);
  const handle = await resolver.resolve(record, reference, context());
  assert.deepEqual(await handle.read(), auth);
  assert.equal(handle.replace, undefined, 'a ticket credential has no secret-writer capability');
  await assert.rejects(resolver.resolve(record, { ...reference, assignment: 'usage.report' }, context()));
});

test('a changed credential or directory inode cannot reuse the workflow handoff', async t => {
  for (const fault of ['contents', 'inode', 'permissions', 'link']) {
    const { runtime, record, provider, reference, auth, file, stage } = await fixture(t);
    const resolver = runtime.createCredentialResolver(runtime.compileConfiguration(record.inputs.configuration), provider);
    const handle = await resolver.resolve(record, reference, context());
    if (fault === 'contents') writeFileSync(file, JSON.stringify({ ...auth, changed: true }));
    if (fault === 'permissions') chmodSync(file, 0o644);
    if (fault === 'inode') { renameSync(stage, stage + '-retained'); mkdirSync(stage, { mode: 0o700 }); }
    if (fault === 'link') { renameSync(file, file + '-retained'); symlinkSync(file + '-retained', file); }
    await assert.rejects(handle.read(), undefined, fault);
  }
});

test('a staged provider rejects another execution attempt and observes cancellation before reading', async t => {
  const { provider, record, reference } = await fixture(t);
  await assert.rejects(provider.resolve(reference, { ...record, ...context(), attemptId: '2' }), /execution-mismatch/);
  const abort = new AbortController();
  const handle = await provider.resolve(reference, { ...record, deadlineMs: Date.now() + 10000, signal: abort.signal });
  abort.abort(); await assert.rejects(handle.read(), /interrupted/);
});

test('the usage adapter invokes the existing reporter with private files and a bounded clean environment', async t => {
  const { parent } = await fixture(t), scriptPath = join(parent, 'reporter.mjs');
  writeFileSync(scriptPath, '// trusted reporter fixture', { mode: 0o600 });
  const keyText = 'iiosu_v1.12345678-1234-1234-1234-123456789abc.' + 'a'.repeat(43); // gitleaks:allow -- synthetic fixture key
  let calls = 0;
  const receipt = { reported: true, eventId: 'a'.repeat(64), source: 'codex', model: 'configured-model', totalTokens: 3 };
  const runtime = { runTrustedProcess: async request => {
    calls++;
    assert.equal(request.command, '/trusted/node'); assert.equal(request.args[0], scriptPath); assert.equal(request.args[2], '0');
    assert.equal(readFileSync(request.args[1], 'utf8'), '{"type":"turn.completed"}\n');
    assert.equal(readFileSync(request.env.AGENT_USAGE_KEY_FILE, 'utf8'), keyText);
    assert.equal(lstatSync(request.env.AGENT_USAGE_KEY_FILE).mode & 0o777, 0o600);
    assert.equal(Object.values(request.env).some(value => value.includes(keyText)), false);
    assert.equal(request.env.IIF_JOB_ID, 'fixture-run'); assert.equal(request.env.II_AGENT_BILLING_MODE, 'subscription_included');
    // The public kit reporter reads the execution id only from this name.
    assert.equal(request.env.II_OS_AGENT_EXECUTION_ID, 'fixture-run');
    assert.equal(request.timeoutMs, 30000); assert.equal(request.maxOutputBytes, 65536);
    return JSON.stringify(receipt);
  } };
  const open = createExistingUsageReporter({ runtime, parent, script: { path: scriptPath, sha256: digest(readFileSync(scriptPath)) },
    executable: '/trusted/node', executablePath: '/trusted/bin', endpoint: 'https://fixture.example/api', workspaceId: 'fixture-workspace', executionId: 'fixture-run' });
  const handle = open({ read: async () => Buffer.from(keyText) });
  assert.deepEqual(await handle.report({ transcript: '{"type":"turn.completed"}\n', exitCode: 0, model: 'configured-model', billingMode: 'subscription_included' }), receipt);
  assert.equal(calls, 1);
  const { readdirSync } = await import('node:fs'); assert.equal(readdirSync(parent).some(name => name.startsWith('usage-')), false);
});

test('failure reporting uses the existing reporter and never leaks child errors or retained keys', async t => {
  const { parent } = await fixture(t), scriptPath = join(parent, 'reporter.mjs'); writeFileSync(scriptPath, '// trusted fixture', { mode: 0o600 });
  let called = false;
  const open = createExistingUsageReporter({ runtime: { runTrustedProcess: async request => {
    called = true; assert.equal(request.args[2], '1'); throw Error('synthetic-sensitive-child-detail');
  } }, parent, script: { path: scriptPath, sha256: digest(readFileSync(scriptPath)) }, executable: '/trusted/node', executablePath: '/trusted/bin',
    endpoint: 'https://fixture.example/api', workspaceId: 'fixture-workspace', executionId: 'fixture-run' });
  const key = 'iiosu_v1.12345678-1234-1234-1234-123456789abc.' + 'a'.repeat(43); // gitleaks:allow -- synthetic fixture key
  await assert.rejects(open({ read: async () => Buffer.from(key) }).report({ transcript: '', exitCode: null, billingMode: 'subscription_included' }), /^Error: usage-report-unconfirmed$/);
  assert.equal(called, true);
  const { readdirSync } = await import('node:fs'); assert.equal(readdirSync(parent).some(name => name.startsWith('usage-')), false);
});
