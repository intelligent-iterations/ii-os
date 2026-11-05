import { createHash } from 'node:crypto';

/** Both ticket execution and credential verification use the same boundary. */
export function compileDockerBinding(runtime, record, binding) {
  const config = record.inputs.configuration;
  if (binding?.schemaVersion !== 1 || binding.hosting !== 'github' || binding.isolation !== 'docker' ||
      config.environment.hosting.provider !== binding.hosting || config.environment.provider !== binding.isolation ||
      config.environment.userNamespaces !== true || !Number.isInteger(config.environment.diskGiB) || binding.workspace !== '/workspace' ||
      !/^[A-Za-z0-9][A-Za-z0-9./:_-]*@sha256:[a-f0-9]{64}$/.test(binding.namespacePolicyImage ?? '') ||
      !/^[A-Za-z0-9][A-Za-z0-9./:_-]*@sha256:[a-f0-9]{64}$/.test(binding.workspaceHelperImage ?? '') ||
      !/^[a-f0-9]{40}$/.test(binding.runtimeRevision ?? '') ||
      !/^\/[A-Za-z0-9/_-]+$/.test(binding.codexExecutable ?? '') ||
      !/^\/[A-Za-z0-9/_-]+(?::\/[A-Za-z0-9/_-]+)*$/.test(binding.executablePath ?? '')) throw Error('unsupported-execution-binding');
  const bindingDigest = 'sha256:' + createHash('sha256').update(runtime.canonicalJson(binding)).digest('hex');
  const component = name => record.inputs.components.find(value => value.name === name)?.version;
  if (component('execution-binding') !== bindingDigest || component('runtime') !== binding.runtimeRevision ||
      binding.runtimeRevision !== runtime.installedRevision) throw Error('execution-binding-mismatch');
  return runtime.compileConfiguration(config);
}
