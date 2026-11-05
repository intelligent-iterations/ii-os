import { requireExecutionPorts } from '../../provider_contracts/execution.mjs';

/**
 * ii-os's prepared-work adapter. The composition root supplies the installed,
 * pinned agent-runtime module and an explicit execution target binding.
 * Tickets, approvals, publication and cross-run reservations remain ii-os concerns.
 */
export async function runPreparedWorker(request, ports) {
  requireExecutionPorts(ports);
  const { runtime, source, target, authorize, harness, access, artifacts, history, onState } = ports;
  const compiled = runtime.compileConfiguration(request.inputs.configuration);
  const record = runtime.createExecutionInputRecord(request.inputs, {
    executionId: request.executionId, attemptId: request.attemptId,
  }, { secretValues: ports.secretValues ?? [] });
  const abort = new AbortController();
  const signal = request.signal ? AbortSignal.any([request.signal, abort.signal]) : abort.signal;
  const deadlineMs = Date.now() + compiled.configuration.limits.timeoutMinutes * 60000;
  const remaining = () => deadlineMs - Date.now();
  const check = () => {
    if (signal.aborted || remaining() <= 0) throw Error('execution-interrupted');
  };
  const timer = setTimeout(() => abort.abort(), remaining());
  // Closing an unused target also supplies an absence receipt after denial or
  // source failure, so the coordinator can safely release its reservation.
  const cleanup = [{ component: 'runtime', close: () => target.close() }];
  let retained = false;
  let isolation;
  let grant;
  let result;
  let phase = 'authorization';
  let started = false;
  let failure;
  const emit = async state => {
    await onState({ state, executionId: request.executionId, attemptId: request.attemptId,
      inputDigest: record.inputDigest, artifactDigest: record.artifactDigest });
  };
  try {
    check();
    if (!await authorize(record)) throw Error('execution-denied');
    await history.retainInputs(record);
    retained = true;
    phase = 'source-verification';
    await source.verifyLocal({ directory: request.preparedDirectory, record });
    check();
    phase = 'provisioning';
    await emit('starting');
    const worker = await target.provision(runtime.workerResources(compiled), { deadlineMs, signal });
    check();
    phase = 'preparation';
    await worker.load(request.preparedDirectory);
    check();
    await source.verifyLocal({ directory: request.preparedDirectory, record });
    await source.verifyWorker({ worker, record, deadlineMs, signal });
    check();
    const preparation = compiled.configuration.environment?.setup;
    if (preparation?.enabled) {
      if (!preparation.commands?.length) throw Error('setup-commands-unresolved');
      const setup = await worker.setup(preparation.commands, {
        timeoutMs: Math.min((preparation.timeoutMinutes ?? 10) * 60000, remaining()), signal,
      });
      if (setup.exitCode !== 0 || setup.timedOut) throw Error('setup-failed');
    }
    check();
    phase = 'isolation';
    isolation = await worker.isolate();
    cleanup.push({ component: 'network', close: () => isolation.close() });
    // Only the trusted access adapter sees provider credentials. It exposes
    // run-scoped worker access and enforces the approved configuration's scope.
    phase = 'access';
    cleanup.push({ component: 'access', close: () => access.close() });
    grant = await access.open({ compiled, isolation, deadlineMs, signal });
    check();
    phase = 'final-authorization';
    if (!await authorize(record)) throw Error('execution-denied');
    check();
    phase = 'execution';
    cleanup.push({ component: 'harness', close: () => harness.close() });
    const execution = await harness.execute({ worker, compiled, record, grant, deadlineMs, signal,
      onStarted: async () => {
        check();
        if (started) throw Error('duplicate-execution-start');
        started = true;
        await emit('running');
      } });
    if (!started) throw Error('execution-start-unconfirmed');
    if (!Number.isSafeInteger(execution.exitCode) || execution.exitCode < 0) throw Error('invalid-execution-result');
    if (execution.exitCode !== 0) failure = 'failed';
    await emit(execution.exitCode === 0 ? 'finished' : 'failed');
    check();
    phase = 'collection';
    // Capture a bundle/result, never push, merge or mint a writer credential here.
    result = await artifacts.collect({ worker, execution, record, deadlineMs, signal });
    // Retain the completed collection before teardown. A controller crash
    // during cleanup must not lose a result that has already been exported.
    await history.retainCollection({ executionId: request.executionId, attemptId: request.attemptId,
      inputDigest: record.inputDigest, collection: result });
  } catch (error) {
    failure = signal.aborted || remaining() <= 0 ? 'cancelled' :
      error?.message === 'execution-denied' ? 'denied' : 'failed';
    try { await emit(failure === 'cancelled' ? 'cancelled' : 'failed'); } catch { /* Cleanup and retained outcome remain mandatory. */ }
  } finally {
    clearTimeout(timer); abort.abort();
    try { await emit('cleaning'); } catch { failure ??= 'observation-failed'; }
    const receipts = [];
    for (const item of cleanup.reverse()) {
      try { await item.close(); receipts.push({ component: item.component, confirmed: true }); }
      catch { receipts.push({ component: item.component, confirmed: false }); }
    }
    const cleanupConfirmed = receipts.every(item => item.confirmed);
    if (!cleanupConfirmed) failure = 'cleanup-unconfirmed';
    // Reporting runs on every path. Its credential and transcript handling stay
    // with the trusted harness adapter, including when model execution failed.
    let usage;
    try { usage = await harness.reportUsage(); }
    catch { failure = cleanupConfirmed ? 'usage-unconfirmed' : failure; }
    const outcome = {
      schemaVersion: 1, executionId: request.executionId, attemptId: request.attemptId,
      inputDigest: record.inputDigest, artifactDigest: record.artifactDigest,
      started, phase, status: failure ?? 'completed', cleanupConfirmed, cleanup: receipts,
      ...(usage ? { usage } : {}), ...(result ? { result } : {}),
    };
    // A cleaned runtime is distinct from successful work and from publication.
    try { if (cleanupConfirmed) await emit('cleaned'); }
    catch { outcome.status = 'observation-failed'; }
    // Rejected requests have no retained input record to bind an outcome to.
    if (retained) await history.retainOutcome(outcome);
    return outcome;
  }
}
