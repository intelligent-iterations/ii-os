import { createHash } from 'node:crypto';
import { constants, closeSync, fstatSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

/** Caller-owned Codex settings, bound to the retained execution input hash. */
function checkedInvocation(value) {
  if (!value || value.schemaVersion !== 1 ||
      Object.keys(value).some(key => !['schemaVersion', 'search', 'maxOutputBytes', 'responseSchema'].includes(key)) ||
      !['disabled', 'cached', 'live'].includes(value.search) ||
      !Number.isSafeInteger(value.maxOutputBytes) || value.maxOutputBytes < 1 || value.maxOutputBytes > 1048576) {
    throw Error('codex-invocation-invalid');
  }
  if (value.responseSchema !== undefined) {
    if (typeof value.responseSchema !== 'string' || !value.responseSchema.isWellFormed() || Buffer.byteLength(value.responseSchema) > 1048576) throw Error('codex-invocation-schema-invalid');
    let parsed;
    try { parsed = JSON.parse(value.responseSchema); } catch { throw Error('codex-invocation-schema-invalid'); }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw Error('codex-invocation-schema-invalid');
  }
  return { schemaVersion: 1, search: value.search, maxOutputBytes: value.maxOutputBytes,
    ...(value.responseSchema === undefined ? {} : { responseSchema: value.responseSchema }) };
}

export function codexInvocationDigest(value) {
  return 'sha256:' + createHash('sha256').update(JSON.stringify(checkedInvocation(value))).digest('hex');
}

export function bindCodexInvocation(value, record) {
  const bindings = record.inputs.components?.filter(component => component.name === 'codex-invocation') ?? [];
  if (value === undefined) {
    if (bindings.length) throw Error('codex-invocation-binding-mismatch');
    return null;
  }
  const invocation = checkedInvocation(value);
  if (bindings.length !== 1 || bindings[0].version !== codexInvocationDigest(invocation)) throw Error('codex-invocation-binding-mismatch');
  return invocation;
}

/** These files are metadata of the trusted harness, never worker credentials. */
export function stageCodexResult(invocation, home) {
  if (!invocation) return { args: [], read: () => undefined };
  const output = join(home, 'last-message.txt');
  // The CLI truncates this existing private file; do not rely on its umask.
  writeFileSync(output, '', { mode: 0o600, flag: 'wx' });
  const args = ['--output-last-message', output];
  if (invocation.responseSchema !== undefined) {
    const schema = join(home, 'response-schema.json');
    writeFileSync(schema, invocation.responseSchema, { mode: 0o600, flag: 'wx' });
    args.push('--output-schema', schema);
  }
  return {
    args,
    read() {
      let descriptor;
      try {
        descriptor = openSync(output, constants.O_RDONLY | constants.O_NOFOLLOW);
        const before = fstatSync(descriptor);
        if (!before.isFile() || before.nlink !== 1 || before.uid !== process.getuid() || before.mode & 0o077 || before.size < 1 || before.size > invocation.maxOutputBytes) throw Error();
        const bytes = readFileSync(descriptor), after = fstatSync(descriptor);
        if (bytes.length !== before.size || before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) throw Error();
        const text = bytes.toString('utf8');
        if (!Buffer.from(text).equals(bytes)) throw Error();
        return text;
      } catch { throw Error('codex-result-unconfirmed'); }
      finally { if (descriptor !== undefined) closeSync(descriptor); }
    },
  };
}
