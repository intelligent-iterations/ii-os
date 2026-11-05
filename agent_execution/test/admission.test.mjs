import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { openAdmission } from '../src/providers/local/admission.mjs';

function fixture(t) {
  const directory = mkdtempSync(join(realpathSync('/tmp'), 'ar-admission-'));
  const owner = randomUUID(); writeFileSync(join(directory, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(directory, '.owner'), 'utf8'), owner); rmSync(directory, { recursive: true }); });
  const options = { directory, allocationId: 'explicit-partition', monthlyLimit: 1000, capacity: { cpu: 2, memoryMiB: 4096, diskGiB: 40 } };
  const request = { executionId: 'run-1', attemptId: '1', inputDigest: 'sha256:' + 'a'.repeat(64), resources: { ...options.capacity }, policy: { agentId: 'fixture-agent', subjectId: 'fixture-ticket', maxConcurrent: 10, maxRunsPerSubject: 100, maxRunsPerMonth: 1000, timeoutSeconds: 300 } };
  return { options, request };
}

test('explicit prepared runs preserve a ninety minute deadline without allowing an unbounded reservation', t => {
  const { options, request } = fixture(t);
  request.policy.timeoutSeconds = 5400;
  const result = openAdmission(options).reserve(request);
  assert.equal(result.disposition, 'launch');
  assert.equal(Date.parse(result.reservation.expiresAt) - Date.parse(result.reservation.createdAt), 5760000);
  assert.throws(() => openAdmission(options).reserve({ ...request, executionId: 'too-long',
    policy: { ...request.policy, timeoutSeconds: 7201 } }), /invalid-admission-policy/);
});

test('persisted reservations survive a new coordinator and retries cannot launch twice', t => {
  const { options, request } = fixture(t);
  const first = openAdmission(options).reserve(request);
  assert.equal(first.disposition, 'launch');
  const restarted = openAdmission(options);
  const retry = restarted.reserve({ ...request, attemptId: '2' });
  assert.equal(retry.disposition, 'recover');
  assert.equal(retry.reservation.reservationId, first.reservation.reservationId);
  assert.equal(retry.reservation.attemptId, '1');
  assert.equal(restarted.reserve({ ...request, executionId: 'run-2' }).disposition, 'waiting-for-capacity');
  assert.throws(() => restarted.reserve({ ...request, inputDigest: 'sha256:' + 'b'.repeat(64) }), /conflict/);
});

test('capacity is released only by cleanup evidence bound to the original attempt', t => {
  const { options, request } = fixture(t), ledger = openAdmission(options);
  const { reservation } = ledger.reserve(request);
  const proof = { ...request, cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true }] };
  for (const bad of [{ ...proof, cleanupConfirmed: false }, { ...proof, attemptId: '2' },
    { ...proof, cleanup: [] }, { ...proof, cleanup: [...proof.cleanup, { component: 'access', confirmed: false }] }]) {
    assert.throws(() => ledger.release(reservation, bad), /cleanup-proof-required/);
  }
  assert.equal(ledger.reserve({ ...request, executionId: 'run-2' }).disposition, 'waiting-for-capacity');
  assert.equal(ledger.release(reservation, proof).state, 'released');
  assert.equal(ledger.reserve(request).disposition, 'recover');
  assert.equal(ledger.reserve({ ...request, executionId: 'run-2' }).disposition, 'launch');
});

test('a different allocation or capacity cannot reinterpret existing reservations', t => {
  const { options, request } = fixture(t);
  openAdmission(options).reserve(request);
  assert.throws(() => openAdmission({ ...options, allocationId: 'another-partition' }).reserve(request), /binding-mismatch/);
  assert.throws(() => openAdmission({ ...options, capacity: { ...options.capacity, cpu: 4 } }).reserve(request), /binding-mismatch/);
});

test('cleanup does not refund the monthly allocation or per-ticket run allowance', t => {
  for (const scope of ['allocation', 'subject', 'agent']) {
    const { options, request } = fixture(t);
    if (scope === 'allocation') options.monthlyLimit = 1;
    if (scope === 'subject') request.policy.maxRunsPerSubject = 1;
    if (scope === 'agent') request.policy.maxRunsPerMonth = 1;
    const ledger = openAdmission(options), { reservation } = ledger.reserve(request);
    ledger.release(reservation, { ...request, cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true }] });
    const result = ledger.reserve({ ...request, executionId: 'run-2' });
    assert.equal(result.disposition, 'denied');
    assert.equal(result.reason, scope === 'allocation' ? 'allocation-monthly-limit' : scope === 'subject' ? 'subject-limit' : 'agent-monthly-limit');
    assert.equal(ledger.reserve({ ...request, attemptId: '2' }).disposition, 'recover');
  }
});

test('an execution crossing a UTC month boundary consumes both months', t => {
  const { options, request } = fixture(t); options.monthlyLimit = 1;
  let now = new Date('2026-01-31T23:59:00Z'); options.clock = () => now;
  const ledger = openAdmission(options), { reservation } = ledger.reserve(request);
  ledger.release(reservation, { ...request, cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true }] });
  now = new Date('2026-02-10T00:00:00Z');
  assert.equal(ledger.reserve({ ...request, executionId: 'run-2' }).reason, 'allocation-monthly-limit');
  now = new Date('2026-03-01T00:00:00Z');
  assert.equal(ledger.reserve({ ...request, executionId: 'run-2' }).disposition, 'launch');
});

test('callback budget charges attempts before transport and survives retries and coordinator restarts', t => {
  const { options, request } = fixture(t); options.monthlyLimit = 1;
  const ledger = openAdmission(options);
  for (let index = 0; index < 16; index++) assert.equal(ledger.reserveObservation(request).allowed, true);
  assert.deepEqual(openAdmission(options).reserveObservation({ ...request, attemptId: '2' }), { allowed: false, reason: 'execution-observation-limit' });
  assert.deepEqual(ledger.reserveObservation({ ...request, executionId: 'another-run' }), { allowed: false, reason: 'monthly-observation-limit' });
});

test('uncertain callback accounting stops further provider requests', t => {
  const { options, request } = fixture(t), ledger = openAdmission(options);
  ledger.reserveObservation(request);
  writeFileSync(join(options.directory, '.observations-pending.json'), JSON.stringify({ interrupted: true }), { mode: 0o600 });
  assert.throws(() => ledger.reserveObservation(request), /observation-budget-recovery-required/);
});


test('one ticket cannot overlap an unresolved execution even when host capacity remains', t => {
  const { options, request } = fixture(t);
  options.capacity = { cpu: 4, memoryMiB: 8192, diskGiB: 80 };
  const ledger = openAdmission(options); assert.equal(ledger.reserve(request).disposition, 'launch');
  assert.equal(ledger.reserve({ ...request, executionId: 'run-2' }).disposition, 'waiting-for-capacity');
  assert.equal(ledger.reserve({ ...request, executionId: 'run-3', policy: { ...request.policy, subjectId: 'another-ticket' } }).disposition, 'launch');
});
