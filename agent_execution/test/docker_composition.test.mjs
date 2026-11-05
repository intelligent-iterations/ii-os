import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash } from 'node:crypto';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { createDockerExecution } from '../src/providers/docker/execution.mjs';
import { inputs } from './fixtures/inputs.mjs';

test('Docker composition rejects missing placement or an unapproved binding before filesystem or credential access', async () => {
  const runtime = await loadInstalledRuntime();
  const value = inputs(); value.configuration.environment.userNamespaces = true; value.configuration.environment.diskGiB = 1;
  const revision = 'b27525b30fc7c709b41fc8c62de4a4eb699f9827';
  const binding = { schemaVersion: 1, hosting: 'github', isolation: 'docker', workspace: '/workspace',
    workspaceHelperImage: 'fixture/disk@sha256:' + 'c'.repeat(64), namespacePolicyImage: 'fixture/policy@sha256:' + 'a'.repeat(64), runtimeRevision: revision, codexExecutable: '/trusted/codex', executablePath: '/usr/local/bin:/usr/bin:/bin' };
  const digest = 'sha256:' + createHash('sha256').update(runtime.canonicalJson(binding)).digest('hex');
  value.components = [{ name: 'runtime', version: revision }, { name: 'execution-binding', version: digest }];
  const record = runtime.createExecutionInputRecord(value, { executionId: 'run-1', attemptId: '1' });
  await assert.rejects(createDockerExecution({ record }), /unsupported-execution-binding/);
  await assert.rejects(createDockerExecution({ record, binding: { ...binding, runtimeRevision: 'b'.repeat(40) } }), /execution-binding-mismatch/);
  await assert.rejects(createDockerExecution({ record, binding }), /execution-provider-unavailable/);
});
