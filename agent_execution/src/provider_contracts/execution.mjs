/** Required trusted integrations. Missing capabilities fail before acquisition. */
export function requireExecutionPorts(ports) {
  for (const [name, methods] of Object.entries({
    source: ['verifyLocal', 'verifyWorker'], target: ['provision', 'close'], access: ['open', 'close'],
    harness: ['execute', 'close', 'reportUsage'], artifacts: ['collect'],
    history: ['retainInputs', 'retainCollection', 'retainOutcome'],
  })) {
    if (!methods.every(method => typeof ports?.[name]?.[method] === 'function')) throw Error('missing-execution-port:' + name);
  }
  if (typeof ports.authorize !== 'function' || typeof ports.onState !== 'function') throw Error('missing-execution-authority');
}
