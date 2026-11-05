import { createHash } from 'node:crypto';

const digest = value => createHash('sha256').update(value).digest('hex');
const keys = (value, expected) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...expected].sort().join(',');

/** Resolve only the reviewed profile's pinned files at one immutable source revision. */
export async function resolveApprovedRuntime({ profile, permissionDigest, sourceRevision, readArtifact, runtime }) {
  const canonical = runtime.canonicalJson(profile), snapshot = JSON.parse(canonical);
  if (!/^[a-f0-9]{64}$/.test(permissionDigest) || digest(canonical) !== permissionDigest) throw Error('runtime-profile-approval-mismatch');
  if (!/^[a-f0-9]{40}$/.test(sourceRevision) || typeof readArtifact !== 'function' || snapshot.schema_version !== 4 ||
      !keys(snapshot, ['schema_version', 'engine', 'id', 'version', 'display_name', 'description', 'allowed_actions', 'denied_actions', 'repository_actions', 'runtime', 'workflow']) ||
      !keys(snapshot.runtime, ['configuration', 'execution_binding'])) throw Error('runtime-profile-invalid');
  const references = [snapshot.runtime.configuration, snapshot.runtime.execution_binding];
  for (const ref of references) {
    if (!keys(ref, ['path', 'sha256']) || typeof ref.path !== 'string' ||
        !/^\.ii-os\/runtimes\/[A-Za-z0-9][A-Za-z0-9._/-]{0,180}\.json$/.test(ref.path) ||
        ref.path.includes('..') || ref.path.includes('//') || !/^[a-f0-9]{64}$/.test(ref.sha256)) throw Error('runtime-profile-reference-invalid');
  }
  if (references[0].path === references[1].path) throw Error('runtime-profile-reference-invalid');
  const files = [];
  for (const ref of references) {
    let bytes;
    try { bytes = await readArtifact(ref.path, { commit: sourceRevision }); }
    catch { throw Error('runtime-profile-artifact-unavailable'); }
    if (!Buffer.isBuffer(bytes) || bytes.length > 1048576 || digest(bytes) !== ref.sha256) throw Error('runtime-profile-artifact-mismatch');
    files.push(bytes.toString('utf8'));
  }
  const compiled = runtime.compileConfigurationText(files[0], 'json');
  const binding = runtime.parseConfigurationText(files[1], 'json');
  if (compiled.configuration.harness.name !== snapshot.engine) throw Error('runtime-profile-harness-mismatch');
  if (binding.runtimeRevision !== runtime.installedRevision) throw Error('runtime-package-pin-mismatch');
  const bindingCanonical = runtime.canonicalJson(binding);
  if (Buffer.byteLength(bindingCanonical) > 16384) throw Error('runtime-binding-too-large');
  return {
    compiled, binding,
    // These are retained execution inputs; the map is not a guest environment.
    environment: { II_OS_EXECUTION_BINDING: bindingCanonical },
    components: [
      { name: 'runtime', version: runtime.installedRevision },
      { name: 'permission-profile', version: permissionDigest },
      { name: 'runtime-profile-source', version: sourceRevision },
      { name: 'runtime-configuration-file', version: references[0].sha256 },
      { name: 'execution-binding', version: 'sha256:' + digest(bindingCanonical) },
    ],
  };
}
