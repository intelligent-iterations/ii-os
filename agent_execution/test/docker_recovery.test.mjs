import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { openExecutionHistory } from '../src/providers/local/history.mjs';
import { createDockerRecovery } from '../src/providers/docker/recovery.mjs';
import { inputs } from './fixtures/inputs.mjs';

async function fixture(t) {
  const parent = mkdtempSync(join(realpathSync('/tmp'), 'docker-recovery-')), owner = randomUUID();
  writeFileSync(join(parent, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(parent, '.owner'), 'utf8'), owner); rmSync(parent, { recursive: true }); });
  const installed = await loadInstalledRuntime(), calls = [], controller = 'c'.repeat(64), daemon = 'fixture-daemon-001';
  const binding = { runtimeRevision: installed.installedRevision, executablePath: '/usr/bin:/bin',
    namespacePolicyImage: 'fixture/policy@sha256:' + 'a'.repeat(64), workspaceHelperImage: 'fixture/helper@sha256:' + 'b'.repeat(64) };
  const value = inputs();
  value.components.push({ name: 'controller-instance', version: controller }, { name: 'controller-daemon', version: daemon },
    { name: 'execution-binding', version: 'sha256:' + createHash('sha256').update(installed.canonicalJson(binding)).digest('hex') });
  const record = installed.createExecutionInputRecord(value, { executionId: 'fixture-run', attemptId: '1' });
  const history = openExecutionHistory({ parent, runtime: installed, executionId: record.executionId, attemptId: record.attemptId });
  await history.retainInputs(record);
  await history.retainRuntimeCheckpoint({ phase: 'provisioning', reference: { owner: 'a'.repeat(32),
    resources: installed.workerResources(installed.compileConfiguration(value.configuration)) } });
  await history.retainCollection({ executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest,
    collection: { resultArtifact: { reference: 'fixture:result' } } });
  let present = false, actualDaemon = daemon;
  const runtime = { ...installed,
    runTrustedProcess: async request => { calls.push(request.args[0]); assert.equal(request.env.OPENAI_API_KEY, undefined);
      return request.args[0] === 'info' ? JSON.stringify(actualDaemon) : present ? controller + '\n' : ''; },
    recoverDockerTarget: async options => { calls.push('teardown');
      assert.equal(options.state.reference.owner, 'a'.repeat(32));
      assert.equal(options.expected.configurationDigest, installed.workerResources(installed.compileConfiguration(value.configuration)).configurationDigest);
      await options.checkpoint({ ...options.state, phase: 'cleaned' });
    },
  };
  const options = { runtime, record, binding, historyParent: parent, runtimeParent: parent,
    onState: async update => calls.push(update.state), reportUsage: async report => {
      calls.push('usage'); assert.equal(report.exitCode, null); return { reported: true, totalTokens: 0 };
    } };
  const reservation = { executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest, reservationId: randomUUID() };
  return { options, reservation, history, calls, setPresent: value => { present = value; }, setDaemon: value => { actualDaemon = value; } };
}

test('fresh cleanup uses the retained runtime reference and result without any model launch', async t => {
  const { options, reservation, history, calls } = await fixture(t);
  const outcome = await createDockerRecovery(options).reconcile(reservation);
  assert.equal(outcome.cleanupConfirmed, true);
  assert.deepEqual(outcome.result, history.readCollection());
  assert.equal(history.readRuntimeCheckpoint().phase, 'cleaned');
  assert.deepEqual(calls, ['info', 'ps', 'cleaning', 'teardown', 'usage', 'cleaned']);
  assert.deepEqual(history.readRecoveryOutcome(), outcome);
  calls.length = 0;
  assert.deepEqual(await createDockerRecovery(options).reconcile(reservation), outcome);
  assert.deepEqual(calls, ['cleaned']);
});

test('a still-present original controller and a different daemon cannot acquire cleanup authority', async t => {
  const { options, reservation, calls, setPresent, setDaemon } = await fixture(t);
  setPresent(true);
  assert.equal(await createDockerRecovery(options).reconcile(reservation), null);
  assert.deepEqual(calls, ['info', 'ps']);
  calls.length = 0; setDaemon('another-daemon');
  await assert.rejects(createDockerRecovery(options).reconcile(reservation), /daemon-mismatch/);
  assert.deepEqual(calls, ['info']);
});

test('failed teardown retains the reservation and never records confirmed cleanup', async t => {
  const { options, reservation, history } = await fixture(t);
  options.runtime.recoverDockerTarget = async () => { throw Error('unconfirmed cleanup'); };
  await assert.rejects(createDockerRecovery(options).reconcile(reservation));
  assert.equal(history.readRecoveryOutcome(), null);
  assert.equal(history.readRuntimeCheckpoint().phase, 'provisioning');
  await assert.rejects(createDockerRecovery(options).reconcile({ ...reservation, inputDigest: 'other' }), /reservation-mismatch/);
});

test('callback failure does not block teardown and its confirmed result can be redelivered', async t => {
  const { options, reservation, history, calls } = await fixture(t);
  options.onState = async state => { calls.push(state.state); throw Error('offline callback'); };
  await assert.rejects(createDockerRecovery(options).reconcile(reservation));
  assert.equal(history.readRecoveryOutcome().cleanupConfirmed, true);
  assert.ok(calls.includes('teardown'));
  options.onState = async state => calls.push(state.state);
  assert.equal((await createDockerRecovery(options).reconcile(reservation)).cleanupConfirmed, true);
});

test('a reporting outage can recover after cleanup without repeating teardown or model work', async t => {
  const { options, reservation, calls } = await fixture(t);
  options.reportUsage = async () => { throw Error('reporter offline'); };
  assert.equal((await createDockerRecovery(options).reconcile(reservation)).status, 'usage-unconfirmed');
  calls.length = 0;
  options.reportUsage = async () => { calls.push('usage'); return { reported: true }; };
  assert.equal((await createDockerRecovery(options).reconcile(reservation)).usage.reported, true);
  assert.deepEqual(calls, ['usage', 'cleaned']);
  calls.length = 0;
  await createDockerRecovery(options).reconcile(reservation);
  assert.deepEqual(calls, ['cleaned']);
});
