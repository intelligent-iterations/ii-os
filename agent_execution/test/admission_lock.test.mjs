import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { chmodSync, linkSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { openAdmission } from '../src/providers/local/admission.mjs';

function fixture(t) {
  const directory = mkdtempSync(join(realpathSync('/tmp'), 'admission-lock-')), owner = randomUUID();
  writeFileSync(join(directory, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(directory, '.owner'), 'utf8'), owner); rmSync(directory, { recursive: true }); });
  const options = { directory, allocationId: 'fixture-partition', monthlyLimit: 100,
    capacity: { cpu: 2, memoryMiB: 4096, diskGiB: 40 } };
  const request = { executionId: 'fixture-run', attemptId: '1', inputDigest: 'sha256:' + 'a'.repeat(64), resources: options.capacity,
    policy: { agentId: 'fixture-agent', subjectId: 'fixture-ticket', maxConcurrent: 2, maxRunsPerSubject: 2, maxRunsPerMonth: 100, timeoutSeconds: 300 } };
  return { options, request };
}

test('a killed transaction releases its lock without reclaiming the original reservation', async t => {
  const { options, request } = fixture(t), module = new URL('../src/providers/local/admission.mjs', import.meta.url).href;
  const child = spawn(process.execPath, ['--input-type=module', '--eval', `
    import { openAdmission } from ${JSON.stringify(module)};
    import { writeFileSync, writeSync } from 'node:fs';
    const options = ${JSON.stringify(options)}, request = ${JSON.stringify(request)};
    const first = openAdmission(options).reserve(request);
    writeFileSync(options.directory + '/fixture-result.json', JSON.stringify(first), { mode: 0o600 });
    openAdmission({ ...options, clock: () => {
      writeSync(1, 'locked\\n');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0);
      return new Date();
    } }).reserve({ ...request, executionId: 'fixture-next' });
  `], { stdio: ['ignore', 'pipe', 'pipe'] });
  const exited = new Promise(resolve => child.once('exit', (code, signal) => resolve({ code, signal })));
  t.after(async () => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL'); await exited; });
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += chunk; });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('fixture-lock-timeout: ' + stderr)), 10000);
    child.stdout.once('data', chunk => { clearTimeout(timer); assert.equal(chunk.toString(), 'locked\n'); resolve(); });
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('exit', code => { clearTimeout(timer); reject(Error('fixture-ended-before-lock: ' + code + ' ' + stderr)); });
  });
  const first = JSON.parse(readFileSync(join(options.directory, 'fixture-result.json')));
  const ledger = openAdmission({ ...options, clock: () => new Date('2099-01-01T00:00:00Z') });
  assert.throws(() => ledger.reserve(request), /admission-busy/);
  child.kill('SIGKILL');
  assert.deepEqual(await exited, { code: null, signal: 'SIGKILL' });
  const recovered = ledger.reserve({ ...request, attemptId: '2' });
  assert.equal(recovered.disposition, 'recover');
  assert.deepEqual(recovered.reservation, first.reservation);
  assert.equal(ledger.reserve({ ...request, executionId: 'fixture-next' }).disposition, 'waiting-for-capacity');
  const proof = { ...request, cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true }] };
  assert.equal(ledger.release(first.reservation, proof).state, 'released');
  assert.equal(ledger.reserve({ ...request, executionId: 'fixture-next' }).disposition, 'launch');
});

test('transactions keep one private lock inode rather than unlinking a contended lock', t => {
  const { options, request } = fixture(t), ledger = openAdmission(options);
  ledger.reserve(request);
  const before = lstatSync(join(options.directory, '.lock'));
  assert.ok(before.isFile());
  assert.equal(before.size, 0);
  assert.equal(before.mode & 0o777, 0o600);
  ledger.reserveObservation(request);
  ledger.reserve(request);
  const after = lstatSync(join(options.directory, '.lock'));
  assert.equal(after.ino, before.ino);
  assert.equal(after.dev, before.dev);
});

test('legacy or foreign lock objects are preserved and fail closed', t => {
  for (const kind of ['directory', 'symlink', 'hardlink', 'public-file']) {
    const { options, request } = fixture(t), lock = join(options.directory, '.lock'), target = join(options.directory, 'fixture-lock-target');
    writeFileSync(target, '', { mode: 0o600 });
    if (kind === 'directory') mkdirSync(lock, { mode: 0o700 });
    if (kind === 'symlink') symlinkSync(target, lock);
    if (kind === 'hardlink') linkSync(target, lock);
    if (kind === 'public-file') { writeFileSync(lock, '', { mode: 0o600 }); chmodSync(lock, 0o644); }
    const before = lstatSync(lock);
    assert.throws(() => openAdmission(options).reserve(request), /admission-lock-unsafe/);
    assert.equal(lstatSync(lock).ino, before.ino);
    assert.equal(readFileSync(target, 'utf8'), '');
  }
});
