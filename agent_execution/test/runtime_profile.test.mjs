import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash } from 'node:crypto';
import { resolveApprovedRuntime } from '../src/runtime_profile.mjs';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { inputs } from './fixtures/inputs.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
async function fixture() {
  const runtime = await loadInstalledRuntime();
  const config = Buffer.from(JSON.stringify(inputs().configuration));
  const binding = Buffer.from(JSON.stringify({ runtimeRevision: runtime.installedRevision, hosting: 'github', isolation: 'docker' }));
  const profile = { schema_version: 4, engine: 'codex', id: 'fixture', version: '1', display_name: 'Fixture', description: 'Fixture',
    allowed_actions: ['read'], denied_actions: [], repository_actions: { mode: 'pull_request' },
    workflow: { file: 'ii-os-agent-task.yml', ref: 'dev' }, runtime: {
      configuration: { path: '.ii-os/runtimes/agent.json', sha256: hash(config) },
      execution_binding: { path: '.ii-os/runtimes/compute.json', sha256: hash(binding) },
    } };
  const permissionDigest = hash(runtime.canonicalJson(profile)), calls = [];
  return { runtime, profile, permissionDigest, sourceRevision: 'a'.repeat(40), calls,
    readArtifact: async (path, scope) => { calls.push({ path, scope }); return path.endsWith('/agent.json') ? config : binding; } };
}

test('approved profile resolves exact bytes at the frozen revision and retains reconstructable placement inputs', async () => {
  const input = await fixture(), result = await resolveApprovedRuntime(input);
  assert.equal(input.calls.length, 2);
  assert.ok(input.calls.every(call => call.scope.commit === input.sourceRevision));
  assert.equal(result.binding.runtimeRevision, input.runtime.installedRevision);
  assert.deepEqual(JSON.parse(result.environment.II_OS_EXECUTION_BINDING), result.binding);
  assert.equal(result.compiled.configuration.environment.image, inputs().configuration.environment.image);
});

test('changed approval denies before reads; changed referenced bytes cannot become configuration', async () => {
  const input = await fixture(); input.profile.version = '2';
  await assert.rejects(resolveApprovedRuntime(input), /approval-mismatch/); assert.equal(input.calls.length, 0);
  const changed = await fixture(); changed.readArtifact = async () => Buffer.from('{}');
  await assert.rejects(resolveApprovedRuntime(changed), /artifact-mismatch/);
});

test('escaping refs and floating revisions fail before artifact requests', async () => {
  for (const fault of ['path', 'revision']) {
    const input = await fixture();
    if (fault === 'path') input.profile.runtime.configuration.path = '.ii-os/runtimes/../private.json';
    else input.sourceRevision = 'dev';
    input.permissionDigest = hash(input.runtime.canonicalJson(input.profile));
    await assert.rejects(resolveApprovedRuntime(input)); assert.equal(input.calls.length, 0);
  }
});
