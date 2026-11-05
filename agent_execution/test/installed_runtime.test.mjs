import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadInstalledRuntime, executePreparedAgent } from '../src/providers/agent_runtime/installed.mjs';

import { inputs } from './fixtures/inputs.mjs';

function ports() {
  const states = [], retained = [];
  return {
    states, retained,
    source: { verifyLocal: async () => {}, verifyWorker: async () => {} },
    authorize: async () => true,
    target: { provision: async (resources, context) => {
      assert.equal(resources.memoryMiB, 4096);
      assert.equal(resources.cpu, 2);
      assert.equal(resources.timeoutSeconds, 300);
      assert.match(resources.configurationDigest, /^sha256:[a-f0-9]{64}$/);
      assert.ok(context.signal instanceof AbortSignal);
      return { load: async () => {}, isolate: async () => ({ close: async () => {} }) };
    }, close: async () => {} },
    access: { open: async () => ({}), close: async () => {} },
    harness: { execute: async ({ record, onStarted }) => {
      assert.equal(record.inputs.prompt.text, 'Approved fixture prompt.');
      await onStarted(); return { exitCode: 0 };
    }, close: async () => {}, reportUsage: async () => ({ reported: true }) },
    artifacts: { collect: async () => ({ reference: 'fixture:bundle' }) },
    history: { retainInputs: async record => retained.push(record), retainCollection: async value => retained.push(value), retainOutcome: async outcome => retained.push(outcome) },
    onState: async event => states.push(event),
  };
}

test('installed pinned package compiles and binds configuration, input history and observations', async () => {
  const runtime = await loadInstalledRuntime(), adapters = ports();
  const request = { inputs: inputs(), executionId: 'fixture-run', attemptId: '1', preparedDirectory: '/fixture/prepared' };
  const result = await executePreparedAgent(request, adapters);
  assert.equal(result.status, 'completed');
  assert.equal(result.cleanupConfirmed, true);
  const expected = runtime.createExecutionInputRecord(request.inputs, request);
  assert.deepEqual(adapters.retained[0], expected);
  assert.equal(adapters.retained[2].inputDigest, expected.inputDigest);
  for (const state of adapters.states) {
    assert.equal(state.executionId, request.executionId);
    assert.equal(state.attemptId, request.attemptId);
    assert.equal(state.artifactDigest, expected.artifactDigest);
  }
});

test('real runtime rejects mutable images and known secret values before authorization or provisioning', async () => {
  for (const fault of ['image', 'secret']) {
    const adapters = ports();
    let effects = 0; adapters.authorize = async () => { effects++; return true; };
    const request = { inputs: inputs(), executionId: 'fixture-run', attemptId: '1', preparedDirectory: '/fixture/prepared' };
    if (fault === 'image') request.inputs.configuration.environment.image = 'fixture/worker:latest';
    else { request.inputs.prompt.text = 'synthetic-private-value'; adapters.secretValues = ['synthetic-private-value']; }
    await assert.rejects(executePreparedAgent(request, adapters));
    assert.equal(effects, 0);
    assert.equal(adapters.retained.length, 0);
  }
});
