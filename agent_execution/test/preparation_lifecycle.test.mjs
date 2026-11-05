import assert from 'node:assert/strict';
import { test } from 'node:test';
import { randomUUID } from 'node:crypto';
import { linkSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadInstalledRuntime } from '../src/providers/agent_runtime/installed.mjs';
import { beginTicketPreparation, retainReadyLaunch, readReadyLaunch, recoverTicketPreparation } from '../src/providers/github_actions/preparation_lifecycle.mjs';

async function fixture(t) {
  const root = mkdtempSync(join(realpathSync('/tmp'), 'preparation-lifecycle-')), owner = randomUUID();
  writeFileSync(join(root, '.owner'), owner, { mode: 0o600 });
  t.after(() => { assert.equal(readFileSync(join(root, '.owner'), 'utf8'), owner); rmSync(root, { recursive: true }); });
  const state = join(root, 'state'); mkdirSync(state, { mode: 0o700 });
  const installed = await loadInstalledRuntime(), calls = [];
  const controller = { id: 'c'.repeat(64), daemon: 'fixture-daemon' };
  let present = false, daemon = controller.daemon;
  const runtime = { ...installed, runTrustedProcess: async request => {
    calls.push(request.args[0]);
    return request.args[0] === 'info' ? JSON.stringify(daemon) : present ? controller.id + '\n' : '';
  } };
  const options = { mode: 'execute', identity: { repository: 'fixture/project', repositoryId: 42, runId: 100,
    runAttempt: 1, issueNumber: 5, dispatchId: 'fixture-dispatch', projectItemId: 'fixture-item', workspaceId: 'fixture-workspace' },
    controller, permissionDigest: 'a'.repeat(64), sourceRevision: 'b'.repeat(40), approvedPromptDigest: 'd'.repeat(64),
    repositories: [{ repository: 'fixture/project', commit: 'b'.repeat(40), path: '' }] };
  const executionId = 'github:42:100:work-ticket';
  const context = { runtime, state, options, executionId };
  const recovery = () => ({ ...context, options: { ...options, mode: 'recover', identity: { ...options.identity, runAttempt: 2 } } });
  const providerProof = { confirmed: true, owner: 'e'.repeat(64), daemon: controller.daemon,
    deploymentInputDigest: 'sha256:' + 'f'.repeat(64), originalController: { id: controller.id, name: 'ii-os-controller-fixture-1' } };
  return { context, recovery, calls, providerProof, setPresent: value => { present = value; }, setDaemon: value => { daemon = value; } };
}

test('a durable preparation intent precedes acquisition and blocks another execution invocation', async t => {
  const { context, calls } = await fixture(t);
  const intent = beginTicketPreparation(context);
  assert.deepEqual(JSON.parse(readFileSync(join(context.state, 'preparation.json'))), intent);
  assert.equal(intent.binding.controller.id, context.options.controller.id);
  assert.throws(() => beginTicketPreparation(context), /already-started/);
  assert.deepEqual(calls, []);
});

test('interrupted preparation recovers absence without reading prompts, profile, credentials or usage', async t => {
  const { context, recovery, calls } = await fixture(t);
  beginTicketPreparation(context);
  writeFileSync(join(context.state, 'launch.json'), '{interrupted write', { mode: 0o600 });
  const recover = recovery();
  for (const name of ['profile', 'workflow', 'helpers']) Object.defineProperty(recover.options, name, { get() { throw Error('must-not-read-' + name); } });
  const first = await recoverTicketPreparation(recover);
  assert.equal(first.disposition, 'recovered');
  assert.equal(first.outcome.phase, 'preparation'); assert.equal(first.outcome.status, 'never-acquired');
  assert.equal(first.outcome.started, false); assert.equal(first.outcome.acquired, false);
  assert.equal(first.outcome.inputDigest, undefined); assert.equal(first.outcome.usage, undefined);
  assert.equal(first.outcome.result, undefined); assert.match(first.outcome.preparationDigest, /^sha256:[a-f0-9]{64}$/);
  assert.deepEqual(first.outcome.cleanup, [{ component: 'runtime', confirmed: true, absent: true }]);
  assert.deepEqual(calls, ['info', 'ps']);
  assert.deepEqual(await recoverTicketPreparation(recover), first);
});

test('absence requires the original controller to be gone from its original daemon', async t => {
  const { context, recovery, setPresent, setDaemon } = await fixture(t);
  beginTicketPreparation(context); setPresent(true);
  await assert.rejects(recoverTicketPreparation(recovery()), /controller-still-present/);
  setPresent(false); setDaemon('other-daemon');
  await assert.rejects(recoverTicketPreparation(recovery()), /daemon-mismatch/);
  assert.throws(() => readFileSync(join(context.state, 'preparation-outcome.json')), { code: 'ENOENT' });
});

test('the durable launch gate binds exact launch bytes and changes recovery to runtime reconciliation', async t => {
  const { context, recovery, calls } = await fixture(t);
  const intent = beginTicketPreparation(context), launch = { record: { executionId: context.executionId, attemptId: '1' }, fixture: 'saved launch' };
  retainReadyLaunch({ ...context, intent, launch });
  assert.deepEqual(readReadyLaunch(context), launch);
  assert.equal(await recoverTicketPreparation(recovery()), null);
  assert.deepEqual(calls, []);
  writeFileSync(join(context.state, 'launch.json'), '{}', { mode: 0o600 });
  assert.throws(() => readReadyLaunch(context), /launch-integrity/);
  assert.equal(await recoverTicketPreparation(recovery()), null); // Never claim absence after the gate exists.
});

test('startup before a source intent needs the provider owned-controller absence attestation', async t => {
  const { context, recovery, providerProof, calls } = await fixture(t);
  await assert.rejects(recoverTicketPreparation(recovery()), /preparation-recovery-unconfirmed/);
  const recover = recovery(); recover.options.previousControllersAbsent = providerProof;
  const result = await recoverTicketPreparation(recover);
  assert.equal(result.outcome.preparation.binding.controller.id, context.options.controller.id);
  assert.deepEqual(result.outcome.preparation.providerProof, providerProof);
  assert.equal(result.outcome.cleanupConfirmed, true); assert.deepEqual(calls, []);
});

test('a torn first intent can recover only through the independently bound provider startup proof', async t => {
  const { context, recovery, providerProof } = await fixture(t);
  writeFileSync(join(context.state, 'preparation.json'), '{torn', { mode: 0o600 });
  await assert.rejects(recoverTicketPreparation(recovery()));
  const recover = recovery(); recover.options.previousControllersAbsent = providerProof;
  assert.equal((await recoverTicketPreparation(recover)).outcome.cleanupConfirmed, true);
});

test('changed approved inputs and a provider daemon mismatch cannot gain cleanup authority', async t => {
  const { context, recovery, providerProof } = await fixture(t); beginTicketPreparation(context);
  const recover = recovery(); recover.options.sourceRevision = 'f'.repeat(40);
  await assert.rejects(recoverTicketPreparation(recover), /preparation-binding-mismatch/);
  recover.options.sourceRevision = context.options.sourceRevision;
  recover.options.previousControllersAbsent = { ...providerProof, daemon: 'other-daemon' };
  await assert.rejects(recoverTicketPreparation(recover), /provider-absence-proof-invalid/);
});

test('a kill after publishing the complete intent can recover its exact private temporary link', async t => {
  const { context, recovery } = await fixture(t); beginTicketPreparation(context);
  linkSync(join(context.state, 'preparation.json'), join(context.state, '.preparation-' + randomUUID()));
  assert.equal((await recoverTicketPreparation(recovery())).outcome.cleanupConfirmed, true);
});

test('an unrelated hard link cannot be treated as an owned publication checkpoint', async t => {
  const { context, recovery, providerProof } = await fixture(t); beginTicketPreparation(context);
  linkSync(join(context.state, 'preparation.json'), join(context.state, 'unrelated-link'));
  const recover = recovery(); recover.options.previousControllersAbsent = providerProof;
  await assert.rejects(recoverTicketPreparation(recover), /preparation-file-invalid/);
});
