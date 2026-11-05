import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import * as configuration from '@intelligent-iterations/ii-agent-runtime/runtime';
import { workerResources } from '@intelligent-iterations/ii-agent-runtime/pipeline';
import { inputs } from './fixtures/inputs.mjs';
import { openExecutionHistory } from '../src/providers/local/history.mjs';

const runtime = { ...configuration, workerResources };

function fixture(t) {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'runtime-history-'));
  const owner = randomUUID(); writeFileSync(join(parent, '.owner'), owner);
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  const identity = { executionId: 'run-1', attemptId: '1' };
  const options = { parent, runtime, ...identity, secretValues: ['synthetic-private-value'] };
  const record = runtime.createExecutionInputRecord(inputs(), identity);
  return { options, record };
}

test('retained inputs and outcome survive restart without rewriting immutable records', async t => {
  const { options, record } = fixture(t);
  const history = openExecutionHistory(options);
  const first = await history.retainInputs(record);
  assert.deepEqual(await history.retainInputs(record), first);
  const outcome = { executionId: record.executionId, attemptId: record.attemptId,
    inputDigest: record.inputDigest, cleanupConfirmed: true, cleanup: [], status: 'completed' };
  await history.retainOutcome(outcome);
  const reopened = openExecutionHistory(options);
  assert.deepEqual(reopened.readInputs(), record);
  assert.deepEqual(reopened.readOutcome(), outcome);
  await assert.rejects(reopened.retainOutcome({ ...outcome, status: 'failed' }), /immutable-history-conflict/);
});

test('another attempt, input identity, or credential value cannot enter retained telemetry', async t => {
  const { options, record } = fixture(t), history = openExecutionHistory(options);
  await history.retainInputs(record);
  for (const change of [{ attemptId: '2' }, { inputDigest: 'other' }, { transcript: 'synthetic-private-value' }]) {
    await assert.rejects(history.retainTelemetry({ executionId: record.executionId, attemptId: record.attemptId,
      inputDigest: record.inputDigest, transcript: 'safe', ...change }));
  }
  await history.retainTelemetry({ executionId: record.executionId, attemptId: record.attemptId,
    inputDigest: record.inputDigest, transcript: 'safe' });
});

test('corrupted retained input cannot be reused for later observations', async t => {
  const { options, record } = fixture(t), history = openExecutionHistory(options);
  await history.retainInputs(record);
  writeFileSync(join(history.directory, 'inputs.json'), JSON.stringify({ ...record, inputDigest: 'tampered' }));
  assert.throws(() => history.readInputs(), /history-input-integrity/);
});


test('bounded large telemetry survives restart as hashed chunks and detects tampering', async t => {
  const { options, record } = fixture(t), history = openExecutionHistory(options);
  await history.retainInputs(record);
  const telemetry = { executionId: record.executionId, attemptId: record.attemptId,
    inputDigest: record.inputDigest, transcript: '🙂tool output\n'.repeat(150000), captureComplete: true, exitCode: 0 };
  await history.retainTelemetry(telemetry);
  const reopened = openExecutionHistory(options);
  assert.deepEqual(reopened.readTelemetry(), telemetry);
  const index = JSON.parse(readFileSync(join(history.directory, 'telemetry.json'), 'utf8'));
  writeFileSync(join(history.directory, index.chunks[0].name), '{"text":"changed"}');
  assert.throws(() => reopened.readTelemetry(), /telemetry-integrity/);
});


test('successful state receipts survive restart and cannot be reused for another payload', async t => {
  const { options, record } = fixture(t), history = openExecutionHistory(options);
  await history.retainInputs(record);
  const receipt = { executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest,
    state: 'running', observerAttempt: '1', payloadDigest: 'sha256:' + 'a'.repeat(64), status: 'execution_running' };
  assert.equal(history.readState('running', receipt.payloadDigest), null);
  await history.retainState(receipt);
  assert.deepEqual(openExecutionHistory(options).readState('running', receipt.payloadDigest), receipt);
  assert.throws(() => history.readState('running', 'sha256:' + 'b'.repeat(64)), /state-conflict/);
});

test('failure, cancellation and uncertainty receipts remain bound after restart', async t => {
  const { options, record } = fixture(t), history = openExecutionHistory(options);
  await history.retainInputs(record);
  for (const state of ['failed', 'cancelled', 'unknown']) {
    const receipt = { executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest,
      state, observerAttempt: '1', payloadDigest: 'sha256:' + 'a'.repeat(64), status: 'execution_' + state };
    await history.retainState(receipt);
    assert.deepEqual(openExecutionHistory(options).readState(state, receipt.payloadDigest), receipt);
  }
});

test('the actual runtime teardown reference survives restart and cannot change resource or run ownership', async t => {
  const { options, record } = fixture(t), history = openExecutionHistory(options);
  await history.retainInputs(record);
  const reference = { backend: 'docker-tofu', owner: 'a'.repeat(32), resources: runtime.workerResources(runtime.compileConfiguration(record.inputs.configuration)) };
  await history.retainRuntimeCheckpoint({ phase: 'preparing', reference });
  await history.retainRuntimeCheckpoint({ phase: 'provisioning', reference });
  const reopened = openExecutionHistory(options);
  assert.deepEqual(reopened.readRuntimeCheckpoint(), { phase: 'provisioning', reference });
  await assert.rejects(reopened.retainRuntimeCheckpoint({ phase: 'cleaned', reference: { ...reference, owner: 'b'.repeat(32) } }), /reference-conflict/);
  await assert.rejects(reopened.retainRuntimeCheckpoint({ phase: 'cleaned', reference: { ...reference, resources: { ...reference.resources, cpu: 4 } } }), /resource-mismatch/);
  await reopened.retainRuntimeCheckpoint({ phase: 'cleaned', reference });
  assert.equal(openExecutionHistory(options).readRuntimeCheckpoint().phase, 'cleaned');
});

test('collection survives a crash before the final outcome and recovery never rewrites the original outcome', async t => {
  const { options, record } = fixture(t), history = openExecutionHistory(options);
  await history.retainInputs(record);
  const metadata = { executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest };
  const collection = { resultArtifact: { reference: 'fixture:result', digest: 'sha256:' + 'a'.repeat(64), bytes: 10 } };
  await history.retainCollection({ ...metadata, collection });
  const original = { ...metadata, status: 'cleanup-unconfirmed', cleanupConfirmed: false, cleanup: [{ component: 'runtime', confirmed: false }] };
  await history.retainOutcome(original);
  const reopened = openExecutionHistory(options);
  assert.deepEqual(reopened.readCollection(), collection);
  const recovered = { ...metadata, status: 'failed', cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true }], result: collection };
  await reopened.retainRecoveryOutcome(recovered);
  assert.deepEqual(openExecutionHistory(options).readRecoveryOutcome(), recovered);
  assert.deepEqual(reopened.readOutcome(), original);
  await assert.rejects(reopened.retainRecoveryOutcome({ ...recovered, cleanupConfirmed: false }), /cleanup-proof-required/);
});
