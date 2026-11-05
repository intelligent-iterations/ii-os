// Run-scoped trusted credential handoff. OAuth bytes never become artifacts,
// history, callback bodies, or worker authority. A refreshed subscription
// credential is written back only after worker cleanup, through the one-time
// repository-secret writer ii-os issues for this exact reservation.
import { constants, closeSync, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, realpathSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { connectorUrl, controllerPaths, importExecution } from './agent_execution_loader.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const json = value => JSON.stringify(value);
const safeDigest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const identifier = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(value);
// The trusted controller keeps this run-scoped journal in its private state.
const rootPath = () => join(controllerPaths().state, 'credential-rotation');
const helper = fileURLToPath(new URL('./codex_github_secret_writer.py', import.meta.url));

function directory(path, create = false) {
  if (create) { try { mkdirSync(path, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; } }
  const info = lstatSync(path);
  if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || info.mode & 0o077 || realpathSync(path) !== path) throw Error('credential-directory-invalid');
  return path;
}
function sync(path) {
  const fd = openSync(path, 'r'); try { fsyncSync(fd); } finally { closeSync(fd); }
}
function bytes(path, maximum = 65536) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = fstatSync(fd);
    if (!info.isFile() || info.nlink !== 1 || info.uid !== process.getuid() || info.mode & 0o077 || info.size > maximum) throw Error('credential-file-invalid');
    return readFileSync(fd);
  } finally { closeSync(fd); }
}
function read(path) {
  try { return JSON.parse(bytes(path).toString('utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function save(path, value) {
  try { bytes(path); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const temporary = path + '.' + randomUUID(), fd = openSync(temporary, 'wx', 0o600);
  try { writeFileSync(fd, value); fsyncSync(fd); } finally { closeSync(fd); }
  renameSync(temporary, path); sync(dirname(path));
}
function credential(value) {
  if (!value || typeof value !== 'object' || value.OPENAI_API_KEY || !value.tokens ||
      !['access_token', 'refresh_token'].every(key => typeof value.tokens[key] === 'string' && value.tokens[key])) throw Error('subscription-oauth-required');
  const encoded = Buffer.from(json(value));
  if (encoded.length < 100 || encoded.length > 49152) throw Error('credential-size-invalid');
  return encoded;
}
function identity(kind, value) {
  if (!['work-ticket', 'codex-auth', 'codex-auth-verify'].includes(kind) ||
      !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value?.repository ?? '') ||
      !['repositoryId', 'runId', 'runAttempt'].every(key => Number.isSafeInteger(value[key]) && value[key] > 0)) throw Error('credential-owner-invalid');
  return { kind, repository: value.repository, repositoryId: value.repositoryId, runId: value.runId, runAttempt: 1 };
}
async function bounded(response) {
  if (!response.ok) { await response.body?.cancel(); const error = Error('credential-broker-unconfirmed'); error.status = response.status; throw error; }
  let size = 0; const chunks = [];
  for await (const chunk of response.body ?? []) {
    size += chunk.length; if (size > 65536) throw Error('credential-broker-response-limit'); chunks.push(Buffer.from(chunk));
  }
  const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (!value || typeof value !== 'object') throw Error('credential-broker-invalid');
  return value;
}
function route(kind, value, sessionId) {
  if (kind === 'work-ticket') {
    if (!['workspaceId', 'projectItemId', 'dispatchId'].every(key => identifier(value[key])) || !Number.isSafeInteger(value.issueNumber)) throw Error('credential-ticket-invalid');
    return `v1/agent-dispatches/${encodeURIComponent(value.workspaceId)}/${encodeURIComponent(value.projectItemId)}/credential-`;
  }
  if (!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(sessionId ?? '')) throw Error('credential-session-invalid');
  return 'v1/codex-auth-sessions/' + sessionId + '/credential-';
}

export function createCredentialRotation(options) {
  if (typeof options.runtime?.canonicalJson !== 'function') throw Error('credential-runtime-contract-unavailable');
  const sameMetadata = (left, right) => options.runtime.canonicalJson(left) === options.runtime.canonicalJson(right);
  const connector = connectorUrl(options.connector), audience = connector + '/v1/codex-auth-sessions';
  const owner = identity(options.kind, options.identity), root = directory(options.directory ?? rootPath(), true);
  const journalFile = join(root, 'journal.json'), candidateFile = join(root, 'auth.json');
  const prefix = route(options.kind, options.identity, options.sessionId);
  const common = options.kind === 'work-ticket' ? {
    dispatchId: options.identity.dispatchId, issueNumber: options.identity.issueNumber,
    permissionProfile: options.permissionProfile, permissionDigest: options.permissionDigest,
  } : {};
  let journal = read(journalFile), context;
  if (journal && !sameMetadata(journal.owner, owner)) throw Error('credential-journal-owner-invalid');
  const http = options.fetch ?? globalThis.fetch;
  async function request(operation, body) {
    if (!context?.admission.reserveObservation(context.record).allowed) throw Error('credential-callback-budget-exhausted');
    const oidc = options.oidc;
    let issuer; try { issuer = new URL(oidc?.tokenUrl); } catch { throw Error('credential-oidc-invalid'); }
    if (issuer.protocol !== 'https:' || issuer.username || issuer.password || issuer.hash ||
        !(issuer.hostname === 'actions.githubusercontent.com' || issuer.hostname.endsWith('.actions.githubusercontent.com')) ||
        typeof oidc?.requestToken !== 'string' || !/^[\x21-\x7e]{1,16384}$/.test(oidc.requestToken)) throw Error('credential-oidc-invalid');
    issuer.searchParams.set('audience', audience);
    const token = await bounded(await http(issuer.href, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(15000),
      headers: { Authorization: 'Bearer ' + oidc.requestToken, Accept: 'application/json' } }));
    if (typeof token.value !== 'string' || !/^[A-Za-z0-9._-]{1,12000}$/.test(token.value)) throw Error('credential-oidc-invalid');
    const endpoint = connector + '?route=' + encodeURIComponent(prefix + operation);
    const result = await bounded(await http(endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: { Authorization: 'Bearer ' + token.value, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: json({ ...common, ...body }) }));
    if (!result.data || typeof result.data !== 'object') throw Error('credential-broker-invalid');
    return result.data;
  }
  function retain() { save(journalFile, json(journal)); }
  function reload() {
    journal = read(journalFile);
    if (journal && (!sameMetadata(journal.owner, owner) || journal.originalDigest !== options.originalDigest)) throw Error('credential-journal-owner-invalid');
  }
  function candidates() {
    return readdirSync(root).filter(name => name === 'auth.json' || /^auth\.json\.[a-f0-9-]{36}$/.test(name));
  }
  function candidate(remove = false) {
    const names = candidates();
    for (const name of names) {
      const encoded = bytes(join(root, name), 49152);
      try { if (digest(encoded) !== journal.candidateDigest) throw Error('credential-candidate-invalid'); }
      finally { encoded.fill(0); }
    }
    if (remove) { for (const name of names) unlinkSync(join(root, name)); sync(root); return; }
    if (!names.length) throw Error('credential-candidate-missing');
    if (!names.includes('auth.json')) { renameSync(join(root, names[0]), candidateFile); sync(root); }
  }
  return {
    async bind(value) {
      reload();
      context = value;
      if (!context?.record || typeof context.admission?.reserveObservation !== 'function' ||
          context.record.executionId !== `github:${owner.repositoryId}:${owner.runId}:${owner.kind}` ||
          !/^sha256:[a-f0-9]{64}$/.test(context.record.inputDigest)) throw Error('credential-budget-context-invalid');
      const budget = { executionId: context.record.executionId, attemptId: context.record.attemptId, inputDigest: context.record.inputDigest };
      const stored = read(join(root, 'context.json'));
      const expected = { schemaVersion: 1, owner, record: budget, allocation: options.allocation };
      if (stored && !sameMetadata(stored, expected)) throw Error('credential-budget-context-changed');
      if (!stored) save(join(root, 'context.json'), json(expected));
    },
    async acquire({ lookupOnly = false } = {}) {
      reload();
      if (!context || context.mode === 'recover' && !lookupOnly) throw Error('credential-recovery-cannot-acquire');
      if (!safeDigest(options.originalDigest) && !(options.kind === 'codex-auth' && options.originalDigest === '')) throw Error('credential-original-digest-invalid');
      if (!journal) { journal = { schemaVersion: 1, owner, operationId: randomUUID(), originalDigest: options.originalDigest, phase: 'acquire-intent' }; retain(); }
      if (journal.originalDigest !== options.originalDigest) throw Error('credential-snapshot-changed');
      if (journal.phase === 'acquired') return;
      if (journal.phase !== 'acquire-intent') throw Error('credential-operation-already-started');
      let acquired;
      try { acquired = await request('acquire', { operationId: journal.operationId, originalDigest: journal.originalDigest,
        ...(options.kind === 'work-ticket' ? { runtimeConfiguration: options.runtimeConfiguration } : {}), ...(lookupOnly ? { cleanupOnly: true } : {}) }); }
      catch (error) {
        if (!lookupOnly && [400, 401, 403, 409].includes(error.status)) { journal.phase = 'acquire-denied'; retain(); }
        throw error;
      }
      if (lookupOnly && acquired.committed === true) {
        if (acquired.secretDigest !== (journal.candidateDigest ?? journal.originalDigest) || typeof acquired.changed !== 'boolean' || !Number.isSafeInteger(acquired.generation)) throw Error('credential-commit-unconfirmed');
        journal.phase = 'committed'; journal.candidateDigest = acquired.secretDigest;
        journal.commit = { committed: true, changed: acquired.changed, secretDigest: acquired.secretDigest,
          generation: acquired.generation, secretUpdatedAt: acquired.secretUpdatedAt ?? null }; retain(); return;
      }
      if (typeof acquired.reservationId !== 'string' || !Number.isSafeInteger(acquired.fence) || acquired.fence < 1 ||
          acquired.originalDigest !== journal.originalDigest || !Number.isSafeInteger(acquired.generation)) throw Error('credential-acquire-unconfirmed');
      if (acquired.secretUpdatedAt !== null && (typeof acquired.secretUpdatedAt !== 'string' || !/^20[2-9][0-9]-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(acquired.secretUpdatedAt))) throw Error('credential-version-unconfirmed');
      journal = { ...journal, reservationId: acquired.reservationId, fence: acquired.fence, generation: acquired.generation,
        secretUpdatedAt: acquired.secretUpdatedAt, phase: 'acquired' }; retain();
    },
    async beginUse() {
      reload();
      if (journal?.phase !== 'acquired' || !journal.reservationId) throw Error('credential-not-acquired');
      journal.useStarted = true; retain();
    },
    async stage(value) {
      reload();
      if (!journal?.reservationId || journal.phase !== 'acquired') throw Error('credential-not-acquired');
      const encoded = credential(value);
      try {
        const candidateDigest = digest(encoded);
        if (journal.candidateDigest && journal.candidateDigest !== candidateDigest) throw Error('credential-candidate-changed');
        journal.candidateDigest = candidateDigest; retain();
        if (candidateDigest !== journal.originalDigest) save(candidateFile, encoded);
        journal.candidateConfirmed = true; retain();
      } finally { encoded.fill(0); }
    },
    async finish(outcome) {
      reload();
      if (!journal) return null; // No callback acquired a credential lease.
      if (journal.phase === 'committed') { candidate(true); return journal.commit; }
      if (journal.phase === 'acquire-denied') return null;
      if (journal.phase === 'acquire-intent') await this.acquire({ lookupOnly: true });
      if (journal.phase === 'committed') { candidate(true); return journal.commit; }
      if (!journal.reservationId || !context || outcome?.cleanupConfirmed !== true) throw Error('credential-cleanup-unconfirmed');
      if (journal.useStarted && !journal.candidateDigest) throw Error('credential-handoff-unconfirmed');
      const candidateDigest = journal.candidateDigest ?? journal.originalDigest;
      if (journal.cleanupDigest === undefined) { journal.cleanupDigest = 'sha256:' + digest(Buffer.from(json(outcome))); retain(); }
      const frozen = { reservationId: journal.reservationId, fence: journal.fence,
        originalDigest: journal.originalDigest, candidateDigest, workerCleanupDigest: journal.cleanupDigest,
        ...(options.identity.runAttempt > 1 ? { cleanupOnly: true } : {}) };
      const changed = candidateDigest !== journal.originalDigest;
      if (changed && !journal.candidateConfirmed) { candidate(); journal.candidateConfirmed = true; retain(); }
      if (changed && journal.phase !== 'written') {
        if (journal.phase !== 'acquired') throw Error('credential-writer-uncertain');
        candidate();
        const encoded = bytes(candidateFile, 49152);
        try { if (digest(encoded) !== candidateDigest) throw Error('credential-candidate-invalid'); credential(JSON.parse(encoded)); }
        finally { encoded.fill(0); }
        journal.phase = 'writer-requested'; retain();
        const writer = await request('writer', frozen);
        if (typeof writer.token !== 'string' || !writer.token || writer.token.length > 16384) throw Error('credential-writer-unconfirmed');
        journal.phase = 'writer-issued'; retain();
        let written;
        try {
          written = JSON.parse(await options.runtime.runTrustedProcess({ command: '/usr/bin/python3', args: [helper],
            input: json({ repository: owner.repository, authFile: candidateFile, token: writer.token,
              expectedSecretUpdatedAt: journal.secretUpdatedAt ?? null, expectedAbsent: journal.secretUpdatedAt == null }),
            cwd: root, env: { PATH: '/usr/local/bin:/usr/bin:/bin', HOME: root, PYTHONDONTWRITEBYTECODE: '1' },
            timeoutMs: 150000, maxOutputBytes: 65536, signal: AbortSignal.timeout(155000) }));
        } finally { writer.token = ''; }
        if (written?.writerTokenRevoked !== true || typeof written.secretUpdatedAt !== 'string') throw Error('credential-write-unconfirmed');
        journal.phase = 'written'; journal.secretUpdatedAt = written.secretUpdatedAt; retain();
      }
      const committed = await request('commit', { ...frozen, ...(changed ? { writerTokenRevoked: true, secretUpdatedAt: journal.secretUpdatedAt } : {}) });
      if (committed.committed !== true || committed.secretDigest !== candidateDigest || committed.changed !== changed || !Number.isSafeInteger(committed.generation)) throw Error('credential-commit-unconfirmed');
      journal.phase = 'committed'; journal.candidateDigest = candidateDigest;
      journal.commit = { committed: true, changed, secretDigest: committed.secretDigest,
        generation: committed.generation, secretUpdatedAt: committed.secretUpdatedAt ?? null }; retain();
      candidate(true);
      return journal.commit;
    },
  };
}

export async function callbackBudget(path) {
  const root = rootPath();
  if (path !== join(root, 'context.json')) throw Error('credential-budget-path-invalid');
  directory(root); const context = read(path);
  if (context?.schemaVersion !== 1 || !context.allocation) throw Error('credential-budget-context-invalid');
  const journal = read(join(root, 'journal.json'));
  const { openAdmission } = await importExecution('src/providers/local/admission.mjs');
  return { record: context.record, admission: openAdmission({ ...context.allocation, directory: controllerPaths().admission }),
    allocation: context.allocation, originalDigest: journal?.originalDigest };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.slice(2).join(',') !== 'charge') throw Error('credential-command-invalid');
  const context = await callbackBudget(process.env.II_OS_CREDENTIAL_BUDGET_CONTEXT);
  if (!context.admission.reserveObservation(context.record).allowed) throw Error('credential-callback-budget-exhausted');
  process.stdout.write('{"allowed":true}\n');
}
