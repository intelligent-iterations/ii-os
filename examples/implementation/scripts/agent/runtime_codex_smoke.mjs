#!/usr/bin/env node
// Adapter for the Connect Codex and stored-credential verification clients.
// No device-login or repository-secret writing policy moves into the runtime.
import { constants, closeSync, fstatSync, fsyncSync, ftruncateSync, lstatSync, mkdirSync, openSync, readFileSync, readSync, realpathSync, writeFileSync, writeSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { connectorUrl, controllerPaths, importExecution } from './agent_execution_loader.mjs';
import { callbackBudget, createCredentialRotation } from './codex_credential_rotation.mjs';

const paths = controllerPaths(), stateRoot = paths.state, scratchRoot = paths.scratch;

function directory(path, create = true) {
  if (create) {
    try { mkdirSync(path, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const info = lstatSync(path);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || info.mode & 0o077 || realpathSync(path) !== path) throw Error('private-directory-invalid');
  return path;
}
function privatePath(path) {
  if (typeof path !== 'string' || !path.startsWith(scratchRoot + '/') || realpathSync(path) !== path) throw Error('private-auth-path-invalid');
  for (let parent = dirname(path); parent.startsWith(scratchRoot); parent = dirname(parent)) directory(parent, false);
}
function oauth(value) {
  if (!value || typeof value !== 'object' || value.OPENAI_API_KEY ||
      !['access_token', 'refresh_token'].every(key => typeof value.tokens?.[key] === 'string' && value.tokens[key].length > 0)) throw Error('subscription-oauth-required');
  return value;
}
function authAccess(path, writable) {
  privatePath(path);
  const valid = info => info.isFile() && info.nlink === 1 && info.uid === process.getuid() && !(info.mode & 0o077) && info.size > 0 && info.size <= 65536;
  const original = lstatSync(path);
  if (!valid(original)) throw Error('private-auth-file-invalid');
  const descriptor = openSync(path, (writable ? constants.O_RDWR : constants.O_RDONLY) | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  const check = () => {
    privatePath(path);
    for (const info of [fstatSync(descriptor), lstatSync(path)]) {
      if (!valid(info) || info.dev !== original.dev || info.ino !== original.ino) throw Error('private-auth-file-invalid');
    }
  };
  try {
    check();
    return {
      read() {
        check();
        const encoded = Buffer.alloc(fstatSync(descriptor).size);
        try {
          let offset = 0;
          while (offset < encoded.length) {
            const bytes = readSync(descriptor, encoded, offset, encoded.length - offset, offset);
            if (!bytes) throw Error('private-auth-read-incomplete');
            offset += bytes;
          }
          const value = oauth(JSON.parse(encoded.toString('utf8'))); check(); return value;
        }
        finally { encoded.fill(0); }
      },
      replace(value) {
        if (!writable) throw Error('private-auth-file-read-only');
        const encoded = Buffer.from(JSON.stringify(oauth(value)));
        try {
          if (encoded.length > 65536) throw Error('private-auth-file-too-large');
          check();
          // Preserve the inode read by the harness. Python receives it only
          // after the worker and harness have both been torn down.
          ftruncateSync(descriptor);
          let offset = 0;
          while (offset < encoded.length) {
            const bytes = writeSync(descriptor, encoded, offset, encoded.length - offset, offset);
            if (!bytes) throw Error('private-auth-write-incomplete');
            offset += bytes;
          }
          fsyncSync(descriptor); check();
        } finally { encoded.fill(0); }
      },
      close() { closeSync(descriptor); },
    };
  } catch (error) { closeSync(descriptor); throw error; }
}

const abort = new AbortController();
process.on('SIGTERM', () => abort.abort()); process.on('SIGINT', () => abort.abort());
let result, credential, rotation;
const [mode, auth, smoke] = process.argv.slice(2), observer = process.env.II_OS_RUNTIME_OBSERVER;
try {
  const kind = process.env.II_OS_RUNTIME_KIND;
  if (!['execute', 'recover'].includes(mode) || !['codex-auth', 'codex-auth-verify'].includes(kind) || !/^[1-9][0-9]{0,2}$/.test(observer ?? '')) throw Error('verification-invocation-invalid');
  const identity = { repository: process.env.GITHUB_REPOSITORY };
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(identity.repository)) throw Error('repository-invalid');
  for (const [key, name] of Object.entries({ repositoryId: 'GITHUB_REPOSITORY_ID', runId: 'GITHUB_RUN_ID', runAttempt: 'GITHUB_RUN_ATTEMPT' })) {
    if (!/^[1-9][0-9]{0,15}$/.test(process.env[name] ?? '')) throw Error('workflow-identity-invalid');
    identity[key] = Number(process.env[name]);
  }
  const budget = await callbackBudget(process.env.II_OS_CREDENTIAL_BUDGET_CONTEXT);
  const { runCodexCredentialVerification } = await importExecution('src/providers/codex/verification.mjs');
  const { loadInstalledRuntime } = await importExecution('src/providers/agent_runtime/installed.mjs');
  rotation = createCredentialRotation({ kind, identity, sessionId: process.env.II_OS_CODEX_AUTH_SESSION_ID,
    connector: connectorUrl(process.env.II_OS_CONNECTOR_URL),
    originalDigest: budget.originalDigest, allocation: budget.allocation,
    oidc: JSON.parse(process.env.II_OS_CREDENTIAL_ROTATION_OIDC), runtime: await loadInstalledRuntime() });
  await rotation.bind({ ...budget, mode });
  let execution = {};
  if (mode === 'execute') {
    const root = new URL('../../', import.meta.url);
    const configuration = JSON.parse(readFileSync(new URL('.ii-os/runtimes/codex-verification.json', root), 'utf8'));
    const binding = JSON.parse(readFileSync(new URL('.ii-os/runtimes/execution-binding.json', root), 'utf8'));
    configuration.source.repository = identity.repository;
    const credentialProvider = kind === 'codex-auth'
      ? process.env.II_OS_CODEX_AUTH_CREDENTIAL_PROVIDER : 'github-actions';
    if (!['github-actions', 'codex-device-login'].includes(credentialProvider)) throw Error('credential-provenance-invalid');
    const reference = credentialProvider === 'codex-device-login'
      ? { provider: credentialProvider, resource: process.env.II_OS_CODEX_AUTH_SESSION_ID, key: 'auth.json', assignment: 'harness.codex.oauth' }
      : { provider: credentialProvider, resource: identity.repository, key: 'CODEX_AUTH_JSON', assignment: 'harness.codex.oauth' };
    configuration.credentialBindings = [reference];
    const components = [];
    for (const [name, variable] of [['implementation-source', 'COORDINATOR_SOURCE_SHA'], ['ii-os-source', 'II_OS_RUNTIME_SOURCE_SHA']]) {
      if (!/^[a-f0-9]{40}$/.test(process.env[variable] ?? '')) throw Error('source-binding-invalid');
      components.push({ name, version: process.env[variable] });
    }
    privatePath(smoke); directory(smoke, false);
    credential = authAccess(auth, kind === 'codex-auth');
    execution = { configuration, binding, components, controller: JSON.parse(process.env.II_OS_RUNTIME_CONTROLLER),
      credentialBinding: reference, credentialProvider: { id: reference.provider, resolve: async () => ({ read: () => credential.read() }) },
      onRefreshedCredential: async value => { await rotation.stage(value); if (kind === 'codex-auth') credential.replace(value); } };
  }
  directory(stateRoot, false); directory(scratchRoot, false);
  if (mode === 'execute') await rotation.beginUse();
  result = await runCodexCredentialVerification({ mode, kind, identity, ...execution,
    observerId: observer, signal: abort.signal,
    stateDirectory: directory(join(stateRoot, 'verification')), scratchDirectory: directory(join(scratchRoot, 'verification')),
    authorize: async record => record.executionId === `github:${identity.repositoryId}:${identity.runId}:${kind}` });
  result.credentialCommit = await rotation.finish(result.outcome);
  if (mode === 'execute' && result.verified) {
    privatePath(smoke); directory(smoke, false);
    writeFileSync(smoke + '/ok.txt', 'ok', { flag: 'wx', mode: 0o600 });
  }
} catch {
  result = { ...result, verified: false, error: 'runtime_codex_verification_unconfirmed' };
} finally { credential?.close(); }
if (['execute', 'recover'].includes(mode) && /^[1-9][0-9]{0,2}$/.test(observer ?? '')) {
  directory(stateRoot, false);
  const file = openSync(join(stateRoot, `verification-observer-${mode}-${observer}.json`), 'wx', 0o600);
  try { writeFileSync(file, JSON.stringify(result)); fsyncSync(file); } finally { closeSync(file); }
  const parent = openSync(stateRoot, 'r'); try { fsyncSync(parent); } finally { closeSync(parent); }
}
process.stdout.write(JSON.stringify(result) + '\n');
process.exitCode = result.verified ? 0 : 1;
