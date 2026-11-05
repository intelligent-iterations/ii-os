/**
 * ii-os owns admission and recovery across workflow attempts. Runtime owns only
 * the single acquired execution. Retried dispatch never calls the launch path.
 */
export async function coordinateExecution(request, ports) {
  const { runtime, admission, authorize, recovery, createExecutionPorts, onState } = ports;
  const record = runtime.createExecutionInputRecord(request.inputs, request, { secretValues: ports.secretValues ?? [] });
  const event = state => onState({ state, executionId: record.executionId, attemptId: record.attemptId,
    inputDigest: record.inputDigest, artifactDigest: record.artifactDigest });
  if (!await authorize(record)) return { disposition: 'denied' };
  const compiled = runtime.compileConfiguration(record.inputs.configuration);
  const requested = request.reservationResources;
  if (requested?.cpu !== compiled.configuration.environment.cpu || requested?.memoryMiB !== compiled.configuration.environment.memoryMiB ||
      (compiled.configuration.environment.diskGiB !== undefined && requested?.diskGiB !== compiled.configuration.environment.diskGiB)) {
    throw Error('reservation-configuration-mismatch');
  }
  if (!request.subjectId || record.inputs.environment.II_OS_EXECUTION_SUBJECT !== request.subjectId) throw Error('execution-subject-mismatch');
  const limits = compiled.configuration.limits;
  const admitted = await admission.reserve({ executionId: record.executionId, attemptId: record.attemptId,
    inputDigest: record.inputDigest, resources: requested, policy: {
      agentId: compiled.configuration.id, subjectId: request.subjectId, maxConcurrent: limits.maxConcurrent,
      maxRunsPerSubject: limits.maxRunsPerSubject, maxRunsPerMonth: limits.maxRunsPerMonth, timeoutSeconds: limits.timeoutMinutes * 60,
    } });
  if (['denied', 'waiting-for-capacity'].includes(admitted.disposition)) {
    // Admission checked for an existing reservation first. This definitive
    // refusal cannot have acquired runtime resources or consumed a run count.
    // Retain that absence independently of callback and usage delivery so the
    // enclosing controller can return its physical capacity fence safely.
    const outcome = { schemaVersion: 1, executionId: record.executionId, attemptId: record.attemptId,
      inputDigest: record.inputDigest, artifactDigest: record.artifactDigest, started: false, acquired: false,
      phase: 'admission', status: 'never-acquired',
      admission: { disposition: admitted.disposition, ...(admitted.reason ? { reason: admitted.reason } : {}) },
      cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true, absent: true }] };
    await ports.retainOutcome(outcome);
    if (admitted.disposition === 'waiting-for-capacity') {
      try { await event('accepted'); await event('waiting-for-capacity'); }
      catch { return { ...admitted, outcome, observationConfirmed: false }; }
    }
    return { ...admitted, outcome };
  }
  if (admitted.disposition === 'recover') {
    // Recovery examines the original attempt's receipts. It must never call
    // createExecutionPorts or resume untrusted work, even if the caller crashed.
    const outcome = await recovery.reconcile(admitted.reservation);
    if (!outcome) return { disposition: 'recovery-required', reservation: admitted.reservation };
    if (outcome.cleanupConfirmed) await admission.release(admitted.reservation, outcome);
    return { disposition: 'recovered', outcome };
  }
  if (admitted.disposition !== 'launch') throw Error('invalid-admission-disposition');
  // A crash here retains the reservation; recovery must prove absence before
  // releasing it. An exception is never translated into permission to relaunch.
  await event('accepted');
  const execution = await createExecutionPorts({ record, reservation: admitted.reservation });
  const outcome = await execution.run(request, { authorize, onState: update => onState({ ...update, reservationId: admitted.reservation.reservationId }) });
  if (outcome.cleanupConfirmed) await admission.release(admitted.reservation, outcome);
  return { disposition: 'executed', outcome };
}
