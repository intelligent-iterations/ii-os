import assert from 'node:assert/strict';
import { test } from 'node:test';
import { randomUUID } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { runCodexCredentialVerification } from '../src/providers/codex/verification.mjs';
import { inputs } from './fixtures/inputs.mjs';

function fixture(t) {
  const root = mkdtempSync(join(realpathSync('/tmp'), 'verification-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(root, '.owner'), 'utf8'), owner); rmSync(root, { recursive: true }); });
  const configuration = inputs().configuration;
  configuration.environment = { ...configuration.environment, userNamespaces: true, diskGiB: 8 };
  const reference = { provider: 'github-actions', resource: 'fixture/project', key: 'OAUTH', assignment: 'harness.codex.oauth' };
  configuration.credentialBindings = [reference];
  for (const name of ['state', 'scratch']) mkdirSync(join(root, name), { mode: 0o700 });
  return { mode: 'execute', kind: 'codex-auth-verify',
    identity: { repository: 'fixture/project', repositoryId: 42, runId: 100, runAttempt: 1 },
    stateDirectory: join(root, 'state'), scratchDirectory: join(root, 'scratch'), configuration,
    controller: { id: 'c'.repeat(64), daemon: 'fixture-daemon' },
    binding: { schemaVersion: 1, hosting: 'github', isolation: 'docker', workspace: '/workspace',
      namespacePolicyImage: configuration.environment.image, workspaceHelperImage: configuration.environment.image,
      runtimeRevision: 'b27525b30fc7c709b41fc8c62de4a4eb699f9827', executablePath: '/usr/bin:/bin', codexExecutable: '/trusted/codex' },
    credentialBinding: reference, credentialProvider: { id: 'github-actions', resolve: async () => assert.fail('credential must remain unopened') },
    authorize: async () => false };
}

test('credential verification refuses absent approval before credentials or infrastructure', async t => {
  await assert.rejects(runCodexCredentialVerification(fixture(t)), /approval-denied/);
});

test('the credential-only reporting exemption cannot be selected by a ticket run', async t => {
  const options = fixture(t); options.kind = 'work-ticket';
  await assert.rejects(runCodexCredentialVerification(options), /invocation-invalid/);
});

test('retry can only recover original credential verification, never start another smoke', async t => {
  const options = fixture(t); options.identity.runAttempt = 2;
  await assert.rejects(runCodexCredentialVerification(options), /invocation-invalid/);
  options.mode = 'recover';
  await assert.rejects(runCodexCredentialVerification(options), error => error.code === 'ENOENT');
});
