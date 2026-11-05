// The kit's runtime files, profile examples and controllers against the real
// ii-os agent_execution package (installed with `npm ci` in agent_execution).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, readdirSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const kit = fileURLToPath(new URL('../../', import.meta.url));
const execution = process.env.II_OS_AGENT_EXECUTION_DIR ?? realpathSync(join(kit, '..', '..', 'agent_execution'));
const load = relative => import(pathToFileURL(join(execution, relative)).href);
const { loadInstalledRuntime } = await load('src/providers/agent_runtime/installed.mjs');
const { resolveApprovedRuntime } = await load('src/runtime_profile.mjs');
const runtime = await loadInstalledRuntime();
const sha256 = value => createHash('sha256').update(value).digest('hex');
const privateDirectory = () => realpathSync(mkdtempSync(join(tmpdir(), 'ii-os-kit-')));

test('every profile example resolves through agent_execution at a frozen revision', async () => {
  const revision = 'a'.repeat(40);
  const directory = join(kit, 'docs', 'agent-permission-examples');
  const names = readdirSync(directory).filter(name => name.endsWith('.json')).sort();
  assert.deepEqual(names, ['pull-request-author.json', 'pull-request-reviewer.json', 'repository-maintainer.json']);
  for (const name of names) {
    const profile = JSON.parse(readFileSync(join(directory, name), 'utf8'));
    const permissionDigest = sha256(runtime.canonicalJson(profile));
    const resolved = await resolveApprovedRuntime({ profile, permissionDigest, sourceRevision: revision, runtime,
      readArtifact: async (path, context) => {
        assert.equal(context.commit, revision);
        return readFileSync(join(kit, path));
      } });
    assert.equal(resolved.compiled.configuration.harness.name, 'codex');
    assert.equal(resolved.binding.runtimeRevision, runtime.installedRevision);
    assert.equal(resolved.binding.hosting, 'github');
    assert.equal(resolved.binding.isolation, 'docker');
    // Credentials are references; no value lives in configuration.
    for (const reference of resolved.compiled.configuration.credentialBindings) assert.equal(reference.provider, 'github-actions');
    // A changed runtime file invalidates the approval instead of being adopted.
    await assert.rejects(resolveApprovedRuntime({ profile, permissionDigest, sourceRevision: revision, runtime,
      readArtifact: async path => Buffer.concat([readFileSync(join(kit, path)), Buffer.from(' ')]) }), /runtime-profile-artifact-mismatch/);
  }
});

test('codex verification configuration carries only the OAuth reference', () => {
  const compiled = runtime.compileConfigurationText(readFileSync(join(kit, '.ii-os/runtimes/codex-verification.json'), 'utf8'), 'json');
  assert.deepEqual(compiled.configuration.credentialBindings.map(value => value.assignment), ['harness.codex.oauth']);
  assert.equal(compiled.configuration.harness.version, JSON.parse(readFileSync(join(kit, '.ii-os/agent-controller.json'), 'utf8')).codexVersion);
});

test('ticket controller failures are sanitized and never echo the envelope', () => {
  const state = privateDirectory(), admission = privateDirectory(), scratch = privateDirectory();
  const secret = 'oidc-request-token-must-not-be-echoed';
  const child = spawnSync(process.execPath, [join(kit, 'scripts/agent/runtime_ticket_controller.mjs')], {
    input: JSON.stringify({ settings: { mode: 'execute', controllerAttempt: 1, identity: { repositoryId: 1, runId: 2, runAttempt: 1 },
      oidc: { requestToken: secret } }, handoff: { directory: '/nonexistent' } }),
    env: { PATH: process.env.PATH, II_OS_CONTROLLER_STATE_DIR: state, II_OS_CONTROLLER_ADMISSION_DIR: admission,
      II_OS_CONTROLLER_SCRATCH_DIR: scratch, II_OS_AGENT_EXECUTION_DIR: execution },
    encoding: 'utf8' });
  assert.equal(child.status, 1);
  assert.ok(!child.stdout.includes(secret) && !child.stderr.includes(secret));
  const receipt = JSON.parse(child.stdout);
  assert.equal(receipt.error, 'agent_runtime_controller_failed');
  assert.equal(receipt.credentialCleanupConfirmed, false);
  assert.equal(receipt.execution, undefined);
});

test('the callback budget is charged only from the controller-owned context', () => {
  const state = privateDirectory(), admission = privateDirectory(), scratch = privateDirectory();
  const child = spawnSync(process.execPath, [join(kit, 'scripts/agent/codex_credential_rotation.mjs'), 'charge'], {
    env: { PATH: process.env.PATH, II_OS_CONTROLLER_STATE_DIR: state, II_OS_CONTROLLER_ADMISSION_DIR: admission,
      II_OS_CONTROLLER_SCRATCH_DIR: scratch, II_OS_AGENT_EXECUTION_DIR: execution,
      II_OS_CREDENTIAL_BUDGET_CONTEXT: join(scratch, 'context.json') }, encoding: 'utf8' });
  assert.notEqual(child.status, 0);
  assert.match(child.stderr, /credential-budget-path-invalid/);
});

test('credential write-back requires an https ii-os connector', async () => {
  process.env.II_OS_CONTROLLER_STATE_DIR = privateDirectory();
  process.env.II_OS_CONTROLLER_ADMISSION_DIR = privateDirectory();
  process.env.II_OS_CONTROLLER_SCRATCH_DIR = privateDirectory();
  process.env.II_OS_AGENT_EXECUTION_DIR = execution;
  const { createCredentialRotation } = await import(pathToFileURL(join(kit, 'scripts/agent/codex_credential_rotation.mjs')).href);
  const identity = { repository: 'acme-co/example-app', repositoryId: 1, runId: 2, runAttempt: 1,
    workspaceId: 'acme-workspace', projectItemId: 'PVTI_example', dispatchId: 'human:example', issueNumber: 7 };
  for (const connector of ['http://ii-os.example.com/api', 'https://user:pass@ii-os.example.com/api', 'https://ii-os.example.com/api/', undefined]) {
    assert.throws(() => createCredentialRotation({ runtime, kind: 'work-ticket', identity, connector }), /connector-url-invalid/);
  }
  assert.doesNotThrow(() => createCredentialRotation({ runtime, kind: 'work-ticket', identity, connector: 'https://ii-os.example.com/api' }));
});
