import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';

const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
function syncDirectory(path) {
  const descriptor = openSync(path, 'r');
  try { fsyncSync(descriptor); } finally { closeSync(descriptor); }
}
function readPrivate(path, limit) {
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(descriptor);
    if (!stat.isFile() || stat.uid !== process.getuid() || stat.nlink !== 1 || (stat.mode & 0o077) || stat.size > limit) throw Error('unsafe-history-file');
    return readFileSync(descriptor, 'utf8');
  } finally { closeSync(descriptor); }
}
function validateDirectory(path) {
  const stat = lstatSync(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) || realpathSync(path) !== path) throw Error('unsafe-history-directory');
}

/** Local retained records belong to the selected execution owner, not the ii-os API. */
export function openExecutionHistory({ parent, runtime, executionId, attemptId, secretValues = [] }) {
  if (![executionId, attemptId].every(value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(value))) throw Error('invalid-history-identity');
  const root = resolve(parent); validateDirectory(root);
  const key = createHash('sha256').update(JSON.stringify([executionId, attemptId])).digest('hex');
  const directory = join(root, 'execution-' + key);
  try { mkdirSync(directory, { mode: 0o700 }); syncDirectory(root); }
  catch (error) { if (error.code !== 'EEXIST') throw error; }
  validateDirectory(directory);
  const identity = { schemaVersion: 1, executionId, attemptId };
  function exclude(value) {
    if (typeof value === 'string' && secretValues.some(secret => value.includes(secret))) throw Error('secret-in-history');
    if (value && typeof value === 'object') for (const [key, child] of Object.entries(value)) { exclude(key); exclude(child); }
  }
  if (secretValues.some(value => typeof value !== 'string' || !value)) throw Error('invalid-history-secret-filter');
  function retain(name, value, maxBytes = 1048576) {
    const text = runtime.canonicalJson(value);
    const snapshot = JSON.parse(text); exclude(snapshot);
    if (Buffer.byteLength(text) > maxBytes) throw Error('history-record-too-large');
    validateDirectory(directory);
    const path = join(directory, name);
    let descriptor;
    try { descriptor = openSync(path, 'wx', 0o600); }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (readPrivate(path, maxBytes) !== text) throw Error('immutable-history-conflict');
      return { reference: path, digest: digest(text), bytes: Buffer.byteLength(text) };
    }
    try { writeFileSync(descriptor, text); fsyncSync(descriptor); } finally { closeSync(descriptor); }
    syncDirectory(directory);
    return { reference: path, digest: digest(text), bytes: Buffer.byteLength(text) };
  }
  retain('identity.json', identity);
  function inputs() {
    const record = JSON.parse(readPrivate(join(directory, 'inputs.json'), 1048576));
    const expected = runtime.createExecutionInputRecord(record.inputs, identity, { secretValues });
    if (runtime.canonicalJson(record) !== runtime.canonicalJson(expected)) throw Error('history-input-integrity');
    return record;
  }
  function bind(value) {
    if (value.executionId !== executionId || value.attemptId !== attemptId) throw Error('history-attempt-mismatch');
    const record = inputs();
    if (value.inputDigest !== record.inputDigest) throw Error('history-input-mismatch');
  }
  function targetCheckpoint(phase) {
    let value;
    try { value = JSON.parse(readPrivate(join(directory, `runtime-${phase}.json`), 65536)); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    bind(value);
    if (value.checkpoint?.phase !== phase || !value.checkpoint.reference) throw Error('history-runtime-checkpoint-invalid');
    return value;
  }
  function readOptional(name) {
    let value;
    try { value = JSON.parse(readPrivate(join(directory, name), 1048576)); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    bind(value); exclude(value); return value;
  }
  return {
    directory,
    async retainInputs(record) {
      const expected = runtime.createExecutionInputRecord(record.inputs, identity, { secretValues });
      if (runtime.canonicalJson(record) !== runtime.canonicalJson(expected)) throw Error('history-input-integrity');
      return retain('inputs.json', expected);
    },
    async retainOutcome(outcome) {
      bind(outcome);
      if (typeof outcome.cleanupConfirmed !== 'boolean' || !Array.isArray(outcome.cleanup)) throw Error('history-cleanup-missing');
      return retain('outcome.json', outcome);
    },
    async retainCollection(value) {
      bind(value);
      if (!value.collection || typeof value.collection !== 'object' || Array.isArray(value.collection)) throw Error('invalid-history-collection');
      return retain('collection.json', value);
    },
    readCollection() { return readOptional('collection.json')?.collection ?? null; },
    async retainRecoveryOutcome(outcome) {
      bind(outcome);
      if (outcome.cleanupConfirmed !== true || !Array.isArray(outcome.cleanup) ||
          !outcome.cleanup.some(item => item.component === 'runtime' && item.confirmed === true) ||
          outcome.cleanup.some(item => item.confirmed !== true)) throw Error('cleanup-proof-required');
      return retain('recovery-outcome.json', outcome);
    },
    readRecoveryOutcome() { return readOptional('recovery-outcome.json'); },
    async retainRecoveryUsage(value) {
      bind(value);
      if (value.usage?.reported !== true) throw Error('usage-proof-required');
      return retain('recovery-usage.json', value);
    },
    readRecoveryUsage() { return readOptional('recovery-usage.json')?.usage ?? null; },
    async retainRuntimeCheckpoint(checkpoint) {
      const snapshot = JSON.parse(runtime.canonicalJson(checkpoint));
      if (!['preparing', 'provisioning', 'cleaned'].includes(snapshot.phase) ||
          Object.keys(snapshot).sort().join(',') !== 'phase,reference' || !snapshot.reference) throw Error('history-runtime-checkpoint-invalid');
      const record = inputs();
      const expected = runtime.workerResources(runtime.compileConfiguration(record.inputs.configuration));
      if (runtime.canonicalJson(snapshot.reference.resources) !== runtime.canonicalJson(expected)) throw Error('history-runtime-resource-mismatch');
      for (const phase of ['preparing', 'provisioning', 'cleaned']) {
        const previous = targetCheckpoint(phase);
        if (previous && runtime.canonicalJson(previous.checkpoint.reference) !== runtime.canonicalJson(snapshot.reference)) throw Error('history-runtime-reference-conflict');
      }
      return retain(`runtime-${snapshot.phase}.json`, { ...identity, inputDigest: record.inputDigest, checkpoint: snapshot }, 65536);
    },
    readRuntimeCheckpoint() {
      return ['cleaned', 'provisioning', 'preparing'].map(targetCheckpoint).find(Boolean)?.checkpoint ?? null;
    },
    async retainTelemetry(telemetry) {
      bind(telemetry);
      // Redaction precedes this boundary. Check the complete text before
      // splitting so a known credential cannot straddle two retained chunks.
      exclude(telemetry);
      const { transcript, ...metadata } = telemetry;
      if (typeof transcript !== 'string' || !transcript.isWellFormed() || Buffer.byteLength(transcript) > 16777216) throw Error('invalid-telemetry-transcript');
      const chunks = [];
      for (let offset = 0; offset < transcript.length;) {
        let end = Math.min(offset + 65536, transcript.length);
        if (end < transcript.length && /[\uD800-\uDBFF]/.test(transcript[end - 1])) end--;
        const text = transcript.slice(offset, end), name = `telemetry-${String(chunks.length).padStart(4, '0')}.json`;
        const artifact = retain(name, { text });
        chunks.push({ name, digest: artifact.digest, bytes: artifact.bytes });
        offset = end;
      }
      return retain('telemetry.json', { schemaVersion: 1, metadata, transcriptDigest: digest(transcript), chunks });
    },
    readState(state, payloadDigest, observerAttempt = attemptId) {
      if (!/^(accepted|waiting-for-capacity|starting|running|finished|failed|cancelled|unknown|cleaning|cleaned)$/.test(state) || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(observerAttempt)) throw Error('invalid-history-state');
      let observation;
      try { observation = JSON.parse(readPrivate(join(directory, `state-${state}-${observerAttempt}.json`), 65536)); }
      catch (error) { if (error.code === 'ENOENT') return null; throw error; }
      bind(observation);
      if (observation.payloadDigest !== payloadDigest || observation.state !== state || observation.observerAttempt !== observerAttempt) throw Error('history-state-conflict');
      return observation;
    },
    async retainState(observation) {
      bind(observation);
      const observerAttempt = observation.observerAttempt ?? attemptId;
      if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/.test(observerAttempt)) throw Error('invalid-history-observer');
      if (!/^(accepted|waiting-for-capacity|starting|running|finished|failed|cancelled|unknown|cleaning|cleaned)$/.test(observation.state) ||
          !/^sha256:[a-f0-9]{64}$/.test(observation.payloadDigest)) throw Error('invalid-history-state');
      return retain(`state-${observation.state}-${observerAttempt}.json`, { ...observation, observerAttempt }, 65536);
    },
    readTelemetry() {
      const index = JSON.parse(readPrivate(join(directory, 'telemetry.json'), 1048576));
      if (index.schemaVersion !== 1 || !Array.isArray(index.chunks) || index.chunks.length > 257) throw Error('telemetry-integrity');
      bind(index.metadata);
      let transcript = '';
      for (const [offset, item] of index.chunks.entries()) {
        if (item.name !== `telemetry-${String(offset).padStart(4, '0')}.json`) throw Error('telemetry-integrity');
        const text = readPrivate(join(directory, item.name), 1048576);
        if (digest(text) !== item.digest || Buffer.byteLength(text) !== item.bytes) throw Error('telemetry-integrity');
        const chunk = JSON.parse(text);
        if (typeof chunk.text !== 'string') throw Error('telemetry-integrity');
        transcript += chunk.text;
        if (Buffer.byteLength(transcript) > 16777216) throw Error('telemetry-integrity');
      }
      if (digest(transcript) !== index.transcriptDigest) throw Error('telemetry-integrity');
      const telemetry = { ...index.metadata, transcript }; exclude(telemetry);
      return telemetry;
    },
    readInputs: inputs,
    readOutcome() {
      const outcome = JSON.parse(readPrivate(join(directory, 'outcome.json'), 1048576));
      bind(outcome); return outcome;
    },
  };
}
