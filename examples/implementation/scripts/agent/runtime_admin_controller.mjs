#!/usr/bin/env node
// Run the trusted Connect Codex, credential verification and permission
// installer clients in the controller on the bound host. Only the fixed
// credential smoke workload enters an agent-runtime worker; the permission
// installer runs no worker and no model.
import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync, chmodSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { connectorUrl, controllerPaths, importExecution } from './agent_execution_loader.mjs';
import { cleanupPermissionSource, preparePermissionProfile } from './runtime_permission_prepare.mjs';
import { createCredentialRotation } from './codex_credential_rotation.mjs';

const scripts = fileURLToPath(new URL('./', import.meta.url));
const paths = controllerPaths(), stateRoot = paths.state, scratch = join(paths.scratch, 'client');
const path = '/usr/local/bin:/usr/bin:/bin';
const abort = new AbortController();
process.on('SIGTERM', () => abort.abort()); process.on('SIGINT', () => abort.abort());
function directory(value, create = false) {
  if (create) { try { mkdirSync(value, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; } }
  const info = lstatSync(value);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || realpathSync(value) !== value || info.mode & 0o077) throw Error('admin-directory-invalid');
}
function read(value) {
  const descriptor = openSync(value, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = fstatSync(descriptor);
    if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid() || info.mode & 0o077 || info.size > 2097152) throw Error('admin-receipt-invalid');
    return JSON.parse(readFileSync(descriptor, 'utf8'));
  } finally { closeSync(descriptor); }
}
function save(value, receipt) {
  const descriptor = openSync(value, 'wx', 0o600);
  try { writeFileSync(descriptor, JSON.stringify(receipt)); fsyncSync(descriptor); } finally { closeSync(descriptor); }
  const parent = openSync(stateRoot, 'r'); try { fsyncSync(parent); } finally { closeSync(parent); }
}
function absent(value) {
  try { lstatSync(value); return false; } catch (error) { if (error.code === 'ENOENT') return true; throw error; }
}
function requireSecrets(value) {
  if (!value.secrets || typeof value.secrets !== 'object' || Array.isArray(value.secrets) ||
      Object.values(value.secrets).some(secret => typeof secret !== 'string' || !secret)) throw Error('admin-secret-binding-invalid');
  const keys = Object.keys(value.secrets).sort().join(',');
  const expected = value.kind === 'permission-installer' ? 'GITHUB_SOURCE_READ_TOKEN' : 'CODEX_AUTH_JSON';
  if (value.kind === 'codex-auth') {
    if (typeof value.reauthenticate !== 'boolean' || !['', ...(value.reauthenticate ? [] : ['CODEX_AUTH_JSON'])].includes(keys)) throw Error('admin-secret-binding-invalid');
  } else if (keys !== expected) throw Error('admin-secret-binding-invalid');
}

let settings, worker, rotation, operationSucceeded = false, credentialCleanupConfirmed = false, rotationConfirmed = false, created = false, owner;
let outputs = {};
try {
  directory(stateRoot);
  const info = lstatSync('/workspace');
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || realpathSync('/workspace') !== '/workspace') throw Error('admin-workspace-invalid');
  chmodSync('/workspace', 0o700); directory('/workspace/repository');
  if (readdirSync('/workspace/repository').length) throw Error('admin-workspace-not-empty');
  const chunks = []; let bytes = 0;
  for await (const chunk of process.stdin) { bytes += chunk.length; if (bytes > 2097152) throw Error('admin-input-limit'); chunks.push(Buffer.from(chunk)); }
  ({ settings } = JSON.parse(Buffer.concat(chunks).toString('utf8')));
  if (!['codex-auth', 'codex-auth-verify', 'permission-installer'].includes(settings?.kind) || !['execute', 'recover'].includes(settings.mode) ||
      settings.authorized !== true || !['repositoryId', 'runId', 'runAttempt'].every(key => Number.isSafeInteger(settings.identity?.[key]) && settings.identity[key] > 0) ||
      settings.mode === 'execute' && settings.identity.runAttempt !== 1) throw Error('admin-invocation-invalid');
  abort.signal.throwIfAborted();
  if (settings.mode === 'execute') requireSecrets(settings);
  const connector = connectorUrl(settings.connector);
  const { loadInstalledRuntime } = await importExecution('src/providers/agent_runtime/installed.mjs');
  const { openAdmission } = await importExecution('src/providers/local/admission.mjs');
  const runtime = await loadInstalledRuntime();
  if (settings.kind !== 'permission-installer') {
    rotation = createCredentialRotation({ runtime, kind: settings.kind, identity: settings.identity, sessionId: settings.sessionId, connector,
      originalDigest: settings.credentialRotation?.originalDigest, allocation: settings.allocation, oidc: settings.credentialRotationOidc });
    await rotation.bind({ mode: settings.mode,
      record: { executionId: `github:${settings.identity.repositoryId}:${settings.identity.runId}:${settings.kind}`,
        attemptId: '1', inputDigest: settings.deploymentInputDigest },
      admission: openAdmission({ ...settings.allocation, directory: paths.admission }) });
  }
  const env = { PATH: path, HOME: scratch, RUNNER_TEMP: scratch, TMPDIR: scratch, PYTHONDONTWRITEBYTECODE: '1',
    GITHUB_REPOSITORY: settings.identity.repository, GITHUB_REPOSITORY_ID: String(settings.identity.repositoryId),
    GITHUB_RUN_ID: String(settings.identity.runId), GITHUB_RUN_ATTEMPT: String(settings.identity.runAttempt), GITHUB_SERVER_URL: 'https://github.com',
    GITHUB_SHA: settings.implementationSha,
    COORDINATOR_SOURCE_SHA: settings.implementationSha, II_OS_RUNTIME_SOURCE_SHA: settings.sourceSha,
    II_OS_RUNTIME_KIND: settings.kind, II_OS_RUNTIME_CONTROLLER: JSON.stringify(settings.controller),
    II_OS_RUNTIME_OBSERVER: String(settings.controllerAttempt),
    II_OS_CODEX_AUTH_SESSION_ID: settings.sessionId ?? '', II_OS_CODEX_AUTH_REPOSITORY: settings.identity.repository,
    II_OS_CONNECTOR_URL: connector, II_OS_AGENT_EXECUTION_DIR: process.env.II_OS_AGENT_EXECUTION_DIR,
    II_OS_CONTROLLER_STATE_DIR: paths.state, II_OS_CONTROLLER_ADMISSION_DIR: paths.admission, II_OS_CONTROLLER_SCRATCH_DIR: paths.scratch,
    GITHUB_OUTPUT: scratch + '/github-output' };
  if (rotation) {
    env.II_OS_CREDENTIAL_BUDGET_CONTEXT = join(stateRoot, 'credential-rotation', 'context.json');
    env.II_OS_CREDENTIAL_ROTATION_OIDC = JSON.stringify(settings.credentialRotationOidc);
  }
  directory(scratch, true); created = true; owner = randomUUID();
  writeFileSync(scratch + '/.owner', owner, { flag: 'wx', mode: 0o600 });
  writeFileSync(env.GITHUB_OUTPUT, '', { flag: 'wx', mode: 0o600 });
  if (settings.mode === 'execute') {
    if (settings.kind === 'codex-auth') {
      env.II_OS_CODEX_AUTH_REAUTHENTICATE = String(settings.reauthenticate);
    }
    if (settings.kind !== 'permission-installer') {
      env.ACTIONS_ID_TOKEN_REQUEST_URL = settings.oidc?.tokenUrl;
      env.ACTIONS_ID_TOKEN_REQUEST_TOKEN = settings.oidc?.requestToken;
    }
    // requireSecrets admitted at most this one key for the Codex clients.
    if (settings.kind !== 'permission-installer' && settings.secrets.CODEX_AUTH_JSON) env.CODEX_AUTH_JSON = settings.secrets.CODEX_AUTH_JSON;
    try {
      if (rotation) await rotation.acquire();
      if (settings.kind === 'permission-installer') {
        outputs = await preparePermissionProfile({ runtime, settings, scratch, scripts, env, signal: abort.signal });
      } else {
        await runtime.runTrustedProcess({ command: '/usr/bin/python3', args: [scripts + (settings.kind === 'codex-auth' ? 'run_codex_auth_session.py' : 'verify_stored_codex_auth.py')],
          cwd: scratch, env, timeoutMs: settings.kind === 'codex-auth' ? 1500000 : 720000, maxOutputBytes: 65536, signal: abort.signal });
      }
      operationSucceeded = true;
      if (settings.kind === 'codex-auth-verify') {
        const text = readFileSync(env.GITHUB_OUTPUT, 'utf8');
        const digest = /^secret_digest=([a-f0-9]{64})\n$/.exec(text);
        if (!digest) throw Error('admin-output-invalid');
        outputs.secret_digest = digest[1];
      }
    } catch { operationSucceeded = false; }
  } else if (settings.kind !== 'permission-installer' && !absent(join(stateRoot, 'verification', 'verification-launch.json'))) {
    try {
      await runtime.runTrustedProcess({ command: '/usr/local/bin/node', args: [scripts + 'runtime_codex_smoke.mjs', 'recover'],
        cwd: scratch, env, timeoutMs: 720000, maxOutputBytes: 65536, signal: abort.signal });
    } catch { /* The saved observer still distinguishes cleanup from work success. */ }
  }
  if (settings.kind === 'permission-installer') {
    cleanupPermissionSource();
    worker = { cleanupConfirmed: true, started: false, status: operationSucceeded ? 'completed' : 'failed', phase: 'permission-validation' };
  }
  const observer = join(stateRoot, 'verification-observer-' + settings.mode + '-' + settings.controllerAttempt + '.json');
  if (settings.kind !== 'permission-installer' && !absent(observer)) worker = read(observer).outcome;
  else if (settings.kind !== 'permission-installer' && absent(join(stateRoot, 'verification', 'verification-launch.json'))) {
    // The smoke saves its launch before the target can acquire anything. On
    // recovery the provider removed the prior controller before invoking us.
    worker = { cleanupConfirmed: true, started: false, status: 'not-started', phase: 'credential-client' };
  }
  if (settings.mode === 'recover' && !absent(join(stateRoot, 'admin-original.json'))) {
    const original = read(join(stateRoot, 'admin-original.json'));
    operationSucceeded = original.operationSucceeded === true; outputs = original.outputs ?? {};
    if (settings.kind === 'permission-installer') worker.status = operationSucceeded ? 'completed' : 'failed';
  }
  if (rotation) { await rotation.finish(worker); rotationConfirmed = true; }
  else rotationConfirmed = true;
} catch { operationSucceeded = false; }
finally {
  if (created) {
    try {
      directory(scratch);
      if (readFileSync(scratch + '/.owner', 'utf8') !== owner) throw Error('admin-credential-owner-changed');
      rmSync(scratch, { recursive: true }); credentialCleanupConfirmed = true;
    } catch { credentialCleanupConfirmed = false; }
  }
}
const receipt = { schemaVersion: 1, execution: { outcome: worker ?? { cleanupConfirmed: false, status: 'cleanup-unconfirmed' } },
  credentialCleanupConfirmed: credentialCleanupConfirmed && rotationConfirmed, operationSucceeded, outputs };
if (settings?.identity?.runAttempt) {
  if (settings.mode === 'execute') save(join(stateRoot, 'admin-original.json'), receipt);
  save(join(stateRoot, 'controller-attempt-' + settings.controllerAttempt + '.json'), receipt);
}
process.stdout.write(JSON.stringify(receipt) + '\n');
process.exitCode = receipt.credentialCleanupConfirmed && worker?.cleanupConfirmed === true ? 0 : 1;
