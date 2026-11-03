import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/codex_credential_policy.dart';
import 'package:ii_os_functions/src/github_actions_oidc.dart';

import 'credential_firestore_fake.dart';

const credentialBindingPath =
    'codexCredentialBindings/github.com~123~CODEX_AUTH_JSON';
final credentialAcquire = <String, Object?>{
  'operationId': 'rotation-1',
  'originalDigest': 'a' * 64,
};

Map<String, Object?> credentialCommit(
  Map<String, Object?> reservation, {
  bool changed = false,
}) => {
  ...reservation,
  'candidateDigest': (changed ? 'b' : 'a') * 64,
  'workerCleanupDigest': 'sha256:${'c' * 64}',
  'writerTokenRevoked': true,
  if (changed) 'secretUpdatedAt': '2026-10-30T12:00:00Z',
};

CodexCredentialOwner credentialOwner({
  String workspace = 'workspace-a',
  int run = 10,
  int attempt = 1,
  int repositoryId = 123,
  String purpose = 'work-ticket',
}) {
  final workflow = purpose == 'work-ticket'
      ? iiOsAgentTaskWorkflow
      : purpose == 'codex-auth'
      ? iiOsCodexAuthWorkflow
      : iiOsCodexAuthFinalizeWorkflow;
  final reference = 'refs/tags/ii-os-agent-v4-${'d' * 40}';
  return CodexCredentialOwner(
    workspaceId: workspace,
    subjectId: purpose == 'work-ticket' ? 'item-1:claim-1' : 'session-1',
    projectItemId: purpose == 'work-ticket' ? 'item-1' : null,
    dispatchId: purpose == 'work-ticket' ? 'claim-1' : null,
    purpose: purpose,
    principal: GitHubActionsPrincipal(
      repository: 'example/project',
      repositoryId: repositoryId,
      runId: run,
      runAttempt: attempt,
      sha: 'd' * 40,
      ref: reference,
      workflowRef: 'example/project/.github/workflows/$workflow@$reference',
      jobWorkflowRef:
          'example/project/.github/workflows/${purpose == 'work-ticket' ? iiOsAgentWorkTicketWorkflow : workflow}@$reference',
      actor: 'test-bot',
      subject: 'test',
      environment: iiOsAgentEnvironment,
    ),
  );
}

void seedCredentialOwner(
  CredentialFirestoreFake firestore,
  CodexCredentialOwner owner, {
  bool empty = false,
}) {
  final p = owner.principal;
  firestore
      .documents['workspaces/${owner.workspaceId}/codexAuth/example~project'] = {
    'repository': p.repository,
    'repositoryId': p.repositoryId,
    'status': 'valid',
    if (!empty) 'secretDigest': 'a' * 64,
    if (!empty)
      'secretUpdatedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 29)),
  };
  firestore.documents[owner.ticket
      ? 'workspaces/${owner.workspaceId}/agentActivations/item-1'
      : 'codexAuthSessions/session-1'] = {
    'workspaceId': owner.workspaceId,
    'repository': p.repository,
    'repositoryId': p.repositoryId,
    'status': owner.ticket ? 'consumed' : 'dispatching',
    'claimId': 'claim-1',
    'workflowRunId': p.runId,
    'workflowRunAttempt': p.runAttempt,
    'workflowSha': p.sha,
    'runId': p.runId,
    'runAttempt': p.runAttempt,
    'verificationRunId': p.runId,
    'verificationRunAttempt': p.runAttempt,
    'verificationWorkflowSha': p.sha,
  };
}
