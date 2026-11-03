import 'package:ii_os_functions/src/agent_dispatch_result.dart';
import 'package:ii_os_functions/src/agent_finalization_receipt.dart';
import 'package:ii_os_functions/src/github_actions_oidc.dart';
import 'package:test/test.dart';

void main() {
  test('binds the finalization receipt to the exact dispatch and run', () {
    final result = AgentDispatchResult.parse({
      'dispatch_id': 'human:item-1',
      'repository': 'acme-co/example-app',
      'repository_id': 123456789,
      'issue_number': 42,
      'project_item_id': 'PVTI_item_1',
      'outcome': 'not_ready',
      'status': 'todo',
      'comments': const <String>[],
      'pull_request': null,
      'automation_failure': {
        'code': 'agent_worker_failed',
        'detail': 'The worker did not complete.',
      },
    });
    const principal = GitHubActionsPrincipal(
      repository: 'acme-co/example-app',
      repositoryId: 123456789,
      runId: 9876543210,
      runAttempt: 2,
      sha: '1111111111111111111111111111111111111111',
      ref: 'refs/tags/ii-os-agent-v4-proof',
      workflowRef: '',
      jobWorkflowRef: '',
      actor: 'example-app[bot]',
      subject: 'repo:acme-co/example-app:environment:maintainer',
      environment: 'maintainer',
    );

    final response = agentFinalizationResponse(
      workspaceId: 'workspace-1',
      projectItemId: 'PVTI_item_1',
      principal: principal,
      result: result,
      resultDigest: 'a' * 64,
      idempotent: true,
      mutated: true,
      projectStatus: 'todo',
    );

    expect(response, {
      'finalized': true,
      'idempotent': true,
      'mutated': true,
      'projectStatus': 'todo',
      'receipt': {
        'schema_version': 1,
        'finalized': true,
        'workspace_id': 'workspace-1',
        'project_item_id': 'PVTI_item_1',
        'dispatch_id': 'human:item-1',
        'repository': 'acme-co/example-app',
        'repository_id': 123456789,
        'issue_number': 42,
        'run_id': 9876543210,
        'run_attempt': 2,
        'result_digest': 'a' * 64,
      },
    });
    expect(
      agentFinalizationResponse(
        workspaceId: 'workspace-1',
        projectItemId: 'PVTI_item_1',
        principal: principal,
        result: result,
        resultDigest: 'a' * 64,
        idempotent: false,
        mutated: true,
        projectStatus: 'ready_for_qa',
        pullRequestUrl: 'https://github.com/acme-co/ui-app/pull/9',
      ),
      containsPair(
        'pullRequestUrl',
        'https://github.com/acme-co/ui-app/pull/9',
      ),
    );
  });
}
