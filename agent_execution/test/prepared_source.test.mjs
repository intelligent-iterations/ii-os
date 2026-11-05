import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { preparedTreeManifest, createPreparedSourceVerifier } from '../src/providers/local/prepared_source.mjs';

function fixture(t) {
  const root = mkdtempSync(join(realpathSync('/tmp'), 'prepared-'));
  const owner = randomUUID(); writeFileSync(join(root, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(root, '.owner'), 'utf8'), owner); rmSync(root, { recursive: true }); });
  const directory = join(root, 'repository'); mkdirSync(directory);
  mkdirSync(join(directory, 'empty')); mkdirSync(join(directory, '.git'));
  writeFileSync(join(directory, 'space and ü.txt'), 'source');
  writeFileSync(join(directory, '.git', 'binary'), Buffer.from([0, 1, 255]));
  symlinkSync('space and ü.txt', join(directory, 'link'));
  const manifest = preparedTreeManifest(directory);
  const record = { inputs: { artifacts: [{ role: 'prepared-tree', artifact: { reference: 'fixture:tree', digest: manifest.digest, bytes: manifest.bytes } }] } };
  const worker = { workspace: root, run: async request => execFileSync('python3', request.args, { timeout: request.timeoutMs, maxBuffer: request.maxOutputBytes }).toString() };
  return { root, directory, manifest, record, worker, deadlineMs: Date.now() + 10000, signal: new AbortController().signal };
}

test('host and guest implementations agree on real files, Unicode, binary data, empty directories and links', async t => {
  const input = fixture(t), verifier = createPreparedSourceVerifier();
  await verifier.verifyLocal(input); await verifier.verifyWorker(input);
  assert.match(input.manifest.digest, /^sha256:[a-f0-9]{64}$/);
});

test('changed prepared contents fail both host and guest verification', async t => {
  const input = fixture(t), verifier = createPreparedSourceVerifier();
  writeFileSync(join(input.directory, 'space and ü.txt'), 'changed');
  await assert.rejects(verifier.verifyLocal(input), /identity-mismatch/);
  await assert.rejects(verifier.verifyWorker(input), /identity-mismatch/);
});

test('escaping symlinks and absent input binding fail closed', async t => {
  const input = fixture(t), verifier = createPreparedSourceVerifier();
  input.record.inputs.artifacts = [];
  await assert.rejects(verifier.verifyLocal(input), /identity-missing/);
  symlinkSync('../.owner', join(input.directory, 'escape'));
  assert.throws(() => preparedTreeManifest(input.directory), /link-escape/);
});
