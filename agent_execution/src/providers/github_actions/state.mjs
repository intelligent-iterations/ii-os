import { createHash } from 'node:crypto';

const remoteStates = new Set(['accepted', 'waiting-for-capacity', 'starting', 'running', 'finished', 'failed', 'cancelled', 'unknown', 'cleaning', 'cleaned']);
const safeId = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/;
const hash = value => 'sha256:' + createHash('sha256').update(value).digest('hex');

async function boundedJson(response) {
  if (!response.ok) {
    await response.body?.cancel();
    const error = Error('workflow-state-provider-failed');
    error.retryable = response.status === 429 || response.status >= 500;
    throw error;
  }
  let size = 0; const chunks = [];
  for await (const chunk of response.body ?? []) {
    size += chunk.length;
    if (size > 65536) throw Error('workflow-state-response-limit');
    chunks.push(Buffer.from(chunk));
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

/** GitHub OIDC and connector traffic stay with the trusted controller. */
export function createWorkflowStateReporter(options) {
  const { runtime, record, identity, admission, history } = options;
  let connector, audience, issuer;
  try { connector = new URL(options.connector); audience = new URL(options.oidc.audience); issuer = new URL(options.oidc.tokenUrl); }
  catch { throw Error('workflow-state-binding-invalid'); }
  if (connector.protocol !== 'https:' || connector.username || connector.password || connector.search || connector.hash ||
      audience.origin !== connector.origin || audience.username || audience.password || audience.search || audience.hash || issuer.protocol !== 'https:' || issuer.username || issuer.password || issuer.hash ||
      !(issuer.hostname === 'token.actions.githubusercontent.com' || issuer.hostname.endsWith('.actions.githubusercontent.com')) ||
      typeof options.oidc.requestToken !== 'string' || !/^[\x21-\x7e]{1,16384}$/.test(options.oidc.requestToken) ||
      !['workspaceId', 'projectItemId', 'dispatchId'].every(key => safeId.test(identity?.[key] ?? '')) ||
      !Number.isSafeInteger(identity.issueNumber) || identity.issueNumber < 1 ||
      !Number.isSafeInteger(identity.repositoryId) || identity.repositoryId < 1 ||
      !Number.isSafeInteger(identity.runId) || identity.runId < 1 || !Number.isSafeInteger(identity.runAttempt) || identity.runAttempt < 1 ||
      typeof admission?.reserveObservation !== 'function' || typeof history?.readState !== 'function' || typeof history?.retainState !== 'function' ||
      record.executionId !== `github:${identity.repositoryId}:${identity.runId}:work-ticket`) throw Error('workflow-state-binding-invalid');
  const endpoint = new URL(connector.href.replace(/\/$/, '') + '/v1/agent-dispatches/' +
    encodeURIComponent(identity.workspaceId) + '/' + encodeURIComponent(identity.projectItemId) + '/execution-state');
  const tokenUrl = new URL(issuer); tokenUrl.searchParams.set('audience', options.oidc.audience);
  const http = options.fetch ?? globalThis.fetch;
  return async update => {
    if (!remoteStates.has(update.state)) return; // Full sequence remains in local runtime telemetry/history.
    if (update.executionId !== record.executionId || update.inputDigest !== record.inputDigest || update.artifactDigest !== record.artifactDigest) throw Error('workflow-state-input-mismatch');
    const body = { dispatchId: identity.dispatchId, issueNumber: identity.issueNumber,
      executionId: record.executionId, state: update.state, inputDigest: record.inputDigest, artifactDigest: record.artifactDigest,
      ...(update.reservationId ? { reservationId: update.reservationId } : {}) };
    const canonical = runtime.canonicalJson(body), payloadDigest = hash(canonical);
    if (history.readState(update.state, payloadDigest, String(identity.runAttempt))) return;
    for (let attempt = 0; attempt < 2; attempt++) {
      if (!admission.reserveObservation(record).allowed) throw Error('workflow-state-budget-exhausted');
      try {
        const signal = AbortSignal.timeout(15000);
        const token = await boundedJson(await http(tokenUrl.href, { method: 'GET', redirect: 'error', signal,
          headers: { Authorization: 'Bearer ' + options.oidc.requestToken, Accept: 'application/json' } }));
        if (typeof token.value !== 'string' || !/^[A-Za-z0-9._-]{1,12000}$/.test(token.value)) throw Error('workflow-state-oidc-invalid');
        const response = await boundedJson(await http(endpoint.href, { method: 'POST', redirect: 'error', signal,
          headers: { Authorization: 'Bearer ' + token.value, 'Content-Type': 'application/json', Accept: 'application/json' }, body: canonical }));
        if (response.data?.recorded !== true || response.data.executionId !== record.executionId || typeof response.data.status !== 'string' || !/^execution_[a-z_]{1,64}$/.test(response.data.status)) throw Error('workflow-state-unconfirmed');
        await history.retainState({ executionId: record.executionId, attemptId: record.attemptId, inputDigest: record.inputDigest,
          state: update.state, observerAttempt: String(identity.runAttempt), payloadDigest, status: response.data.status });
        return;
      } catch (error) {
        if (attempt === 1 || error.retryable === false ||
            !['TypeError', 'TimeoutError'].includes(error.name) && error.retryable !== true) throw Error('workflow-state-report-failed');
      }
    }
  };
}
