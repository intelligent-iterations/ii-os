import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { loadInstalledRuntime } from '../agent_runtime/installed.mjs';
import { runPreparedWorker } from '../agent_runtime/prepared_worker.mjs';
import { readWorkerFile } from '../agent_runtime/files.mjs';
import { compileDockerBinding } from '../docker/binding.mjs';
import { createDockerRecovery } from '../docker/recovery.mjs';
import { openExecutionHistory } from '../local/history.mjs';
import { createPreparedSourceVerifier, preparedTreeManifest } from '../local/prepared_source.mjs';
import { createCodexHarness } from './harness.mjs';

function directory(path, create = false) {
  if (create) {
    try { mkdirSync(path, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const info = lstatSync(path);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || info.mode & 0o077 || realpathSync(path) !== path) throw Error('verification-directory-invalid');
  return path;
}
function save(path, value) {
  const descriptor = openSync(path, 'wx', 0o600);
  try { writeFileSync(descriptor, JSON.stringify(value)); fsyncSync(descriptor); }
  finally { closeSync(descriptor); }
  const parent = openSync(join(path, '..'), 'r');
  try { fsyncSync(parent); } finally { closeSync(parent); }
}
function read(path) {
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = fstatSync(descriptor);
    if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid() || info.mode & 0o077 || info.size > 1048576) throw Error('verification-record-invalid');
    return JSON.parse(readFileSync(descriptor, 'utf8'));
  } finally { closeSync(descriptor); }
}

/** Keep the existing credential-only smoke, using the ticket's proved worker boundary.
 * Device login, repository-secret replacement and finalization remain caller policy.
 */
export async function runCodexCredentialVerification(options) {
  const runtime = await loadInstalledRuntime(), identity = options.identity;
  if (!['codex-auth', 'codex-auth-verify'].includes(options.kind) ||
      !['execute', 'recover'].includes(options.mode) ||
      !['repositoryId', 'runId', 'runAttempt'].every(key => Number.isSafeInteger(identity?.[key]) && identity[key] > 0) ||
      options.mode === 'execute' && identity.runAttempt !== 1 || typeof options.authorize !== 'function') throw Error('verification-invocation-invalid');
  const executionId = `github:${identity.repositoryId}:${identity.runId}:${options.kind}`;
  const observer = options.observerId ?? String(identity.runAttempt);
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(observer)) throw Error('verification-observer-invalid');
  const state = directory(options.stateDirectory), scratch = directory(options.scratchDirectory);
  const historyParent = directory(join(state, 'history'), true), runtimeParent = directory(join(state, 'runtime'), true);
  const launchFile = join(state, 'verification-launch.json');
  // These exact two credential-only workflows are exempted in the existing
  // implementation usage contract/checker. No ticket execution uses this port.
  const reportUsage = async () => ({ exempt: true, contract: 'credential-only-workflow',
    workflow: options.kind === 'codex-auth' ? 'ii-os-codex-auth.yml' : 'ii-os-codex-auth-finalize.yml' });
  let record, binding, preparedDirectory;
  if (options.mode === 'recover') {
    ({ record, binding, preparedDirectory } = read(launchFile));
    if (record.executionId !== executionId || record.attemptId !== '1' ||
        runtime.canonicalJson(runtime.createExecutionInputRecord(record.inputs, record)) !== runtime.canonicalJson(record)) throw Error('verification-recovery-mismatch');
  } else {
    if (options.configuration?.source?.repository !== identity.repository ||
        !/^[a-f0-9]{64}$/.test(options.controller?.id ?? '') ||
        !/^[A-Za-z0-9:-]{8,256}$/.test(options.controller?.daemon ?? '')) throw Error('verification-source-mismatch');
    binding = options.binding;
    preparedDirectory = directory(join(state, 'verification-source'), true);
    directory(join(preparedDirectory, '.git'), true);
    const manifest = preparedTreeManifest(preparedDirectory);
    const inputs = { schemaVersion: 1, configuration: options.configuration,
      prompt: { kind: 'inline', text: 'Write a file named ok.txt containing exactly ok.' }, repositories: [],
      artifacts: [{ role: 'prepared-tree', artifact: { reference: preparedDirectory, digest: manifest.digest, bytes: manifest.bytes } }],
      components: [{ name: 'runtime', version: runtime.installedRevision },
        { name: 'execution-binding', version: 'sha256:' + createHash('sha256').update(runtime.canonicalJson(binding)).digest('hex') },
        { name: 'controller-instance', version: options.controller.id }, { name: 'controller-daemon', version: options.controller.daemon },
        ...(options.components ?? [])],
      model: { provider: 'openai', identity: options.configuration.harness.model, parameters: {} },
      environment: { II_OS_EXECUTION_SUBJECT: executionId }, credentials: options.configuration.credentialBindings ?? [], coverage: [] };
    record = runtime.createExecutionInputRecord(inputs, { executionId, attemptId: '1' });
    compileDockerBinding(runtime, record, binding);
    if (!await options.authorize(record)) throw Error('verification-approval-denied');
    save(launchFile, { record, binding, preparedDirectory });
  }
  const compiled = compileDockerBinding(runtime, record, binding);
  if (!await options.authorize(record)) throw Error('verification-approval-denied');
  const history = openExecutionHistory({ parent: historyParent, runtime, executionId, attemptId: record.attemptId });
  await history.retainInputs(record);
  const states = [], onState = async event => { states.push(event.state); };
  let outcome;
  if (options.mode === 'recover') {
    outcome = await createDockerRecovery({ runtime, record, binding, historyParent, runtimeParent, onState, reportUsage })
      .reconcile({ executionId, attemptId: record.attemptId, inputDigest: record.inputDigest });
    if (!outcome) throw Error('verification-cleanup-unconfirmed');
  } else {
    const resolver = runtime.createCredentialResolver(compiled, options.credentialProvider);
    const target = runtime.dockerTofuTarget({ parent: runtimeParent, executablePath: binding.executablePath,
      namespacePolicyImage: binding.namespacePolicyImage, workspaceHelperImage: binding.workspaceHelperImage,
      services: runtime.executionServices, checkpoint: checkpoint => history.retainRuntimeCheckpoint(checkpoint) });
    const harness = createCodexHarness({ runtime, parent: directory(join(scratch, 'harness'), true), socketParent: directory(join(scratch, 'sockets'), true),
      controllerWorkspace: binding.workspace, executable: binding.codexExecutable, executablePath: binding.executablePath,
      credentialForRun: context => resolver.resolve(record, options.credentialBinding, context),
      onRefreshedCredential: options.onRefreshedCredential, telemetry: { retain: value => history.retainTelemetry(value) }, reportUsage });
    outcome = await runPreparedWorker({ executionId, attemptId: record.attemptId, inputs: record.inputs, preparedDirectory, signal: options.signal }, {
      runtime, target, source: createPreparedSourceVerifier(), harness, history, authorize: options.authorize, onState,
      access: { open: async () => ({}), close: async () => {} }, artifacts: { collect: async ({ worker, deadlineMs, signal }) => {
        const bytes = await readWorkerFile(worker, worker.workspace + '/repository/ok.txt', 16,
          { timeoutMs: Math.min(10000, deadlineMs - Date.now()), signal });
        if (bytes.toString('utf8').trim() !== 'ok') throw Error('verification-output-missing');
        return { verified: true };
      } },
    });
  }
  save(join(state, `verification-states-${options.mode}-${observer}.json`), states);
  let transcript = '';
  try { transcript = history.readTelemetry().transcript.slice(-8192); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  return { outcome, transcript, verified: outcome.status === 'completed' && outcome.cleanupConfirmed === true && outcome.result?.verified === true };
}
