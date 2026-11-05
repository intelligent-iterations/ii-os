import { createHash } from 'node:crypto';
import { openExecutionHistory } from '../local/history.mjs';

/** Reconcile the original execution; this adapter has no launch or harness port. */
export function createDockerRecovery({ runtime, record, binding, historyParent, runtimeParent, onState, reportUsage }) {
  const hash = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
  if (binding.runtimeRevision !== runtime.installedRevision ||
      record.inputs.components.find(value => value.name === 'runtime')?.version !== runtime.installedRevision ||
      record.inputs.components.find(value => value.name === 'execution-binding')?.version !== hash(runtime.canonicalJson(binding)) ||
      typeof onState !== 'function') throw Error('recovery-binding-mismatch');
  const history = openExecutionHistory({ parent: historyParent, runtime, executionId: record.executionId, attemptId: record.attemptId });
  const readOutcome = () => {
    try { return history.readOutcome(); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  };
  async function recoverUsage(previous) {
    let usage = previous?.usage ?? history.readRecoveryUsage(), telemetry;
    if (!usage && typeof reportUsage === 'function') {
      try { telemetry = history.readTelemetry(); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      try {
        usage = await reportUsage({ transcript: telemetry?.transcript ?? '', exitCode: telemetry?.exitCode ?? null,
          model: record.inputs.configuration.harness.model, billingMode: 'subscription_included' });
        await history.retainRecoveryUsage({ executionId: record.executionId, attemptId: record.attemptId,
          inputDigest: record.inputDigest, usage });
      } catch { usage = null; }
    }
    return { usage, captureComplete: telemetry?.captureComplete === true };
  }
  return {
    async reconcile(reservation) {
      if (reservation.executionId !== record.executionId || reservation.attemptId !== record.attemptId ||
          reservation.inputDigest !== record.inputDigest || runtime.canonicalJson(history.readInputs()) !== runtime.canonicalJson(record)) throw Error('recovery-reservation-mismatch');
      const observe = state => onState({ state, executionId: record.executionId, attemptId: record.attemptId,
        inputDigest: record.inputDigest, artifactDigest: record.artifactDigest, reservationId: reservation.reservationId });
      const original = readOutcome(), previous = history.readRecoveryOutcome() ?? original;
      if (previous?.cleanupConfirmed === true) {
        // A fresh workflow attempt must redeliver cleanup before its existing
        // finalization path can use the retained result. No model is resumed.
        const { usage, captureComplete } = await recoverUsage(previous);
        await observe('cleaned');
        return { ...previous, ...(usage ? { usage, ...(previous.status === 'usage-unconfirmed' ? { status: 'recovered-cleanup' } : {}) } : {}),
          ...(captureComplete ? { telemetryRecovered: true } : {}) };
      }
      const controller = record.inputs.components.find(value => value.name === 'controller-instance')?.version;
      const daemon = record.inputs.components.find(value => value.name === 'controller-daemon')?.version;
      if (!/^[a-f0-9]{64}$/.test(controller ?? '') || !/^[A-Za-z0-9:-]{8,256}$/.test(daemon ?? '')) return null;
      const observedDaemon = await runtime.runTrustedProcess({ command: 'docker', args: ['info', '--format', '{{json .ID}}'],
        cwd: runtimeParent, env: { PATH: binding.executablePath, HOME: runtimeParent }, timeoutMs: 10000, maxOutputBytes: 4096 });
      if (JSON.parse(observedDaemon) !== daemon) throw Error('recovery-controller-daemon-mismatch');
      const ids = await runtime.runTrustedProcess({ command: 'docker', args: ['ps', '--all', '--no-trunc', '--format', '{{.ID}}'],
        cwd: runtimeParent, env: { PATH: binding.executablePath, HOME: runtimeParent }, timeoutMs: 10000, maxOutputBytes: 1048576 });
      if (ids.split('\n').some(value => value.trim() === controller)) return null;
      // Observation failure must not prevent independent infrastructure cleanup.
      try { await observe('cleaning'); } catch { /* Retained facts remain authoritative for retry. */ }
      const checkpoint = history.readRuntimeCheckpoint();
      if (checkpoint) {
        await runtime.recoverDockerTarget({ parent: runtimeParent, state: checkpoint,
          expected: { configurationDigest: runtime.workerResources(runtime.compileConfiguration(record.inputs.configuration)).configurationDigest,
            namespacePolicyImage: binding.namespacePolicyImage, workspaceHelperImage: binding.workspaceHelperImage },
          executablePath: binding.executablePath, checkpoint: value => history.retainRuntimeCheckpoint(value) });
      }
      // The pinned target fsyncs its preparing checkpoint before it can create
      // any runtime resource. No checkpoint means acquisition never started.
      const { usage, captureComplete } = await recoverUsage(original);
      const result = original?.result ?? history.readCollection();
      const outcome = { schemaVersion: 1, executionId: record.executionId, attemptId: record.attemptId,
        inputDigest: record.inputDigest, artifactDigest: record.artifactDigest, started: original?.started ?? false,
        phase: 'recovery', status: usage ? 'recovered-cleanup' : 'usage-unconfirmed', cleanupConfirmed: true,
        cleanup: ['runtime', 'network', 'access', 'harness'].map(component => ({ component, confirmed: true })),
        telemetryRecovered: captureComplete, ...(usage ? { usage } : {}), ...(result ? { result } : {}) };
      await history.retainRecoveryOutcome(outcome);
      await observe('cleaned');
      return outcome;
    },
  };
}
