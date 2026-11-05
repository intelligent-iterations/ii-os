// The kit's Codex usage reporter posts one event the ii-os backend accepts and
// prints the exact receipt agent_execution's usage adapter verifies.
// Everything runs offline against a 127.0.0.1 server.
// Set II_OS_AGENT_EXECUTION_DIR to an installed agent_execution package.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const reporterSource = resolve(here, '../../scripts/agent/worker/report-codex-exec-usage.mjs');
const agentExecution = resolve(process.env.II_OS_AGENT_EXECUTION_DIR || join(here, '../../../../agent_execution'));
const backendEvent = resolve(here, '../../../../functions/lib/src/agent_usage_event.dart');
const sha256 = value => createHash('sha256').update(value).digest('hex');
const key = 'iiosu_v1.12345678-1234-1234-1234-123456789abc.' + 'a'.repeat(43); // gitleaks:allow -- synthetic fixture key
const executionId = 'github:4242:100:work-ticket';

// Mirrors AgentUsageEvent.parse of the ii-os backend: unknown keys, bad
// identifiers, missing counts or out-of-window times are rejected there.
const eventKeys = ['schemaVersion', 'eventId', 'occurredAt', 'source', 'eventType', 'executionOrigin', 'model', 'hostId', 'billing', 'sessionFingerprint', 'metrics'];
const countKeys = ['prompts', 'sessions', 'requests', 'inputTokens', 'cachedInputTokens', 'cacheReadInputTokens', 'cacheCreationInputTokens',
  'outputTokens', 'reasoningOutputTokens', 'totalTokens', 'usageEvents', 'claudeOtelRequests', 'claudeStatuslineSamples', 'codexTokenEvents'];
const metricKeys = [...countKeys, 'costUsd', 'apiEquivalentCostUsd', 'actualCostUsd'];
function assertBackendAccepts(event) {
  const identifier = /^[A-Za-z0-9][A-Za-z0-9._:/-]*$/, optional = /^[A-Za-z0-9][A-Za-z0-9._:/@+#-]*$/;
  assert.deepEqual(Object.keys(event).filter(name => !eventKeys.includes(name)), []);
  assert.equal(event.schemaVersion, 'ii.agent-usage.event.v1');
  assert.ok(identifier.test(event.eventId) && event.eventId.length <= 200);
  assert.ok(Math.abs(Date.parse(event.occurredAt) - Date.now()) < 600000);
  assert.ok(['local', 'cloud', 'unknown'].includes(event.executionOrigin));
  assert.ok(identifier.test(event.source) && identifier.test(event.eventType));
  if ('model' in event) assert.ok(optional.test(event.model) && event.model.length <= 160);
  if ('sessionFingerprint' in event) assert.match(event.sessionFingerprint, /^[0-9a-f]{64}$/);
  assert.deepEqual(Object.keys(event.billing).filter(name => !['mode', 'provider', 'plan', 'subscriptionCostUsdMonthly'].includes(name)), []);
  assert.ok(['subscription_included', 'metered_api', 'metered_credits', 'cloud_provider', 'unknown'].includes(event.billing.mode));
  assert.ok(identifier.test(event.billing.provider));
  assert.deepEqual(Object.keys(event.metrics).filter(name => !metricKeys.includes(name)), []);
  for (const name of countKeys) assert.ok(Number.isSafeInteger(event.metrics[name]) && event.metrics[name] >= 0, name);
  for (const name of ['costUsd', 'apiEquivalentCostUsd', 'actualCostUsd']) {
    if (name === 'costUsd' || name in event.metrics) assert.ok(Number.isFinite(event.metrics[name]) && event.metrics[name] >= 0, name);
  }
}

function fixture(t) {
  const root = mkdtempSync(join(realpathSync('/tmp'), 'worker-usage-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(root, '.owner'), 'utf8'), owner); rmSync(root, { recursive: true }); });
  const home = join(root, 'home'); mkdirSync(home, { mode: 0o700 });
  writeFileSync(join(root, 'usage.key'), key, { mode: 0o600 });
  return { root, home };
}

async function server(t, status = 202) {
  const requests = [];
  const listener = createServer((request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      requests.push({ method: request.method, url: request.url, headers: request.headers, body: Buffer.concat(chunks).toString('utf8') });
      response.writeHead(status, { 'content-type': 'application/json' }); response.end('{}');
    });
  });
  await new Promise((done, fail) => { listener.once('error', fail); listener.listen(0, '127.0.0.1', done); });
  t.after(() => new Promise(done => listener.close(done)));
  return { requests, url: `http://127.0.0.1:${listener.address().port}/api` };
}

function report({ root, home }, url, log, overrides = {}, exitStatus = '0') {
  const logPath = join(root, 'codex-' + randomUUID() + '.jsonl'); writeFileSync(logPath, log);
  const env = { HOME: home, CODEX_HOME: home, AGENT_USAGE_KEY_FILE: join(root, 'usage.key'), II_OS_AGENT_USAGE_URL: url,
    II_OS_AGENT_USAGE_WORKSPACE_ID: 'example-workspace', II_OS_AGENT_EXECUTION_ID: executionId, EVALS_EXECUTION_ORIGIN: 'cloud',
    II_AGENT_USAGE_SOURCE: 'codex', II_AGENT_BILLING_MODE: 'subscription_included', II_AGENT_BILLING_PROVIDER: 'openai',
    II_AGENT_MODEL: 'gpt-5.6-sol', ...overrides };
  for (const [name, value] of Object.entries(env)) if (value === undefined) delete env[name];
  return new Promise(done => {
    const child = spawn(process.execPath, [reporterSource, logPath, exitStatus], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '', stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; }); child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('close', code => done({ code, stdout, stderr, log }));
  });
}

const transcript = [
  { type: 'thread.started', thread_id: 'thread-example-1' },
  { type: 'item.completed', item: { type: 'agent_message', text: 'private prompt text must stay local' } },
  { type: 'turn.completed', usage: { input_tokens: 50, cached_input_tokens: 20, output_tokens: 10, reasoning_output_tokens: 3 } },
].map(value => JSON.stringify(value)).join('\n') + '\n';

test('one Codex run posts one backend-valid event and prints the exact receipt', async t => {
  const context = fixture(t), ingest = await server(t);
  const run = await report(context, ingest.url, transcript);
  assert.equal(run.code, 0, run.stderr);
  assert.equal(ingest.requests.length, 1);
  const [request] = ingest.requests;
  assert.equal(request.method, 'POST');
  assert.equal(request.url, '/api/v1/workspaces/example-workspace/agent-usage/events');
  assert.equal(request.headers.authorization, 'Bearer ' + key);
  assert.equal(request.headers['content-type'], 'application/json');
  assert.equal(request.body.includes('private prompt text'), false);
  const body = JSON.parse(request.body);
  assert.deepEqual(Object.keys(body), ['events']); assert.equal(body.events.length, 1);
  const [event] = body.events;
  assertBackendAccepts(event);
  assert.deepEqual(Object.keys(event).sort(), ['billing', 'eventId', 'eventType', 'executionOrigin', 'metrics', 'model', 'occurredAt',
    'schemaVersion', 'sessionFingerprint', 'source']);
  assert.equal(event.eventId, sha256(`${executionId}\n${sha256(transcript)}\n0`));
  assert.equal(event.source, 'codex'); assert.equal(event.eventType, 'codex.exec.completed'); assert.equal(event.executionOrigin, 'cloud');
  assert.equal(event.model, 'gpt-5.6-sol');
  assert.deepEqual(event.billing, { mode: 'subscription_included', provider: 'openai' });
  assert.equal(event.sessionFingerprint, sha256('codex\nthread-example-1'));
  assert.deepEqual(Object.keys(event.metrics).sort(), [...metricKeys].sort());
  assert.deepEqual({ ...event.metrics, costUsd: undefined, apiEquivalentCostUsd: undefined }, { prompts: 1, sessions: 1, requests: 1,
    inputTokens: 50, cachedInputTokens: 20, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 10, reasoningOutputTokens: 3,
    totalTokens: 60, costUsd: undefined, apiEquivalentCostUsd: undefined, actualCostUsd: 0, usageEvents: 1, claudeOtelRequests: 0,
    claudeStatuslineSamples: 0, codexTokenEvents: 1 });
  assert.equal(event.metrics.costUsd, 0.000328); // (30 x 4 + 20 x 0.4 + 10 x 20) / 1e6
  assert.equal(event.metrics.apiEquivalentCostUsd, event.metrics.costUsd);
  // agent_execution's usage adapter accepts exactly these keys.
  const lines = run.stdout.trim().split('\n'); assert.equal(lines.length, 1);
  assert.deepEqual(JSON.parse(lines[0]), { reported: true, eventId: event.eventId, source: 'codex', model: 'gpt-5.6-sol', totalTokens: 60 });
});

test('metered API runs carry the priced cost; a failed run stays a distinct event', async t => {
  const context = fixture(t), ingest = await server(t);
  const log = JSON.stringify({ type: 'turn.completed', usage: { input_tokens: 100000, cached_input_tokens: 50000, output_tokens: 10000 } }) + '\n';
  const priced = await report(context, ingest.url, log, { II_AGENT_MODEL: 'gpt-5.6-luna', II_AGENT_BILLING_MODE: 'metered_api' });
  assert.equal(priced.code, 0, priced.stderr);
  const failed = await report(context, ingest.url, log, { II_AGENT_MODEL: 'gpt-5.6-luna', II_AGENT_BILLING_MODE: 'metered_api' }, '1');
  assert.equal(failed.code, 0, failed.stderr);
  const [first, second] = ingest.requests.map(request => JSON.parse(request.body).events[0]);
  assertBackendAccepts(first); assertBackendAccepts(second);
  assert.equal(first.metrics.costUsd, 0.023); assert.equal(first.metrics.actualCostUsd, 0.023);
  assert.equal(first.eventType, 'codex.exec.completed'); assert.equal(second.eventType, 'codex.exec.failed');
  assert.notEqual(first.eventId, second.eventId);
  assert.equal('sessionFingerprint' in first, false); assert.equal(first.metrics.sessions, 0);
});

test('the same transcript in another execution is another event', async t => {
  const context = fixture(t), ingest = await server(t);
  assert.equal((await report(context, ingest.url, '')).code, 0);
  assert.equal((await report(context, ingest.url, '', { II_OS_AGENT_EXECUTION_ID: 'github:4242:101:work-ticket' })).code, 0);
  const [first, second] = ingest.requests.map(request => JSON.parse(request.body).events[0]);
  assert.notEqual(first.eventId, second.eventId);
  assert.equal(first.metrics.totalTokens, 0); assert.equal(first.metrics.requests, 0);
});

test('an ephemeral run without a model label is priced from the configured model', async t => {
  const context = fixture(t), ingest = await server(t);
  writeFileSync(join(context.home, 'config.toml'), 'model = "gpt-5.6-sol"\napproval_policy = "never"\n');
  const run = await report(context, ingest.url, transcript, { II_AGENT_MODEL: undefined });
  assert.equal(run.code, 0, run.stderr);
  assert.equal(JSON.parse(ingest.requests[0].body).events[0].model, 'gpt-5.6-sol');
  assert.equal(JSON.parse(run.stdout).model, 'gpt-5.6-sol');
});

test('an unknown model still reports tokens and says why it has no rate', async t => {
  const context = fixture(t), ingest = await server(t);
  writeFileSync(join(context.home, 'config.toml'), '[profiles.other]\nmodel = "gpt-5.6-luna"\n');
  const run = await report(context, ingest.url, transcript, { II_AGENT_MODEL: undefined, II_AGENT_BILLING_MODE: 'unknown' });
  assert.equal(run.code, 0, run.stderr);
  assert.match(run.stderr, /could not determine the model/);
  const event = JSON.parse(ingest.requests[0].body).events[0];
  assertBackendAccepts(event);
  assert.equal('model' in event, false); assert.equal(event.metrics.totalTokens, 60); assert.equal(event.metrics.costUsd, 0);
  assert.equal('actualCostUsd' in event.metrics, false);
  assert.equal(JSON.parse(run.stdout).model, null);
});

for (const [name, overrides, reason] of [
  ['a plain-HTTP remote endpoint', { II_OS_AGENT_USAGE_URL: 'http://usage.example.com/api' }, /II_OS_AGENT_USAGE_URL must use HTTPS/],
  ['an endpoint with credentials', { II_OS_AGENT_USAGE_URL: 'https://alice@usage.example.com/api' }, /must not carry credentials/],
  ['an endpoint with a query', { II_OS_AGENT_USAGE_URL: 'https://usage.example.com/api?debug=1' }, /must not carry credentials, a query/],
  ['a missing execution id', { II_OS_AGENT_EXECUTION_ID: undefined }, /II_OS_AGENT_EXECUTION_ID is required/],
  ['a missing workspace', { II_OS_AGENT_USAGE_WORKSPACE_ID: undefined }, /II_OS_AGENT_USAGE_WORKSPACE_ID is required/],
  ['another usage source', { II_AGENT_USAGE_SOURCE: 'opencode' }, /invalid agent usage source/],
  ['an unsupported billing mode', { II_AGENT_BILLING_MODE: 'free' }, /invalid billing mode/],
]) {
  test(`the reporter refuses ${name} before sending anything`, async t => {
    const context = fixture(t), ingest = await server(t);
    const run = await report(context, ingest.url, transcript, overrides);
    assert.notEqual(run.code, 0); assert.match(run.stderr, reason);
    assert.equal(run.stdout, ''); assert.equal(ingest.requests.length, 0);
  });
}

test('a rejected ingest prints no receipt', async t => {
  const context = fixture(t), ingest = await server(t, 400);
  const run = await report(context, ingest.url, transcript);
  assert.notEqual(run.code, 0); assert.equal(run.stdout, ''); assert.equal(ingest.requests.length, 1);
  assert.match(run.stderr, /HTTP 400/);
});

test('agent_execution\'s usage adapter runs the kit reporter and confirms its receipt', async t => {
  const { createExistingUsageReporter } = await import(pathToFileURL(join(agentExecution, 'src/providers/github_actions/usage_reporter.mjs')).href);
  const { loadInstalledRuntime } = await import(pathToFileURL(join(agentExecution, 'src/providers/agent_runtime/installed.mjs')).href);
  const context = fixture(t), ingest = await server(t), runtime = await loadInstalledRuntime();
  const parent = join(context.root, 'reporter'); mkdirSync(parent, { mode: 0o700 });
  const script = join(context.root, 'report-codex-exec-usage.mjs'); copyFileSync(reporterSource, script);
  const node = join(context.root, 'node'); symlinkSync(process.execPath, node);
  const open = createExistingUsageReporter({ runtime, parent, script: { path: script, sha256: sha256(readFileSync(script)) },
    executable: node, executablePath: '/usr/bin:/bin', endpoint: ingest.url, workspaceId: 'example-workspace', executionId });
  const receipt = await open({ read: async () => Buffer.from(key) })
    .report({ transcript, exitCode: 0, model: 'gpt-5.6-sol', billingMode: 'subscription_included' });
  const event = JSON.parse(ingest.requests[0].body).events[0];
  assertBackendAccepts(event);
  assert.deepEqual(receipt, { reported: true, eventId: sha256(`${executionId}\n${sha256(transcript)}\n0`), source: 'codex', model: 'gpt-5.6-sol', totalTokens: 60 });
  assert.equal(event.eventId, receipt.eventId);
});

test('every event and metric key is one the backend source accepts', { skip: existsSync(backendEvent) ? false : 'backend source not in this checkout' }, () => {
  // Read the allowed key sets straight from AgentUsageEvent.parse.
  const source = readFileSync(backendEvent, 'utf8');
  const sets = [...source.matchAll(/_expectKeys\((\w+), const \{([^}]*)\}\)/g)]
    .map(([, target, keys]) => [target, [...keys.matchAll(/'([A-Za-z]+)'/g)].map(match => match[1])]);
  const allowed = target => sets.find(([name]) => name === target)?.[1];
  assert.ok(allowed('json') && allowed('metrics'), 'backend key sets not found');
  for (const name of eventKeys) assert.ok(allowed('json').includes(name), name);
  for (const name of metricKeys) assert.ok(allowed('metrics').includes(name), name);
});
