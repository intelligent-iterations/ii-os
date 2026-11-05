#!/usr/bin/env node
// Trusted controller for one approved work ticket. The host provider starts it
// as a child process on the bound runtime host; ii-os agent_execution owns the
// behaviour (approval checks, preparation, admission, runtime, result policy,
// usage reporting and recovery). This file only wires the job's inputs in.
import { chmodSync, closeSync, fsyncSync, lstatSync, mkdirSync, openSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { connectorUrl, controllerPaths, importExecution, privateDirectory } from './agent_execution_loader.mjs';
import { createCredentialRotation } from './codex_credential_rotation.mjs';

// Staged by agent_credential_handoff.py; each is verified by its digest.
const helperNames = { core: 'agent-work-ticket-core.sh', status: 'agent-work-ticket-status.sh',
  prepare: 'agent-work-ticket-prepare.sh', execute: 'agent-work-ticket-execute.sh', materializer: 'agent-workspace-materialize.py' };
const abort = new AbortController();
process.on('SIGTERM', () => abort.abort());
process.on('SIGINT', () => abort.abort());

function stagedHandoff(value) {
  if (!value || typeof value.directory !== 'string' || !Number.isSafeInteger(value.device) || !Number.isSafeInteger(value.inode) ||
      !value.digests || typeof value.digests !== 'object' ||
      ![...Object.values(helperNames), 'github-api.token', 'codex-auth.json', 'agent-usage.key', 'ticket-prompt.json', 'report-codex-exec-usage.mjs']
        .every(name => /^[a-f0-9]{64}$/.test(value.digests[name] ?? ''))) throw Error('controller-handoff-invalid');
  privateDirectory(value.directory);
  const info = lstatSync(value.directory);
  if (info.dev !== value.device || info.ino !== value.inode) throw Error('controller-handoff-changed');
  return value;
}

let phase = 'controller-initialize';
let outcome, errorCode, rotationConfirmed = false, observerAttempt, state;
try {
  const paths = controllerPaths();
  state = paths.state;
  // An empty placeholder for native Codex path canonicalization. The actual
  // tool executor sees a different /workspace inside the runtime's worker.
  const workspace = lstatSync('/workspace');
  if (!workspace.isDirectory() || workspace.isSymbolicLink() || workspace.uid !== process.getuid() || realpathSync('/workspace') !== '/workspace') throw Error('controller-workspace-invalid');
  chmodSync('/workspace', 0o700);
  try { mkdirSync('/workspace/repository', { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  privateDirectory('/workspace/repository');
  if (readdirSync('/workspace/repository').length) throw Error('controller-workspace-not-empty');
  const chunks = []; let bytes = 0;
  for await (const chunk of process.stdin) {
    bytes += chunk.length;
    if (bytes > 4194304) throw Error('controller-input-limit');
    chunks.push(Buffer.from(chunk));
  }
  phase = 'input-decode';
  const { settings, handoff: rawHandoff } = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  const identity = settings?.identity;
  if (!identity || ![identity.repositoryId, identity.runId, identity.runAttempt].every(value => Number.isSafeInteger(value) && value > 0) ||
      !['execute', 'recover'].includes(settings.mode)) throw Error('controller-invocation-invalid');
  observerAttempt = settings.controllerAttempt;
  if (!Number.isSafeInteger(observerAttempt) || observerAttempt < 1 || observerAttempt > 100) throw Error('controller-observer-invalid');
  abort.signal.throwIfAborted();
  const handoff = stagedHandoff(rawHandoff);
  const connector = connectorUrl(settings.connector);
  const { runGitHubDockerTicket } = await importExecution('src/providers/github_actions/controller.mjs');
  const { loadInstalledRuntime } = await importExecution('src/providers/agent_runtime/installed.mjs');
  const runtime = await loadInstalledRuntime();
  const directory = handoff.directory;
  const helpers = Object.fromEntries(Object.entries(helperNames).map(([name, filename]) =>
    [name, { path: join(directory, filename), sha256: handoff.digests[filename] }]));
  const approval = settings.authorization;
  if (settings.mode === 'execute' && settings.credentialRotation?.originalDigest !== handoff.digests['codex-auth.json']) throw Error('credential-snapshot-mismatch');
  const rotation = createCredentialRotation({ runtime, kind: 'work-ticket', identity, connector,
    originalDigest: settings.credentialRotation?.originalDigest, runtimeConfiguration: settings.credentialRotation?.runtimeConfiguration,
    permissionProfile: settings.profile?.id, permissionDigest: settings.permissionDigest,
    oidc: settings.oidc, allocation: settings.allocation });
  // The one-use approval was consumed by the workflow; this binds every launch
  // input to that exact approval, profile digest, source and prompt.
  const authorize = async record => approval?.consumed === true && approval.repositoryId === identity.repositoryId &&
    approval.runId === identity.runId && approval.dispatchId === identity.dispatchId &&
    approval.permissionDigest === settings.permissionDigest && approval.sourceRevision === settings.sourceRevision &&
    record.inputs.components.some(value => value.name === 'permission-profile' && value.version === settings.permissionDigest) &&
    record.inputs.components.some(value => value.name === 'runtime-profile-source' && value.version === settings.sourceRevision) &&
    record.inputs.environment.II_OS_APPROVED_PROMPT_DIGEST === approval.ticketPromptDigest;
  outcome = await runGitHubDockerTicket({ ...settings, connector, authorize, signal: abort.signal, onPhase: value => { phase = value; },
    onCredentialContext: context => rotation.bind(context), beforeCredentialUse: async () => { await rotation.acquire(); await rotation.beginUse(); },
    onRefreshedCredential: value => rotation.stage(value),
    stateDirectory: paths.state, admissionDirectory: paths.admission, scratchDirectory: paths.scratch, helpers,
    approvedPromptFile: join(directory, 'ticket-prompt.json'), approvedPromptDigest: approval?.ticketPromptDigest,
    workflow: { ...settings.workflow, stage: { directory, device: handoff.device, inode: handoff.inode },
      source: { ...settings.workflow.source, filename: 'github-api.token', sha256: handoff.digests['github-api.token'] },
      oauth: { ...settings.workflow.oauth, filename: 'codex-auth.json', sha256: handoff.digests['codex-auth.json'] },
      usage: { ...settings.workflow.usage, filename: 'agent-usage.key', sha256: handoff.digests['agent-usage.key'] },
      reporter: { ...settings.workflow.reporter, parent: paths.scratch,
        script: { path: join(directory, 'report-codex-exec-usage.mjs'), sha256: handoff.digests['report-codex-exec-usage.mjs'] } } } });
  await rotation.finish(outcome?.outcome); rotationConfirmed = true;
} catch {
  // The envelope carries OIDC transport credentials and secret locations. Raw
  // child errors or settings never reach the workflow log boundary.
  errorCode = 'agent_runtime_controller_failed';
}
// Credential values stay in the job's staged handoff, which the workflow
// removes and proves absent before publication; this controller made no copy
// beyond the native harness home that agent_execution removes during cleanup.
const receipt = JSON.stringify({ schemaVersion: 1, ...(outcome ? { execution: outcome } : {}),
  credentialCleanupConfirmed: rotationConfirmed, phase, ...(errorCode ? { error: errorCode } : {}) }) + '\n';
if (observerAttempt && state) {
  // Retain the sanitized result before writing to a pipe that may be gone.
  const fd = openSync(join(state, `controller-attempt-${observerAttempt}.json`), 'wx', 0o600);
  try { writeFileSync(fd, receipt); fsyncSync(fd); } finally { closeSync(fd); }
  const parent = openSync(state, 'r'); try { fsyncSync(parent); } finally { closeSync(parent); }
}
process.stdout.write(receipt);
process.exitCode = errorCode || !rotationConfirmed ? 1 : 0;
