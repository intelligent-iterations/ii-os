import assert from 'node:assert/strict';
import { test } from 'node:test';
import { coordinateExecution } from '../src/coordinator.mjs';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { inputs } from './fixtures/inputs.mjs';

async function fixture() {
  const runtime = await loadInstalledRuntime(), calls = [], retained = [];
  const request = { inputs: inputs(), executionId: 'fixture-run', attemptId: '1', subjectId: 'fixture-ticket', reservationResources: { cpu: 2, memoryMiB: 4096, diskGiB: 40 } };
  const record = runtime.createExecutionInputRecord(request.inputs, request);
  const reservation = { executionId: record.executionId, attemptId: '1', inputDigest: record.inputDigest };
  const outcome = { ...reservation, cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true }] };
  const ports = { runtime,
    authorize: async () => true,
    admission: { reserve: async () => { calls.push('reserve'); return { disposition: 'launch', reservation }; }, release: async (bound, receipt) => {
      assert.equal(bound, reservation); assert.equal(receipt, outcome); calls.push('release');
    } },
    recovery: { reconcile: async bound => { assert.equal(bound, reservation); calls.push('recover'); return outcome; } },
    retainOutcome: async value => { calls.push('retain'); retained.push(value); },
    createExecutionPorts: async () => { calls.push('compose'); return { run: async () => { calls.push('execute'); return outcome; } }; },
    onState: async event => calls.push(event.state),
  };
  return { ports, request, calls, reservation, outcome, retained };
}

test('coordinator releases a reservation only after confirmed runtime cleanup', async () => {
  for (const cleaned of [true, false]) {
    const { ports, request, calls, outcome } = await fixture(); outcome.cleanupConfirmed = cleaned;
    const result = await coordinateExecution(request, ports);
    assert.equal(result.disposition, 'executed');
    assert.deepEqual(calls, ['reserve', 'accepted', 'compose', 'execute', ...(cleaned ? ['release'] : [])]);
  }
});

test('retried workflow recovers the original attempt without composing or launching another agent', async () => {
  const { ports, request, calls, reservation } = await fixture(); request.attemptId = '2';
  ports.admission.reserve = async () => ({ disposition: 'recover', reservation });
  const result = await coordinateExecution(request, ports);
  assert.equal(result.disposition, 'recovered'); assert.equal(result.outcome.attemptId, '1');
  assert.deepEqual(calls, ['recover', 'release']);
});

test('unknown recovery retains capacity and never relaunches', async () => {
  const { ports, request, calls, reservation } = await fixture();
  ports.admission.reserve = async () => ({ disposition: 'recover', reservation });
  ports.recovery.reconcile = async () => null;
  assert.equal((await coordinateExecution(request, ports)).disposition, 'recovery-required');
  assert.deepEqual(calls, []);
});

test('denial and exhausted capacity prevent construction of execution adapters', async () => {
  const denied = await fixture(); denied.ports.authorize = async () => false;
  assert.equal((await coordinateExecution(denied.request, denied.ports)).disposition, 'denied');
  assert.deepEqual(denied.calls, []);
  const waiting = await fixture(); waiting.ports.admission.reserve = async () => ({ disposition: 'waiting-for-capacity' });
  assert.equal((await coordinateExecution(waiting.request, waiting.ports)).disposition, 'waiting-for-capacity');
  assert.deepEqual(waiting.calls, ['retain', 'accepted', 'waiting-for-capacity']);
});

test('definitive admission refusals retain bound absence without execution, usage or reservation release', async () => {
  for (const admitted of [{ disposition: 'denied', reason: 'allocation-monthly-limit' },
    { disposition: 'denied', reason: 'agent-monthly-limit' }, { disposition: 'denied', reason: 'subject-limit' },
    { disposition: 'waiting-for-capacity' }]) {
    const { ports, request, calls, retained } = await fixture();
    ports.admission.reserve = async () => admitted;
    const result = await coordinateExecution(request, ports), record = ports.runtime.createExecutionInputRecord(request.inputs, request);
    assert.deepEqual(result.outcome, { schemaVersion: 1, executionId: record.executionId, attemptId: record.attemptId,
      inputDigest: record.inputDigest, artifactDigest: record.artifactDigest, started: false, acquired: false,
      phase: 'admission', status: 'never-acquired', admission: admitted, cleanupConfirmed: true,
      cleanup: [{ component: 'runtime', confirmed: true, absent: true }] });
    assert.equal(result.disposition, admitted.disposition);
    assert.deepEqual(retained, [result.outcome]);
    assert.deepEqual(calls, ['retain', ...(admitted.disposition === 'waiting-for-capacity' ? ['accepted', 'waiting-for-capacity'] : [])]);
  }
});

test('capacity callback failure cannot obscure independently retained runtime absence', async () => {
  const { ports, request, calls, retained } = await fixture();
  ports.admission.reserve = async () => ({ disposition: 'waiting-for-capacity' });
  ports.onState = async () => { assert.equal(retained.length, 1); throw Error('callback-unavailable'); };
  const result = await coordinateExecution(request, ports);
  assert.equal(result.outcome.cleanupConfirmed, true);
  assert.equal(result.observationConfirmed, false);
  assert.deepEqual(calls, ['retain']);
});

test('failed absence retention does not return cleanup proof or attempt callbacks', async () => {
  const { ports, request, calls } = await fixture();
  ports.admission.reserve = async () => ({ disposition: 'waiting-for-capacity' });
  ports.retainOutcome = async () => { throw Error('retention-failed'); };
  await assert.rejects(coordinateExecution(request, ports), /retention-failed/);
  assert.deepEqual(calls, []);
});

test('configuration and admission cannot disagree about reserved memory', async () => {
  const { ports, request, calls } = await fixture(); request.reservationResources.memoryMiB = 128;
  await assert.rejects(coordinateExecution(request, ports), /reservation-configuration-mismatch/);
  assert.deepEqual(calls, []);
});
