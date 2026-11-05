import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { coordinateExecution } from '../../coordinator.mjs';
import { resolveApprovedRuntime } from '../../runtime_profile.mjs';
import { loadInstalledRuntime } from '../agent_runtime/installed.mjs';
import { createDockerWorkflowExecution } from '../docker/execution.mjs';
import { createDockerRecovery } from '../docker/recovery.mjs';
import { openAdmission } from '../local/admission.mjs';
import { openExecutionHistory } from '../local/history.mjs';
import { prepareApprovedRepositories } from './preparation.mjs';
import { beginTicketPreparation, retainReadyLaunch, readReadyLaunch, recoverTicketPreparation } from './preparation_lifecycle.mjs';
import { prepareExistingTicketPrompt } from './prompt.mjs';
import { createExistingResultCollector } from './results.mjs';
import { createStagedSecretProvider } from './staged_secrets.mjs';
import { createExistingUsageReporter } from './usage_reporter.mjs';
import { createWorkflowStateReporter } from './state.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
function privateDirectory(path) {
  const stat = lstatSync(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || stat.mode & 0o077 || realpathSync(path) !== path) throw Error('controller-directory-invalid');
  return path;
}
function child(parent, name) {
  const path = join(parent, name);
  try { mkdirSync(path, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  return privateDirectory(path);
}
function privateBytes(path, maximum) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.uid !== process.getuid() || stat.nlink !== 1 || stat.mode & 0o077 || stat.size > maximum) throw Error('controller-file-invalid');
    return readFileSync(fd);
  } finally { closeSync(fd); }
}
function retain(path, bytes) {
  let fd;
  try { fd = openSync(path, 'wx', 0o600); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    if (!privateBytes(path, 1048576).equals(bytes)) throw Error('controller-retained-input-conflict');
    return;
  }
  try { writeFileSync(fd, bytes); fsyncSync(fd); } finally { closeSync(fd); }
}

/** Compose the existing workflow helpers with the installed runtime on its selected host.
 * The caller has consumed the existing human approval before delivering settings.
 * Provider credentials remain in this trusted disposable controller.
 */
export async function runGitHubDockerTicket(options) {
  const runtime = await loadInstalledRuntime();
  const phase = value => options.onPhase?.(value);
  phase('controller-validation');
  if (!['execute', 'recover'].includes(options.mode) || typeof options.authorize !== 'function' ||
      !Number.isSafeInteger(options.identity?.repositoryId) || !Number.isSafeInteger(options.identity?.runId) ||
      !Number.isSafeInteger(options.identity?.runAttempt) || options.identity.runAttempt < 1 ||
      options.mode === 'execute' && options.identity.runAttempt !== 1) throw Error('controller-invocation-invalid');
  const executionId = `github:${options.identity.repositoryId}:${options.identity.runId}:work-ticket`;
  const state = privateDirectory(options.stateDirectory), scratch = privateDirectory(options.scratchDirectory);
  const preparationContext = { runtime, state, options, executionId };
  if (options.mode === 'recover') {
    phase('recovery-inputs');
    // Startup may have stopped before even identity.json was fully written.
    // The provider's pre-start journal can prove this before any retained
    // execution file, prompt, helper or credential needs to be opened.
    const interrupted = await recoverTicketPreparation(preparationContext);
    if (interrupted) return interrupted;
  }
  retain(join(state, 'identity.json'), Buffer.from(runtime.canonicalJson({ schemaVersion: 1, executionId })));
  const paths = { historyParent: child(state, 'history'), runtimeParent: child(state, 'runtime'),
    sourceParent: child(state, 'sources'), collectionParent: child(state, 'collections'),
    harnessParent: child(scratch, 'harness'), socketParent: child(scratch, 'sockets') };
  const workflow = options.workflow;
  let record, request, binding, task;
  if (options.mode === 'recover') {
    const saved = readReadyLaunch(preparationContext);
    ({ record, request, binding, task } = saved);
    if (record?.executionId !== executionId || request?.executionId !== executionId ||
        !request.preparedDirectory.startsWith(paths.sourceParent + '/') ||
        runtime.canonicalJson(runtime.createExecutionInputRecord(record.inputs, record)) !== runtime.canonicalJson(record)) throw Error('controller-recovery-input-invalid');
    request = { ...request, attemptId: String(options.identity.runAttempt) };
  } else {
    const intent = beginTicketPreparation(preparationContext);
    phase('runtime-profile');
    const resolved = await resolveApprovedRuntime({ profile: options.profile, permissionDigest: options.permissionDigest,
      sourceRevision: options.sourceRevision, runtime, readArtifact: async (path, context) => {
        const artifact = options.runtimeFiles?.[path];
        if (artifact?.commit !== context.commit) throw Error('runtime-file-source-mismatch');
        return Buffer.from(artifact.base64, 'base64');
      } });
    binding = resolved.binding;
    if (resolved.compiled.configuration.source.repository !== options.identity.repository ||
        !/^[a-f0-9]{64}$/.test(options.controller?.id ?? '') ||
        !/^[A-Za-z0-9:-]{8,256}$/.test(options.controller?.daemon ?? '')) throw Error('controller-source-binding-invalid');
    task = { ...options.task, repository: options.identity.repository, repositoryId: options.identity.repositoryId,
      issueNumber: options.identity.issueNumber, dispatchId: options.identity.dispatchId, projectItemId: options.identity.projectItemId };
    const approvedBytes = privateBytes(options.approvedPromptFile, 65536);
    phase('approved-prompt');
    const prompt = await prepareExistingTicketPrompt({ runtime, parent: paths.harnessParent, helpers: options.helpers,
      task, approvedBytes, approvedDigest: options.approvedPromptDigest, executablePath: binding.executablePath, profile: options.profile, signal: options.signal });
    task.promptDigest = prompt.sha256;
    const inputs = { schemaVersion: 1, configuration: resolved.compiled.configuration,
      prompt: { kind: 'inline', text: prompt.text },
      repositories: options.repositories.map(value => ({ repository: value.repository, commit: value.commit, localChanges: null })),
      artifacts: [], components: [...resolved.components, ...prompt.components,
        ...Object.entries(options.helpers).map(([name, helper]) => ({ name: 'result-helper-' + name, version: 'sha256:' + helper.sha256 })),
        { name: 'usage-reporter', version: 'sha256:' + workflow.reporter.script.sha256 },
        { name: 'controller-instance', version: options.controller.id }, { name: 'controller-daemon', version: options.controller.daemon }],
      model: { provider: 'openai', identity: resolved.compiled.configuration.harness.model, parameters: {} },
      environment: { ...resolved.environment, II_OS_EXECUTION_SUBJECT: `github:${options.identity.repositoryId}:issue:${options.identity.issueNumber}`,
        II_OS_APPROVED_PROMPT_DIGEST: options.approvedPromptDigest, II_OS_WORK_TICKET: runtime.canonicalJson(task) },
      credentials: resolved.compiled.configuration.credentialBindings ?? [], coverage: [] };
    const identity = { executionId, attemptId: String(options.identity.runAttempt) };
    const preliminary = runtime.createExecutionInputRecord(inputs, identity);
    if (!await options.authorize(preliminary)) throw Error('controller-approval-denied');
    phase('source-preparation');
    let preparedDirectory;
    try {
      const source = workflow.source;
      if (source?.reference?.assignment !== 'source.read') throw Error('controller-source-credential-unavailable');
      const provider = createStagedSecretProvider({ runtime, record: preliminary, stage: workflow.stage,
        bindings: [{ ...source, open: ({ read }) => ({ read }) }] });
      const credential = await runtime.createCredentialResolver(resolved.compiled, provider).resolve(preliminary, source.reference,
        { deadlineMs: Date.now() + 300000, signal: options.signal ?? new AbortController().signal });
      const prepared = await prepareApprovedRepositories({ runtime, parent: paths.sourceParent, compiled: resolved.compiled,
        record: preliminary, credential, branch: 'ii-os-agent/' + hash(task.dispatchId).slice(0, 32),
        repositories: options.repositories, executablePath: binding.executablePath, signal: options.signal });
      inputs.artifacts.push({ role: 'prepared-tree', artifact: prepared.artifact });
      preparedDirectory = prepared.preparedDirectory;
    } catch {
      // No runtime has been acquired. Retain a failed execution through the
      // same cleanup, reporting and callback path instead of stranding the
      // consumed application claim. Missing source identity fails verification
      // before provisioning; a workflow retry only recovers this outcome.
      inputs.environment.II_OS_SOURCE_PREPARATION_FAILED = 'true';
      preparedDirectory = child(paths.sourceParent, 'failed-preparation');
    }
    record = runtime.createExecutionInputRecord(inputs, identity);
    const environment = resolved.compiled.configuration.environment;
    request = { ...identity, subjectId: inputs.environment.II_OS_EXECUTION_SUBJECT, inputs,
      preparedDirectory,
      reservationResources: { cpu: environment.cpu, memoryMiB: environment.memoryMiB, diskGiB: environment.diskGiB } };
    phase('launch-inputs');
    retainReadyLaunch({ ...preparationContext, intent, launch: { record, request, binding, task } });
  }
  phase('execution-composition');
  const history = openExecutionHistory({ parent: paths.historyParent, runtime, executionId, attemptId: record.attemptId });
  await history.retainInputs(record);
  const admission = openAdmission({ ...options.allocation, directory: privateDirectory(options.admissionDirectory) });
  // Bind the trusted provider to the durable callback debit. Acquisition stays
  // inside the tracked worker lifecycle so refusal still proves teardown.
  await options.onCredentialContext?.({ record, admission, mode: options.mode });
  if (options.mode === 'recover') {
    let previous;
    try { previous = history.readOutcome(); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (previous?.status === 'never-acquired') {
      if (previous.phase !== 'admission' || previous.started !== false || previous.acquired !== false ||
          previous.artifactDigest !== record.artifactDigest || previous.cleanupConfirmed !== true ||
          !['denied', 'waiting-for-capacity'].includes(previous.admission?.disposition) || previous.usage || previous.result ||
          previous.cleanup?.length !== 1 || previous.cleanup[0].component !== 'runtime' ||
          previous.cleanup[0].confirmed !== true || previous.cleanup[0].absent !== true) throw Error('controller-absence-proof-invalid');
      // A refusal has no reservation to recover. Reconsulting admission could
      // consume a run count after capacity or a monthly allowance changes.
      // Its immutable absence receipt authorizes cleanup, never another launch.
      return { disposition: 'recovered', outcome: previous };
    }
  }
  const onState = createWorkflowStateReporter({ runtime, record, identity: options.identity, admission, history,
    connector: options.connector, oidc: options.oidc });
  const reportUsage = async report => {
    const provider = createStagedSecretProvider({ runtime, record, stage: workflow.stage, bindings: [{ ...workflow.usage,
      open: createExistingUsageReporter({ ...workflow.reporter, runtime, executionId }) }] });
    const handle = await runtime.createCredentialResolver(runtime.compileConfiguration(record.inputs.configuration), provider).resolve(record,
      workflow.usage.reference, { deadlineMs: Date.now() + 30000, signal: new AbortController().signal });
    return handle.report(report);
  };
  const collector = createExistingResultCollector({ runtime, parent: paths.collectionParent, task,
    helpers: options.helpers, readTelemetry: () => history.readTelemetry() });
  return coordinateExecution({ ...request, signal: options.signal }, {
    runtime, admission, authorize: options.authorize, onState,
    retainOutcome: outcome => history.retainOutcome(outcome),
    recovery: createDockerRecovery({ runtime, record, binding, ...paths, onState, reportUsage }),
    createExecutionPorts: async () => {
      if (options.mode !== 'execute') throw Error('recovery-cannot-launch');
      return createDockerWorkflowExecution({ binding, record, ...paths, workflow,
        beforeCredentialUse: options.beforeCredentialUse,
        onRefreshedCredential: options.onRefreshedCredential,
        access: { open: async () => ({ repositories: record.inputs.repositories.map(value => value.repository) }), close: async () => {} },
        artifacts: collector });
    },
  });
}
