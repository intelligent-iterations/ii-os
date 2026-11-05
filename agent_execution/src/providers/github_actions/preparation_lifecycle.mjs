import { closeSync, constants, fstatSync, fsyncSync, linkSync, lstatSync, openSync, readFileSync, readdirSync, realpathSync, unlinkSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';

const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const hex = (value, length) => typeof value === 'string' && value.length === length && /^[a-f0-9]+$/.test(value);
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(value);
const daemonId = value => typeof value === 'string' && /^[A-Za-z0-9:-]{8,256}$/.test(value);
function directory(state) {
  const stat = lstatSync(state);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || stat.mode & 0o077 || realpathSync(state) !== state) throw Error('controller-preparation-directory-invalid');
}
function bytes(path) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    const publicationLink = stat.nlink === 2 && readdirSync(dirname(path)).some(name => {
      if (!/^\.preparation-[a-f0-9-]{36}$/.test(name)) return false;
      const staged = lstatSync(join(dirname(path), name));
      return staged.isFile() && !staged.isSymbolicLink() && staged.dev === stat.dev && staged.ino === stat.ino;
    });
    // A kill between atomic publication and removing its temporary name leaves
    // two links to the same fully synced, privately owned inode. Recognize only
    // that exact publisher link; arbitrary hard links remain unsafe.
    if (!stat.isFile() || stat.uid !== process.getuid() || stat.nlink !== 1 && !publicationLink || stat.mode & 0o077 || stat.size > 1048576) throw Error('controller-preparation-file-invalid');
    return readFileSync(fd);
  } finally { closeSync(fd); }
}
function optional(path) {
  try { return bytes(path); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function retain(state, name, value, runtime, exclusive = false) {
  directory(state);
  const text = Buffer.from(runtime.canonicalJson(value)), path = join(state, name);
  const temporary = join(state, '.preparation-' + randomUUID());
  const fd = openSync(temporary, 'wx', 0o600);
  try { writeFileSync(fd, text); fsyncSync(fd); } finally { closeSync(fd); }
  try {
    // Publish only complete, synced records. A killed writer can leave its
    // private temporary file; it cannot publish a partially written gate.
    try { linkSync(temporary, path); }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (exclusive) throw Error('controller-preparation-already-started');
      if (!bytes(path).equals(text)) throw Error('controller-preparation-record-conflict');
    }
  } finally { unlinkSync(temporary); }
  const parent = openSync(state, 'r'); try { fsyncSync(parent); } finally { closeSync(parent); }
}
function binding(options, controller) {
  const { identity } = options;
  if (!identity || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(identity.repository ?? '') ||
      !['repositoryId', 'runId', 'issueNumber'].every(key => Number.isSafeInteger(identity[key]) && identity[key] > 0) ||
      !['dispatchId', 'projectItemId'].every(key => identifier(identity[key])) ||
      identity.workspaceId !== undefined && !identifier(identity.workspaceId) ||
      !hex(options.permissionDigest, 64) || !hex(options.sourceRevision, 40) || !hex(options.approvedPromptDigest, 64) ||
      !controller || !(controller.id === null || hex(controller.id, 64)) || !daemonId(controller.daemon) ||
      !Array.isArray(options.repositories) || !options.repositories.length || options.repositories.length > 11) throw Error('controller-preparation-binding-invalid');
  const repositories = options.repositories.map(value => {
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value.repository ?? '') || !hex(value.commit, 40) ||
        typeof value.path !== 'string' || value.path.length > 200 || value.path.startsWith('/') ||
        value.path.split('/').some(part => part === '..' || part === '.')) throw Error('controller-preparation-binding-invalid');
    return { repository: value.repository, commit: value.commit, path: value.path };
  });
  return { identity: { repository: identity.repository, repositoryId: identity.repositoryId, runId: identity.runId,
    issueNumber: identity.issueNumber, dispatchId: identity.dispatchId, projectItemId: identity.projectItemId,
    ...(identity.workspaceId !== undefined ? { workspaceId: identity.workspaceId } : {}) },
    permissionDigest: options.permissionDigest, sourceRevision: options.sourceRevision, approvedPromptDigest: options.approvedPromptDigest,
    repositories, controller };
}
function intentFor(context, controller) {
  return { schemaVersion: 1, executionId: context.executionId, attemptId: '1', binding: binding(context.options, controller) };
}
function validateIntent(intent, context) {
  const expected = intentFor(context, intent?.binding?.controller);
  if (context.runtime.canonicalJson(intent) !== context.runtime.canonicalJson(expected)) throw Error('controller-preparation-binding-mismatch');
  return intent;
}
function providerProof(options, intent) {
  const proof = options.previousControllersAbsent;
  if (proof === undefined) return null;
  if (!proof || Object.keys(proof).sort().join(',') !== 'confirmed,daemon,deploymentInputDigest,originalController,owner' ||
      proof.confirmed !== true || !hex(proof.owner, 64) || !daemonId(proof.daemon) ||
      !/^sha256:[a-f0-9]{64}$/.test(proof.deploymentInputDigest ?? '') ||
      proof.daemon !== options.controller?.daemon ||
      intent && proof.daemon !== intent.binding.controller.daemon ||
      proof.originalController !== null && (!proof.originalController ||
        Object.keys(proof.originalController).sort().join(',') !== 'id,name' || !hex(proof.originalController.id, 64) ||
        !/^ii-os-controller-[A-Za-z0-9-]{1,128}$/.test(proof.originalController.name ?? '') ||
        intent && proof.originalController.id !== intent.binding.controller.id)) throw Error('controller-provider-absence-proof-invalid');
  return proof;
}

/** ii-os preparation journal. This contains approved references, never credentials. */
export function beginTicketPreparation(context) {
  if (context.options.mode !== 'execute' || context.options.identity.runAttempt !== 1 || !hex(context.options.controller?.id, 64)) throw Error('controller-preparation-invocation-invalid');
  const intent = intentFor(context, context.options.controller);
  retain(context.state, 'preparation.json', intent, context.runtime, true);
  return intent;
}

/** The acquisition path cannot run until both launch inputs and this gate are durable. */
export function retainReadyLaunch(context) {
  validateIntent(context.intent, context);
  const { runtime, state, launch, intent } = context;
  const launchBytes = runtime.canonicalJson(launch);
  retain(state, 'launch.json', launch, runtime);
  retain(state, 'launch-ready.json', { schemaVersion: 1, executionId: intent.executionId, attemptId: intent.attemptId,
    preparationDigest: digest(runtime.canonicalJson(intent)), launchDigest: digest(launchBytes) }, runtime);
}

export function readReadyLaunch(context) {
  const { runtime, state } = context;
  const intent = validateIntent(JSON.parse(bytes(join(state, 'preparation.json'))), context);
  const launchBytes = bytes(join(state, 'launch.json')), ready = JSON.parse(bytes(join(state, 'launch-ready.json')));
  const expected = { schemaVersion: 1, executionId: intent.executionId, attemptId: intent.attemptId,
    preparationDigest: digest(runtime.canonicalJson(intent)), launchDigest: digest(launchBytes) };
  if (runtime.canonicalJson(ready) !== runtime.canonicalJson(expected)) throw Error('controller-launch-integrity');
  return JSON.parse(launchBytes);
}

/** Cleanup only: no admission, preparation, credentials, model or usage ports exist here. */
export async function recoverTicketPreparation(context) {
  const { runtime, state, options, executionId } = context;
  if (options.mode !== 'recover') throw Error('controller-preparation-recovery-invalid');
  directory(state);
  if (optional(join(state, 'launch-ready.json'))) return null;
  let intent;
  try {
    const saved = optional(join(state, 'preparation.json'));
    if (saved) intent = validateIntent(JSON.parse(saved), context);
  } catch (error) {
    // A provider-owned pre-start journal can independently prove the torn
    // first write. Unsafe files and changed valid bindings still fail closed.
    if (!(error instanceof SyntaxError) || !options.previousControllersAbsent) throw error;
  }
  const proof = providerProof(options, intent);
  if (!intent && !proof) throw Error('controller-preparation-recovery-unconfirmed');
  if (!intent) intent = intentFor(context, { id: proof.originalController?.id ?? null, daemon: proof.daemon });
  if (!proof) {
    const command = args => runtime.runTrustedProcess({ command: 'docker', args, cwd: state,
      env: { PATH: '/usr/local/bin:/usr/bin:/bin', HOME: state }, timeoutMs: 10000, maxOutputBytes: 1048576 });
    if (JSON.parse(await command(['info', '--format', '{{json .ID}}'])) !== intent.binding.controller.daemon) throw Error('controller-preparation-daemon-mismatch');
    const ids = await command(['ps', '--all', '--no-trunc', '--format', '{{.ID}}']);
    if (ids.split('\n').some(value => value.trim() === intent.binding.controller.id)) throw Error('controller-preparation-controller-still-present');
  }
  // Recheck after proving the original writer absent: it cannot race this
  // observation by committing its launch gate and then acquiring a worker.
  if (optional(join(state, 'launch-ready.json'))) throw Error('controller-preparation-gate-changed');
  const preparation = { ...intent, ...(proof ? { providerProof: proof } : {}) };
  const outcome = { schemaVersion: 1, executionId, attemptId: '1', phase: 'preparation', status: 'never-acquired',
    started: false, acquired: false, preparation, preparationDigest: digest(runtime.canonicalJson(preparation)),
    cleanupConfirmed: true, cleanup: [{ component: 'runtime', confirmed: true, absent: true }] };
  retain(state, 'preparation-outcome.json', outcome, runtime);
  return { disposition: 'recovered', outcome };
}
