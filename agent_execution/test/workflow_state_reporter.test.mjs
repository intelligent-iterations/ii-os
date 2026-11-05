import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createWorkflowStateReporter } from '../src/providers/github_actions/state.mjs';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { inputs } from './fixtures/inputs.mjs';

async function fixture() {
  const runtime = await loadInstalledRuntime();
  const record = runtime.createExecutionInputRecord(inputs(), { executionId: 'github:42:100:work-ticket', attemptId: '1' });
  let receipt; const calls = [];
  const options = { runtime, record, identity: { repositoryId: 42, runId: 100, runAttempt: 1, workspaceId: 'workspace', projectItemId: 'item', dispatchId: 'dispatch', issueNumber: 5 },
    connector: 'https://control.example/api', oidc: { audience: 'https://control.example/api/oidc', tokenUrl: 'https://pipelines.actions.githubusercontent.com/idtoken', requestToken: 'synthetic-request-token' },
    admission: { reserveObservation: () => { calls.push('debit'); return { allowed: true }; } },
    history: { readState: (_state, digest) => { if (receipt) assert.equal(receipt.payloadDigest, digest); return receipt; }, retainState: async value => { receipt = value; calls.push('receipt'); } },
    fetch: async (url, request) => {
      calls.push(request.method);
      assert.equal(request.redirect, 'error'); assert.ok(request.signal instanceof AbortSignal);
      if (request.method === 'GET') return Response.json({ value: 'synthetic-oidc-token' });
      assert.equal(request.headers.Authorization, 'Bearer synthetic-oidc-token');
      assert.ok(!request.body.includes('synthetic-request-token'));
      assert.ok(!request.body.includes('synthetic-oidc-token'));
      return Response.json({ data: { recorded: true, executionId: record.executionId, status: 'execution_running' } });
    },
  };
  const update = { executionId: record.executionId, inputDigest: record.inputDigest, artifactDigest: record.artifactDigest,
    state: 'running', reservationId: '12345678-abcd-4000-8000-123456789abc' };
  return { options, update, calls };
}

test('state transport debits before provider access and an existing success receipt prevents duplicate requests', async () => {
  const { options, update, calls } = await fixture();
  await createWorkflowStateReporter(options)(update);
  await createWorkflowStateReporter(options)(update);
  assert.deepEqual(calls, ['debit', 'GET', 'POST', 'receipt']);
});

test('exhausted budget, an unbound event or another token host causes no provider request', async () => {
  const { options, update, calls } = await fixture();
  options.admission.reserveObservation = () => ({ allowed: false });
  await assert.rejects(createWorkflowStateReporter(options)(update), /budget-exhausted/);
  await assert.rejects(createWorkflowStateReporter(options)({ ...update, inputDigest: 'other' }), /input-mismatch/);
  options.oidc.tokenUrl = 'https://attacker.example/idtoken';
  assert.throws(() => createWorkflowStateReporter(options), /binding-invalid/);
  assert.deepEqual(calls, []);
});

test('transient failures receive at most two charged attempts without leaking provider error bodies', async () => {
  const { options, update, calls } = await fixture();
  options.fetch = async () => { calls.push('GET'); return new Response('synthetic-private-error', { status: 503 }); };
  await assert.rejects(createWorkflowStateReporter(options)(update), error => error.message === 'workflow-state-report-failed');
  assert.deepEqual(calls, ['debit', 'GET', 'debit', 'GET']);
});

test('failure and cancellation observations reach the existing lifecycle callback', async () => {
  for (const state of ['failed', 'cancelled', 'unknown']) {
    const { options, update, calls } = await fixture();
    await createWorkflowStateReporter(options)({ ...update, state });
    assert.deepEqual(calls, ['debit', 'GET', 'POST', 'receipt']);
  }
});
