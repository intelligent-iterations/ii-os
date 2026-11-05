import { compileDockerBinding } from './binding.mjs';
import { loadInstalledRuntime } from '../agent_runtime/installed.mjs';
import { runPreparedWorker } from '../agent_runtime/prepared_worker.mjs';
import { createCodexHarness } from '../codex/harness.mjs';
import { openExecutionHistory } from '../local/history.mjs';
import { createPreparedSourceVerifier } from '../local/prepared_source.mjs';
import { createStagedSecretProvider } from '../github_actions/staged_secrets.mjs';
import { createExistingUsageReporter } from '../github_actions/usage_reporter.mjs';

/** Reuse GitHub Actions' staged secrets and the installed evaluations reporter. */
export async function createDockerWorkflowExecution(options) {
  const runtime = await loadInstalledRuntime(), { workflow, record } = options;
  if (!workflow?.oauth || !workflow?.usage || workflow.oauth.reference?.assignment !== 'harness.codex.oauth' ||
      workflow.usage.reference?.assignment !== 'usage.report') throw Error('workflow-credential-bindings-unavailable');
  const provider = createStagedSecretProvider({ runtime, record, stage: workflow.stage, bindings: [
    { ...workflow.oauth, open: ({ read }) => ({ read: async () => {
      try { return JSON.parse((await read()).toString('utf8')); }
      catch { throw Error('workflow-oauth-invalid'); }
    } }) },
    { ...workflow.usage, open: createExistingUsageReporter({ ...workflow.reporter, runtime, executionId: record.executionId }) },
  ] });
  return createDockerExecution({ ...options, credentialProvider: provider, usageProvider: provider,
    credentialBinding: workflow.oauth.reference, usageBinding: workflow.usage.reference });
}

/** Explicit composition for a trusted, disposable controller on the chosen Docker host. */
export async function createDockerExecution(options) {
  const runtime = await loadInstalledRuntime();
  for (const name of ['dockerTofuTarget', 'executionServices']) if (!runtime[name]) throw Error('runtime-capability-unavailable:' + name);
  const { binding, record } = options;
  const compiled = compileDockerBinding(runtime, record, binding);
  if (!options.access || !options.artifacts || !options.credentialProvider || !options.usageProvider ||
      options.credentialBinding?.assignment !== 'harness.codex.oauth' || options.usageBinding?.assignment !== 'usage.report') throw Error('execution-provider-unavailable');
  const oauth = runtime.createCredentialResolver(compiled, options.credentialProvider);
  const usage = runtime.createCredentialResolver(compiled, options.usageProvider);
  const history = openExecutionHistory({ parent: options.historyParent, runtime,
    executionId: record.executionId, attemptId: record.attemptId, secretValues: options.secretValues ?? [] });
  const target = runtime.dockerTofuTarget({ parent: options.runtimeParent, executablePath: binding.executablePath,
    namespacePolicyImage: binding.namespacePolicyImage, workspaceHelperImage: binding.workspaceHelperImage, services: runtime.executionServices,
    checkpoint: checkpoint => history.retainRuntimeCheckpoint(checkpoint) });
  const harness = createCodexHarness({ runtime, parent: options.harnessParent, socketParent: options.socketParent,
    invocation: options.invocation,
    controllerWorkspace: binding.workspace, executable: binding.codexExecutable, executablePath: binding.executablePath,
    onRefreshedCredential: options.onRefreshedCredential,
    credentialForRun: async context => {
      await options.beforeCredentialUse?.();
      return oauth.resolve(record, options.credentialBinding, context);
    }, telemetry: { retain: value => history.retainTelemetry(value) }, reportUsage: async report => {
      const reporter = await usage.resolve(record, options.usageBinding, { deadlineMs: Date.now() + 30000, signal: new AbortController().signal });
      if (typeof reporter.report !== 'function') throw Error('usage-provider-unavailable');
      return reporter.report(report);
    } });
  let used = false;
  return {
    history,
    async run(request, callbacks) {
      if (used) throw Error('execution-composition-already-used');
      used = true;
      const supplied = runtime.createExecutionInputRecord(request.inputs, request, { secretValues: options.secretValues ?? [] });
      if (runtime.canonicalJson(supplied) !== runtime.canonicalJson(record)) throw Error('execution-request-mismatch');
      return runPreparedWorker(request, { runtime, target, source: createPreparedSourceVerifier(), harness,
        history, access: options.access, artifacts: options.artifacts,
        secretValues: options.secretValues ?? [], authorize: callbacks.authorize, onState: callbacks.onState });
    },
  };
}
