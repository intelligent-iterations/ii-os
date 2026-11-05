import { readFileSync } from 'node:fs';
import { runPreparedWorker } from './prepared_worker.mjs';
import { requireExecutionPorts } from '../../provider_contracts/execution.mjs';

/** Import only the deployment's installed package; no source-tree or Fleet fallback. */
export async function loadInstalledRuntime() {
  const [configuration, execution] = await Promise.all([
    import('@intelligent-iterations/ii-agent-runtime/runtime'),
    import('@intelligent-iterations/ii-agent-runtime/pipeline'),
  ]);
  const manifest = JSON.parse(readFileSync(new URL('../../../package.json', import.meta.url), 'utf8'));
  const dependency = manifest.dependencies?.['@intelligent-iterations/ii-agent-runtime'];
  const pin = /^github:intelligent-iterations\/ii-agent-runtime#([a-f0-9]{40})$/.exec(dependency ?? '');
  if (!pin) throw Error('runtime-package-pin-unavailable');
  const runtime = { ...configuration, ...execution, installedRevision: pin[1] };
  for (const name of ['compileConfiguration', 'createCredentialResolver', 'createExecutionInputRecord', 'workerResources',
    'runTrustedProcess', 'openTrustedProcess', 'openWorkerStdioEndpoint', 'recoverDockerTarget',
    'saveExecutionInputsArtifact', 'loadExecutionInputsArtifact']) {
    if (typeof runtime[name] !== 'function') throw Error('runtime-capability-unavailable:' + name);
  }
  return runtime;
}

export async function executePreparedAgent(request, ports) {
  requireExecutionPorts(ports);
  const runtime = await loadInstalledRuntime();
  if (request.inputs.components.find(component => component.name === 'runtime')?.version !== runtime.installedRevision) throw Error('runtime-package-pin-mismatch');
  return runPreparedWorker(request, { ...ports, runtime });
}
