import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { readWorkerFile, writeWorkerFile } from '../src/providers/agent_runtime/files.mjs';

test('bounded worker transport retains binary bytes and refuses replacement and overflow', async t => {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'worker-files-')), owner = randomUUID();
  writeFileSync(join(parent, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  const runtime = await loadInstalledRuntime();
  const worker = { open: request => runtime.openTrustedProcess({ ...request, cwd: parent, env: { PATH: '/usr/bin:/bin', HOME: parent } }) };
  const context = { timeoutMs: 10000, signal: new AbortController().signal }, path = join(parent, 'bytes');
  const value = Buffer.from([0, 255, 1, 128, 0, 254]);
  await writeWorkerFile(worker, path, value, context);
  assert.deepEqual(await readWorkerFile(worker, path, 32, context), value);
  await assert.rejects(writeWorkerFile(worker, path, Buffer.from('replacement'), context));
  assert.deepEqual(readFileSync(path), value);
  await assert.rejects(readWorkerFile(worker, path, 4, context));
});
