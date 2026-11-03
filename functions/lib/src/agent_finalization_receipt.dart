import 'agent_dispatch_result.dart';
import 'github_actions_oidc.dart';

Map<String, Object?> agentFinalizationReceipt({
  required String workspaceId,
  required String projectItemId,
  required GitHubActionsPrincipal principal,
  required AgentDispatchResult result,
  required String resultDigest,
}) => {
  'schema_version': 1,
  'finalized': true,
  'workspace_id': workspaceId,
  'project_item_id': projectItemId,
  'dispatch_id': result.dispatchId,
  'repository': principal.repository,
  'repository_id': principal.repositoryId,
  'issue_number': result.issueNumber,
  'run_id': principal.runId,
  'run_attempt': principal.runAttempt,
  'result_digest': resultDigest,
};

Map<String, Object?> agentFinalizationResponse({
  required String workspaceId,
  required String projectItemId,
  required GitHubActionsPrincipal principal,
  required AgentDispatchResult result,
  required String resultDigest,
  required bool idempotent,
  required bool mutated,
  required String? projectStatus,
  String? pullRequestUrl,
}) => {
  'finalized': true,
  'idempotent': idempotent,
  'mutated': mutated,
  'projectStatus': projectStatus,
  'receipt': agentFinalizationReceipt(
    workspaceId: workspaceId,
    projectItemId: projectItemId,
    principal: principal,
    result: result,
    resultDigest: resultDigest,
  ),
  'pullRequestUrl': ?pullRequestUrl,
};
