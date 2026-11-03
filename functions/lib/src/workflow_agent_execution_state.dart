part of 'workflow_api.dart';

extension WorkflowAgentExecutionState on WorkflowApi {
  Future<Response> _recordAgentExecutionState(
    Request request,
    String requestId,
    String workspaceId,
    String projectItemId,
    GitHubActionsPrincipal principal,
  ) async {
    final body = await readJsonObject(request);
    const required = {
      'dispatchId',
      'issueNumber',
      'executionId',
      'state',
      'inputDigest',
      'artifactDigest',
    };
    if (!body.keys.toSet().containsAll(required) ||
        body.keys.any((key) => !{...required, 'reservationId'}.contains(key))) {
      throw _executionStateRequestInvalid;
    }
    final claimId = requiredString(body, 'dispatchId', maxLength: 200);
    final executionId = requiredString(body, 'executionId', maxLength: 160);
    final state = requiredString(body, 'state', maxLength: 32);
    final inputDigest = requiredString(body, 'inputDigest', maxLength: 71);
    final artifactDigest = requiredString(
      body,
      'artifactDigest',
      maxLength: 71,
    );
    final reservation = body['reservationId'];
    final reservationId = reservation == null
        ? ''
        : requiredString(body, 'reservationId', maxLength: 36);
    final issueNumber = body['issueNumber'];
    final update = RuntimeAgentExecution.parseCallback(
      repositoryId: principal.repositoryId,
      runId: principal.runId,
      executionId: executionId,
      reservationId: reservationId,
      state: state,
      inputDigest: inputDigest,
      artifactDigest: artifactDigest,
    );
    if (issueNumber is! int || issueNumber <= 0 || update == null) {
      throw _executionStateRequestInvalid;
    }
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      workspaceId: workspaceId,
      action: 'agent.dispatch.execution.state',
      targetType: 'agent_execution',
      targetId: executionId,
      metadata: {
        'repository': principal.repository,
        'projectItemId': projectItemId,
        'issueNumber': issueNumber,
        'dispatchId': claimId,
        'state': state,
      },
      execute: () async {
        final recorded = await AgentActivationStore(store).recordExecutionState(
          principal: principal,
          workspaceId: workspaceId,
          projectItemId: projectItemId,
          claimId: claimId,
          issueNumber: issueNumber,
          backendId: 'agent-runtime',
          update: update,
          inputDigest: inputDigest,
          artifactDigest: artifactDigest,
        );
        // Admission, capacity and provisioning never move the ticket.
        if (state == 'running') {
          final projectId = recorded['projectId'] as String? ?? '';
          final fieldId = recorded['projectStatusFieldId'] as String? ?? '';
          final optionId =
              recorded['projectInProgressOptionId'] as String? ?? '';
          if ([projectId, fieldId, optionId].any((value) => value.isEmpty)) {
            throw _executionStateRequestInvalid;
          }
          final workspace = await store.getWorkspace(workspaceId);
          final github = await githubForWorkspace(workspace);
          await github.updateProjectItemField(
            workspace,
            projectId: projectId,
            itemId: projectItemId,
            fieldId: fieldId,
            value: {'singleSelectOptionId': optionId},
            repository: principal.repository,
          );
        }
        return recorded;
      },
    );
  }
}

const _executionStateRequestInvalid = ApiError(
  400,
  'agent_execution_state_invalid',
  'The execution state, identity or input binding is invalid.',
);
