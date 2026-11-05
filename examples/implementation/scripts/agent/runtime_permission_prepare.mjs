// Prepare the exact approved source with ii-os's own preparation adapter and
// run the permission installer's validator on it. Publication stays in the
// workflow and happens only after this controller has exited.
import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, realpathSync, rmdirSync, rmSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { controllerPaths, importExecution } from './agent_execution_loader.mjs';

const stateRoot = () => controllerPaths().state;
const sourceParentPath = () => join(stateRoot(), 'installer-sources');
const markerPath = () => join(stateRoot(), 'installer-source-owner.json');
function privateText(path, maximum) {
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = fstatSync(descriptor);
    if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid() || info.mode & 0o077 || info.size > maximum) throw Error('permission-source-owner-invalid');
    return readFileSync(descriptor, 'utf8');
  } finally { closeSync(descriptor); }
}
function directory(path, create = false) {
  if (create) { try { mkdirSync(path, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; } }
  const info = lstatSync(path);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || info.mode & 0o077 || realpathSync(path) !== path) throw Error('permission-source-directory-invalid');
}
export function cleanupPermissionSource() {
  const sourceParent = sourceParentPath(), marker = markerPath();
  try { lstatSync(sourceParent); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
  directory(sourceParent);
  const expected = JSON.parse(privateText(marker, 1024)).owner;
  if (!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(expected)) throw Error('permission-source-owner-changed');
  let actual;
  try { actual = privateText(sourceParent + '/.owner', 36); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    // The durable journal precedes mkdir. Interruption before writing the
    // inner marker can leave only an empty directory, which rmdir checks.
    rmdirSync(sourceParent); return;
  }
  if (actual !== expected) {
    if (!expected.startsWith(actual) || readdirSync(sourceParent).join(',') !== '.owner') throw Error('permission-source-owner-changed');
    // An interrupted marker write precedes all Git work. Remove only its
    // partial marker and an otherwise empty directory, never recurse here.
    rmSync(sourceParent + '/.owner'); rmdirSync(sourceParent); return;
  }
  rmSync(sourceParent, { recursive: true });
}
export async function preparePermissionProfile({ runtime, settings, scratch, scripts, env, signal }) {
  const sourceParent = sourceParentPath(), marker = markerPath();
  const { prepareApprovedRepositories } = await importExecution('src/providers/github_actions/preparation.mjs');
  const allowed = ['APPROVAL_ID', 'DISPATCH_ID', 'DISPATCH_FENCE', 'WORKSPACE_ID', 'PROFILE_ID', 'PROFILE_JSON', 'PROFILE_VERSION', 'PROFILE_DIGEST'];
  if (Object.keys(settings.installation ?? {}).sort().join(',') !== allowed.sort().join(',') ||
      Object.values(settings.installation).some(value => typeof value !== 'string' || Buffer.byteLength(value) > 65536) ||
      !/^[a-f0-9]{40}$/.test(settings.implementationSha)) throw Error('permission-installation-binding-invalid');
  const owner = randomUUID();
  // Never reuse a source directory after interruption. Recovery only removes
  // the original owned source and returns its saved result, without Git access.
  try { lstatSync(sourceParent); throw Error('permission-source-already-exists'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const markerFile = openSync(marker, 'wx', 0o600);
  try { writeFileSync(markerFile, JSON.stringify({ owner })); fsyncSync(markerFile); } finally { closeSync(markerFile); }
  const parent = openSync(stateRoot(), 'r'); try { fsyncSync(parent); } finally { closeSync(parent); }
  mkdirSync(sourceParent, { mode: 0o700 });
  const ownerFile = openSync(sourceParent + '/.owner', 'wx', 0o600);
  try { writeFileSync(ownerFile, owner); fsyncSync(ownerFile); } finally { closeSync(ownerFile); }
  const root = new URL('../../', import.meta.url);
  const configuration = JSON.parse(readFileSync(new URL('.ii-os/runtimes/codex-verification.json', root), 'utf8'));
  configuration.source = { ...configuration.source, repository: settings.identity.repository, additionalRepositories: [], permissions: { contents: 'read' } };
  const reference = { provider: 'github-actions', resource: settings.identity.repository, key: 'GITHUB_SOURCE_READ_TOKEN', assignment: 'source.read' };
  configuration.credentialBindings = [reference];
  const executionId = `github:${settings.identity.repositoryId}:${settings.identity.runId}:permission-installer`;
  const record = runtime.createExecutionInputRecord({ schemaVersion: 1, configuration,
    prompt: { kind: 'inline', text: 'Prepare the existing two-person-approved permission installation.' },
    repositories: [{ repository: settings.identity.repository, commit: settings.implementationSha, localChanges: null }],
    artifacts: [], components: [{ name: 'runtime', version: runtime.installedRevision }, { name: 'implementation-source', version: settings.implementationSha }],
    model: { provider: 'none', identity: 'no-model-request', parameters: {} },
    environment: { II_OS_EXECUTION_SUBJECT: executionId, II_OS_PERMISSION_DIGEST: settings.installation.PROFILE_DIGEST },
    credentials: [reference], coverage: [] }, { executionId, attemptId: '1' });
  const compiled = runtime.compileConfiguration(configuration);
  const provider = { id: 'github-actions', resolve: async () => ({ read: async () => Buffer.from(settings.secrets.GITHUB_SOURCE_READ_TOKEN) }) };
  const credential = await runtime.createCredentialResolver(compiled, provider).resolve(record, reference,
    { deadlineMs: Date.now() + 300000, signal });
  const prepared = await prepareApprovedRepositories({ runtime, parent: sourceParent, compiled, record, credential,
    branch: 'ii-os-agent/' + createHash('sha256').update(settings.installation.DISPATCH_ID).digest('hex').slice(0, 32),
    repositories: [{ repository: settings.identity.repository, commit: settings.implementationSha, path: '' }],
    executablePath: '/usr/local/bin:/usr/bin:/bin', signal });
  const validatorEnv = { ...env, ...settings.installation };
  delete validatorEnv.GITHUB_SOURCE_READ_TOKEN;
  await runtime.runTrustedProcess({ command: '/usr/bin/python3', args: [scripts + 'agent_permission_install.py'],
    cwd: prepared.preparedDirectory, env: validatorEnv, timeoutMs: 120000, maxOutputBytes: 65536, signal });
  const result = {};
  for (const [name, directoryName, maximum] of [['profile_b64', 'agent-permissions', 65536], ['proof_b64', 'agent-permission-proofs', 1048576]]) {
    const path = prepared.preparedDirectory + '/.ii-os/' + directoryName + '/' + settings.installation.PROFILE_ID + '.json';
    const info = lstatSync(path);
    if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > maximum || realpathSync(path) !== path) throw Error('permission-output-invalid');
    result[name] = readFileSync(path).toString('base64');
  }
  return result;
}
