import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash, randomUUID } from 'node:crypto';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { runGitHubDockerTicket } from '../src/providers/github_actions/controller.mjs';
import { inputs } from './fixtures/inputs.mjs';
import { openExecutionHistory } from '../src/providers/local/history.mjs';
import { openAdmission } from '../src/providers/local/admission.mjs';

async function fixture(t, markers = 'legacy') {
  const root = mkdtempSync(join(realpathSync('/tmp'), 'workflow-controller-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(root, '.owner'), 'utf8'), owner); rmSync(root, { recursive: true }); });
  const directory = name => { const path = join(root, name); mkdirSync(path, { mode: 0o700 }); return path; };
  const runtime = await loadInstalledRuntime(), hash = value => createHash('sha256').update(value).digest('hex');
  const configuration = inputs().configuration;
  configuration.environment = { ...configuration.environment, diskGiB: 40, userNamespaces: true };
  const binding = { runtimeRevision: runtime.installedRevision, executablePath: '/usr/bin:/bin', codexExecutable: '/usr/bin/codex' };
  const runtimeFiles = {}, references = {};
  for (const [name, value] of Object.entries({ configuration, execution_binding: binding })) {
    const path = `.ii-os/runtimes/${name}.json`, text = runtime.canonicalJson(value);
    references[name] = { path, sha256: hash(text) };
    runtimeFiles[path] = { commit: 'b'.repeat(40), base64: Buffer.from(text).toString('base64') };
  }
  const profile = { schema_version: 4, engine: 'codex', id: 'fixture-agent', version: 'fixture', display_name: 'Fixture', description: 'Generic plumbing fixture.',
    allowed_actions: ['Perform fixture work.'], denied_actions: [], repository_actions: { mode: 'pull_request' }, runtime: references,
    workflow: { file: 'ii-os-agent-task.yml', ref: 'dev' } };
  const helpers = {};
  const sources = markers === 'legacy'
    ? { core: '# generic core fixture', status: "# '/iif/job/artifacts/ii-os-agent-result.json'",
      prepare: '# You are running inside a Fleet-managed ephemeral container.\nprintf fixture-prompt > "$IIAUTO_WORK_ROOT/prompt.md"\nprompt_sha="$(file_sha256 "$prompt_file")"' }
    : { core: '# generic core fixture', status: "# '/ii-os-agent/artifacts/ii-os-agent-result.json'",
      prepare: '# You are running inside an agent-runtime ephemeral container.\nprintf fixture-prompt > "$IIAUTO_WORK_ROOT/prompt.md"\nprompt_sha="$(file_sha256 "$prompt_file")"' };
  for (const [name, text] of Object.entries(sources)) {
    const path = join(root, name); writeFileSync(path, text, { mode: 0o600 }); helpers[name] = { path, sha256: hash(text) };
  }
  const approvedPromptFile = join(root, 'approved.json'); writeFileSync(approvedPromptFile, '{}', { mode: 0o600 });
  const options = { mode: 'execute', stateDirectory: directory('state'), scratchDirectory: directory('scratch'), admissionDirectory: directory('admission'),
    identity: { repository: 'fixture/project', repositoryId: 42, runId: 100, runAttempt: 1, issueNumber: 5,
      dispatchId: 'fixture-dispatch', projectItemId: 'fixture-item', workspaceId: 'fixture-workspace' },
    profile, permissionDigest: hash(runtime.canonicalJson(profile)), sourceRevision: 'b'.repeat(40), runtimeFiles, helpers,
    task: { appSlug: 'fixture-bot' }, controller: { id: 'c'.repeat(64), daemon: 'fixture-daemon' }, approvedPromptFile, approvedPromptDigest: hash('{}'),
    repositories: [{ repository: 'fixture/project', commit: 'b'.repeat(40), path: '' }],
    workflow: { reporter: { script: { sha256: 'a'.repeat(64) } } }, authorize: async () => false };
  return options;
}

test('controller denies before Git credentials or runtime acquisition when the existing approval check refuses', async t => {
  const options = await fixture(t); let authorizationChecks = 0;
  options.authorize = async record => {
    authorizationChecks++;
    assert.equal(record.executionId, 'github:42:100:work-ticket');
    assert.equal(record.inputs.prompt.text, 'fixture-prompt');
    return false;
  };
  await assert.rejects(runGitHubDockerTicket(options), /approval-denied/);
  assert.equal(authorizationChecks, 1);
});

test('neutral kit helpers render the approved prompt through the installed runtime process', async t => {
  const options = await fixture(t, 'neutral'); let authorizationChecks = 0;
  options.authorize = async record => {
    authorizationChecks++;
    assert.equal(record.inputs.prompt.text, 'fixture-prompt');
    assert.ok(record.inputs.components.some(component => component.name === 'prompt-helper-status' && component.version === 'sha256:' + options.helpers.status.sha256));
    return false;
  };
  await assert.rejects(runGitHubDockerTicket(options), /approval-denied/);
  assert.equal(authorizationChecks, 1);
});

test('a changed profile file is refused before approval or provider access', async t => {
  const options = await fixture(t); let authorizationChecks = 0;
  options.authorize = async () => { authorizationChecks++; return true; };
  options.runtimeFiles[options.profile.runtime.configuration.path].base64 = Buffer.from('{}').toString('base64');
  await assert.rejects(runGitHubDockerTicket(options), /artifact-mismatch/);
  assert.equal(authorizationChecks, 0);
});

test('another workflow attempt cannot select the new-execution mode', async t => {
  const options = await fixture(t); options.identity.runAttempt = 2;
  await assert.rejects(runGitHubDockerTicket(options), /invocation-invalid/);
  options.mode = 'recover';
  await assert.rejects(runGitHubDockerTicket(options), /preparation-recovery-unconfirmed/);
});

for (const interruptedPhase of ['runtime-profile', 'approved-prompt', 'source-preparation']) {
  test(`crash at ${interruptedPhase} retains preparation ownership and recovers without launching`, async t => {
    const options = await fixture(t); options.authorize = async () => true;
    options.onPhase = phase => { if (phase === interruptedPhase) throw Error('fixture-controller-crash'); };
    await assert.rejects(runGitHubDockerTicket(options), /fixture-controller-crash/);
    const original = JSON.parse(readFileSync(join(options.stateDirectory, 'preparation.json')));
    assert.equal(original.binding.controller.id, options.controller.id);
    let authorizations = 0;
    const retry = { ...options, mode: 'recover', onPhase: undefined, identity: { ...options.identity, runAttempt: 2 },
      authorize: async () => { authorizations++; throw Error('recovery-cannot-authorize-execution'); },
      previousControllersAbsent: { confirmed: true, owner: 'e'.repeat(64), daemon: options.controller.daemon,
        deploymentInputDigest: 'sha256:' + 'f'.repeat(64), originalController: { id: options.controller.id, name: 'ii-os-controller-fixture-1' } } };
    const result = await runGitHubDockerTicket(retry);
    assert.equal(result.disposition, 'recovered'); assert.equal(result.outcome.phase, 'preparation');
    assert.equal(result.outcome.status, 'never-acquired'); assert.equal(result.outcome.cleanupConfirmed, true);
    assert.equal(result.outcome.inputDigest, undefined); assert.equal(result.outcome.usage, undefined);
    assert.equal(authorizations, 0);
  });
}

test('provider startup absence can recover before a torn identity file or credential inputs are opened', async t => {
  const options = await fixture(t);
  writeFileSync(join(options.stateDirectory, 'identity.json'), '{interrupted', { mode: 0o600 });
  options.mode = 'recover'; options.identity.runAttempt = 2;
  options.previousControllersAbsent = { confirmed: true, owner: 'e'.repeat(64), daemon: options.controller.daemon,
    deploymentInputDigest: 'sha256:' + 'f'.repeat(64), originalController: null };
  Object.defineProperty(options, 'workflow', { get() { throw Error('recovery-must-not-open-workflow'); } });
  const result = await runGitHubDockerTicket(options);
  assert.equal(result.outcome.phase, 'preparation'); assert.equal(result.outcome.cleanupConfirmed, true);
  assert.equal(result.outcome.preparation.binding.controller.id, null);
});

for (const refusal of ['allocation-monthly-limit', 'agent-monthly-limit', 'subject-limit', 'waiting-for-capacity']) {
  test(`controller retains ${refusal} absence and recovers it without admission, usage or launch`, async t => {
    const options = await fixture(t), runtime = await loadInstalledRuntime();
    if (refusal === 'agent-monthly-limit') {
      const reference = options.profile.runtime.configuration, artifact = options.runtimeFiles[reference.path];
      const configuration = JSON.parse(Buffer.from(artifact.base64, 'base64'));
      configuration.limits.maxRunsPerMonth = 1;
      const bytes = Buffer.from(runtime.canonicalJson(configuration));
      reference.sha256 = createHash('sha256').update(bytes).digest('hex'); artifact.base64 = bytes.toString('base64');
      options.permissionDigest = createHash('sha256').update(runtime.canonicalJson(options.profile)).digest('hex');
    }
    options.authorize = async () => true;
    options.allocation = { allocationId: 'fixture-partition', monthlyLimit: refusal === 'allocation-monthly-limit' ? 1 : 100,
      capacity: { cpu: 2, memoryMiB: 4096, diskGiB: 40 } };
    options.connector = 'https://control.example/api';
    options.oidc = { audience: 'https://control.example/api/oidc', tokenUrl: 'https://pipelines.actions.githubusercontent.com/idtoken', requestToken: 'synthetic-request' };
    const credentialContexts = [];
    options.onCredentialContext = async ({ record, admission, mode }) => {
      credentialContexts.push({ mode, executionId: record.executionId, inputDigest: record.inputDigest });
      // Credential provider transport uses the same durable debit as states.
      // This fixture owns no handoff to finish during cleanup-only recovery.
      if (mode === 'execute') assert.equal(admission.reserveObservation(record).allowed, true);
    };
    const ledger = openAdmission({ ...options.allocation, directory: options.admissionDirectory });
    const original = ledger.reserve({ executionId: 'original-run', attemptId: '1', inputDigest: 'sha256:' + 'a'.repeat(64),
      resources: options.allocation.capacity, policy: { agentId: refusal === 'waiting-for-capacity' ? 'another-agent' : 'fixture-agent',
        subjectId: 'github:42:issue:5', maxConcurrent: 1, maxRunsPerSubject: 1, maxRunsPerMonth: 10, timeoutSeconds: 300 } });
    assert.equal(original.disposition, 'launch');
    const reservations = () => readdirSync(options.admissionDirectory).filter(name => /^[a-f0-9]{64}\.json$/.test(name))
      .map(name => [name, readFileSync(join(options.admissionDirectory, name), 'utf8')]);
    const before = reservations(); let providerCalls = 0;
    t.mock.method(globalThis, 'fetch', async () => { providerCalls++; throw Error('fixture-callback-unavailable'); });
    const first = await runGitHubDockerTicket(options);
    assert.equal(first.disposition, refusal === 'waiting-for-capacity' ? refusal : 'denied');
    assert.equal(first.outcome.status, 'never-acquired');
    assert.equal(first.outcome.acquired, false); assert.equal(first.outcome.started, false);
    assert.equal(first.outcome.cleanupConfirmed, true);
    assert.deepEqual(first.outcome.cleanup, [{ component: 'runtime', confirmed: true, absent: true }]);
    assert.equal(first.outcome.usage, undefined); assert.equal(first.outcome.result, undefined);
    assert.equal(first.outcome.admission.reason, refusal === 'waiting-for-capacity' ? undefined : refusal);
    assert.deepEqual(reservations(), before); // No new run count, release or refund.
    assert.equal(providerCalls, refusal === 'waiting-for-capacity' ? 1 : 0);
    const history = openExecutionHistory({ parent: join(options.stateDirectory, 'history'), runtime,
      executionId: 'github:42:100:work-ticket', attemptId: '1' });
    assert.deepEqual(history.readOutcome(), first.outcome); assert.equal(history.readRuntimeCheckpoint(), null);
    // Even if admission cannot be consulted, another workflow attempt must
    // recover this terminal refusal rather than reserve or run anything.
    chmodSync(join(options.admissionDirectory, '.lock'), 0o644);
    const retry = await runGitHubDockerTicket({ ...options, mode: 'recover', identity: { ...options.identity, runAttempt: 2 } });
    assert.equal(retry.disposition, 'recovered'); assert.deepEqual(retry.outcome, first.outcome);
    assert.deepEqual(reservations(), before);
    assert.equal(providerCalls, refusal === 'waiting-for-capacity' ? 1 : 0);
    assert.deepEqual(credentialContexts.map(value => value.mode), ['execute', 'recover']);
    assert.equal(credentialContexts[0].executionId, 'github:42:100:work-ticket');
    assert.equal(credentialContexts[0].inputDigest, credentialContexts[1].inputDigest);
  });
}

test('unavailable approved source retains a failed cleaned run and retry never provisions a worker', async t => {
  const options = await fixture(t), runtime = await loadInstalledRuntime();
  const root = dirname(options.approvedPromptFile), hash = value => createHash('sha256').update(value).digest('hex');
  const configuration = inputs().configuration;
  configuration.environment = { ...configuration.environment, diskGiB: 40, userNamespaces: true };
  const ref = (key, assignment) => ({ provider: 'github-actions', resource: 'fixture/project', key, assignment });
  const source = ref('SOURCE_READ', 'source.read'), oauth = ref('OAUTH', 'harness.codex.oauth'), usage = ref('USAGE', 'usage.report');
  configuration.credentialBindings = [source, oauth, usage];
  const executablePath = '/usr/bin:/bin', node = join(root, 'node');
  symlinkSync(process.execPath, node);
  const binding = { schemaVersion: 1, hosting: 'github', isolation: 'docker', workspace: '/workspace',
    namespacePolicyImage: configuration.environment.image, workspaceHelperImage: configuration.environment.image,
    runtimeRevision: runtime.installedRevision, executablePath, codexExecutable: '/usr/bin/codex' };
  for (const [name, value] of Object.entries({ configuration, execution_binding: binding })) {
    const path = options.profile.runtime[name].path, bytes = Buffer.from(runtime.canonicalJson(value));
    options.profile.runtime[name].sha256 = hash(bytes);
    options.runtimeFiles[path].base64 = bytes.toString('base64');
  }
  options.permissionDigest = hash(runtime.canonicalJson(options.profile));
  const stage = join(root, 'stage'); mkdirSync(stage, { mode: 0o700 });
  const usageKey = 'iiosu_v1.12345678-1234-1234-1234-123456789abc.' + 'a'.repeat(43); // gitleaks:allow -- synthetic fixture key
  writeFileSync(join(stage, 'usage.key'), usageKey, { mode: 0o600 });
  const reporter = join(root, 'reporter.mjs');
  const reporterSource = 'console.log(JSON.stringify({reported:true,eventId:"' + 'a'.repeat(64) + '",source:"codex",model:null,totalTokens:0}));';
  writeFileSync(reporter, reporterSource, { mode: 0o600 });
  const stat = statSync(stage);
  options.workflow = { stage: { directory: stage, device: stat.dev, inode: stat.ino },
    // The approved source token is deliberately absent; no Git process or
    // provider request can run. OAuth is never opened on this path either.
    source: { reference: source, filename: 'source.token', sha256: 'a'.repeat(64) },
    oauth: { reference: oauth, filename: 'auth.json', sha256: 'b'.repeat(64) },
    usage: { reference: usage, filename: 'usage.key', sha256: hash(usageKey) },
    reporter: { parent: root, executable: node, executablePath, endpoint: 'https://usage.example', workspaceId: 'fixture-workspace',
      script: { path: reporter, sha256: hash(reporterSource) } } };
  options.allocation = { allocationId: 'fixture-partition', monthlyLimit: 100,
    capacity: { cpu: 4, memoryMiB: 8192, diskGiB: 80 } };
  options.authorize = async () => true;
  options.connector = 'https://control.example/api';
  options.oidc = { audience: 'https://control.example/api/oidc', tokenUrl: 'https://pipelines.actions.githubusercontent.com/idtoken', requestToken: 'synthetic-request' };
  const states = [];
  t.mock.method(globalThis, 'fetch', async (url, request) => {
    if (String(url).startsWith('https://pipelines.actions.githubusercontent.com/')) return Response.json({ value: 'synthetic-oidc' });
    assert.ok(String(url).startsWith('https://control.example/api/'));
    const body = JSON.parse(request.body); states.push(body.state);
    return Response.json({ data: { recorded: true, executionId: body.executionId, status: 'execution_' + body.state } });
  });
  const first = await runGitHubDockerTicket(options);
  assert.equal(first.disposition, 'executed'); assert.equal(first.outcome.status, 'failed');
  assert.equal(first.outcome.started, false); assert.equal(first.outcome.cleanupConfirmed, true);
  assert.equal(first.outcome.usage.reported, true);
  const history = openExecutionHistory({ parent: join(options.stateDirectory, 'history'), runtime,
    executionId: 'github:42:100:work-ticket', attemptId: '1' });
  assert.equal(history.readInputs().inputs.environment.II_OS_SOURCE_PREPARATION_FAILED, 'true');
  assert.equal(history.readRuntimeCheckpoint(), null);
  const retry = await runGitHubDockerTicket({ ...options, mode: 'recover', identity: { ...options.identity, runAttempt: 2 } });
  assert.equal(retry.disposition, 'recovered'); assert.equal(retry.outcome.started, false);
  assert.equal(retry.outcome.cleanupConfirmed, true);
  assert.deepEqual(states, ['accepted', 'failed', 'cleaning', 'cleaned', 'cleaned']);
});
