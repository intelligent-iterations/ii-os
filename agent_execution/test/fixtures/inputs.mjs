export function inputs() {
  return {
    schemaVersion: 1,
    configuration: {
      schemaVersion: 2, id: 'fixture-agent', revision: 'fixture-revision', instructions: 'Use the approved prompt.',
      harness: { name: 'codex', version: '0.164.0', model: 'fixture-model' },
      environment: { provider: 'docker', hosting: { provider: 'github' }, image: 'fixture/worker@sha256:' + 'a'.repeat(64), cpu: 2, memoryMiB: 4096 },
      source: { provider: 'github', repository: 'fixture/project', appId: 1, installationId: 2, additionalRepositories: [] },
      limits: { enabled: false, maxConcurrent: 1, maxRunsPerSubject: 1, maxRunsPerMonth: 10, timeoutMinutes: 5,
        maxModelRequests: 20, maxInputTokensPerRequest: 4096, maxOutputTokensPerRequest: 1024,
        maxModelCostMicrousdPerRun: 1000000, maxCostMicrousdPerMonth: 20000000,
        inputMicrousdPerMillionTokens: 2000000, outputMicrousdPerMillionTokens: 10000000, computeMicrousdPerMinute: 0 },
    },
    prompt: { kind: 'inline', text: 'Approved fixture prompt.' },
    repositories: [{ repository: 'fixture/project', commit: 'b'.repeat(40), localChanges: null }],
    artifacts: [], components: [{ name: 'runtime', version: 'b27525b30fc7c709b41fc8c62de4a4eb699f9827' }],
    model: { provider: 'fixture-provider', identity: 'fixture-model', parameters: {} },
    environment: { II_OS_EXECUTION_SUBJECT: 'fixture-ticket' }, credentials: [], coverage: [],
  };
}
