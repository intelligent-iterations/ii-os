import assert from 'node:assert/strict';
import { test } from 'node:test';
import { runPreparedWorker } from '../src/providers/agent_runtime/prepared_worker.mjs';

function fixture(fault = '') {
  const calls = [];
  let authorization = 0;
  const action = name => async () => { calls.push(name); if (fault === name) throw Error('synthetic-private-error'); };
  const request = { executionId: 'run-1', attemptId: 'attempt-1', preparedDirectory: '/prepared',
    inputs: { configuration: { limits: { timeoutMinutes: 1 } } } };
  const ports = {
    source: { verifyLocal: action('source-local'), verifyWorker: action('source-worker') },
    runtime: {
      compileConfiguration: configuration => ({ configuration }),
      createExecutionInputRecord: () => ({ inputDigest: 'input', artifactDigest: 'artifact' }),
      workerResources: () => ({ image: 'pinned', cpu: 2, memoryMiB: 4096 }),
    },
    authorize: async () => { calls.push('authorize'); return fault !== 'denied' && !(fault === 'revoked' && ++authorization === 2); },
    target: { provision: async (_resources, context) => {
      assert.ok(context.signal instanceof AbortSignal);
      await action('provision')();
      return { load: action('load'), isolate: async () => ({ close: action('network-close') }) };
    }, close: action('runtime-close') },
    access: { open: async () => { await action('access-open')(); return { handle: 'run-handle' }; }, close: action('access-close') },
    harness: { execute: async input => {
      await action('execute')(); await input.onStarted(); return { exitCode: 0 };
    }, close: action('harness-close'), reportUsage: async () => { await action('usage')(); return { billingMode: 'subscription_included' }; } },
    artifacts: { collect: async () => { await action('collect')(); return { bundle: 'retained-reference' }; } },
    history: { retainInputs: action('inputs'), retainCollection: action('collection-retained'), retainOutcome: action('outcome') },
    onState: async event => { await action(event.state)(); },
  };
  return { calls, request, ports };
}

test('prepared work uses runtime provisioning and confirms execution only from the harness', async () => {
  const { calls, request, ports } = fixture();
  const outcome = await runPreparedWorker(request, ports);
  assert.equal(outcome.status, 'completed');
  assert.equal(outcome.cleanupConfirmed, true);
  assert.ok(calls.indexOf('running') > calls.indexOf('execute'));
  assert.deepEqual(calls, ['authorize', 'inputs', 'source-local', 'starting', 'provision', 'load', 'source-local', 'source-worker', 'access-open',
    'authorize', 'execute', 'running', 'finished', 'collect', 'collection-retained', 'cleaning', 'harness-close', 'access-close', 'network-close', 'runtime-close', 'usage', 'cleaned', 'outcome']);
});

test('partial provisioning and access failures still clean acquired infrastructure', async () => {
  for (const fault of ['provision', 'load', 'access-open', 'execute', 'collect']) {
    const { calls, request, ports } = fixture(fault);
    const outcome = await runPreparedWorker(request, ports);
    assert.equal(outcome.status, 'failed', fault);
    assert.ok(calls.includes('runtime-close'), fault);
    assert.ok(calls.includes('usage'), fault);
    assert.equal(JSON.stringify(outcome).includes('synthetic-private-error'), false);
    if (['provision', 'load', 'access-open', 'execute'].includes(fault)) assert.equal(calls.includes('running'), false);
  }
});

test('denied or revoked approval never executes the harness', async () => {
  for (const fault of ['denied', 'revoked']) {
    const { calls, request, ports } = fixture(fault);
    const outcome = await runPreparedWorker(request, ports);
    assert.equal(outcome.status, 'denied');
    assert.equal(calls.includes('execute'), false);
    assert.equal(calls.includes('provision'), fault === 'revoked');
  }
});

test('cleanup failure retains failure even if other cleanup components succeed', async () => {
  const { calls, request, ports } = fixture('access-close');
  const outcome = await runPreparedWorker(request, ports);
  assert.equal(outcome.status, 'cleanup-unconfirmed');
  assert.equal(outcome.cleanupConfirmed, false);
  assert.ok(calls.includes('runtime-close'));
  assert.equal(calls.includes('cleaned'), false);
});

test('missing workload-start observation and usage failure cannot look completed', async () => {
  const missing = fixture();
  missing.ports.harness.execute = async () => ({ exitCode: 0 });
  assert.equal((await runPreparedWorker(missing.request, missing.ports)).status, 'failed');
  const usage = fixture('usage');
  assert.equal((await runPreparedWorker(usage.request, usage.ports)).status, 'usage-unconfirmed');
});

test('a nonzero agent exit cannot become completed after collection', async () => {
  const { request, ports } = fixture();
  ports.harness.execute = async input => { await input.onStarted(); return { exitCode: 1 }; };
  const outcome = await runPreparedWorker(request, ports);
  assert.equal(outcome.status, 'failed');
  assert.equal(outcome.cleanupConfirmed, true);
});


test('changed source cannot acquire credentials or execute and any provisioned worker is cleaned', async () => {
  for (const fault of ['source-local', 'source-worker']) {
    const { calls, request, ports } = fixture(fault);
    const outcome = await runPreparedWorker(request, ports);
    assert.equal(outcome.status, 'failed');
    assert.equal(calls.includes('access-open'), false);
    assert.equal(calls.includes('execute'), false);
    assert.equal(calls.includes('runtime-close'), true);
    assert.equal(calls.includes('inputs'), true);
    assert.equal(calls.includes('outcome'), true);
  }
});


test('denial closes the unused target but does not retain an outcome without authorized inputs', async () => {
  const { calls, request, ports } = fixture('denied');
  const outcome = await runPreparedWorker(request, ports);
  assert.equal(outcome.cleanupConfirmed, true);
  assert.deepEqual(outcome.cleanup, [{ component: 'runtime', confirmed: true }]);
  assert.equal(calls.includes('inputs'), false);
  assert.equal(calls.includes('outcome'), false);
});
