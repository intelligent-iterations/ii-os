import { constants, closeSync, fstatSync, lstatSync, openSync, readFileSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

/** Consume the existing workflow handoff; GitHub Actions supplies secret values. */
export function createStagedSecretProvider({ runtime, record, stage, bindings }) {
  if (!stage || !Array.isArray(bindings) || !bindings.length || !bindings.every(entry =>
    entry.reference?.provider === 'github-actions' && typeof entry.open === 'function' &&
    /^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$/.test(entry.filename ?? '') &&
    /^[a-f0-9]{64}$/.test(entry.sha256 ?? ''))) throw Error('workflow-secret-binding-invalid');
  const entries = new Map(bindings.map(entry => [runtime.canonicalJson(entry.reference), { ...entry }]));
  if (entries.size !== bindings.length) throw Error('workflow-secret-binding-invalid');
  const approved = new Set(record.inputs.credentials.map(reference => runtime.canonicalJson(reference)));
  if ([...entries.keys()].some(key => !approved.has(key))) throw Error('workflow-secret-binding-denied');
  // These are already pinned by the existing staging/mirror receipt. Do not
  // discover a directory from a secret name or accept a replacement inode.
  function directory() {
    const info = lstatSync(stage.directory);
    if (!info.isDirectory() || info.isSymbolicLink() || info.uid !== process.getuid() || (info.mode & 0o077) ||
        realpathSync(stage.directory) !== stage.directory || info.dev !== stage.device || info.ino !== stage.inode) {
      throw Error('workflow-secret-stage-changed');
    }
  }
  directory();
  return {
    id: 'github-actions',
    async resolve(reference, context) {
      if (context.executionId !== record.executionId || context.attemptId !== record.attemptId || context.inputDigest !== record.inputDigest) {
        throw Error('workflow-secret-execution-mismatch');
      }
      const entry = entries.get(runtime.canonicalJson(reference));
      if (!entry) throw Error('workflow-secret-binding-denied');
      const read = async () => {
        if (!(context.signal instanceof AbortSignal) || context.signal.aborted || Date.now() >= context.deadlineMs) throw Error('workflow-secret-interrupted');
        directory();
        const descriptor = openSync(join(stage.directory, entry.filename), constants.O_RDONLY | constants.O_NOFOLLOW);
        try {
          const before = fstatSync(descriptor);
          if (!before.isFile() || before.uid !== process.getuid() || before.nlink !== 1 || (before.mode & 0o077) || before.size < 1 || before.size > 65536) throw Error();
          const value = readFileSync(descriptor), after = fstatSync(descriptor);
          if (before.size !== value.length || before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs ||
              createHash('sha256').update(value).digest('hex') !== entry.sha256) throw Error();
          return value;
        } catch { throw Error('workflow-secret-integrity'); }
        finally { closeSync(descriptor); }
      };
      // The selected trusted adapter interprets OAuth JSON, GitHub tokens or a
      // reporting key. No value enters runtime configuration or the worker.
      return entry.open({ read });
    },
  };
}
