part of 'api.dart';

extension on IiOsApi {
  Future<Response?> _agentTicketResetRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    final isReset =
        path.length == 7 &&
        path[4] == 'items' &&
        path[6] == 'reset' &&
        request.method == 'PATCH';
    if (!isReset) return null;

    final access = await store.requireAccessContext(
      actor,
      workspaceId,
      Capability.ticketsWrite,
    );
    final body = await readJsonObject(request);
    final projectId = requiredString(body, 'projectId', maxLength: 200);
    final selectedRepository = selectedWorkspaceRepository(
      access.workspace,
      body['repository'],
    );
    final github = await githubForWorkspace(access.workspace);
    final project = await github.getProject(
      access.workspace,
      projectId,
      repository: selectedRepository,
    );
    final target = AgentTicketActivationTarget.fromProject(
      projectId: projectId,
      itemId: path[5],
      project: project,
      expectedRepository: selectedRepository,
    );
    if (target.issueState != 'OPEN') {
      throw const ApiError(
        409,
        'agent_ticket_closed',
        'Reopen the issue before resetting it.',
      );
    }

    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: 'agent.ticket.reset',
      targetType: 'github_issue',
      targetId: '${target.repository}#${target.issueNumber}',
      metadata: {
        'projectId': projectId,
        'projectItemId': target.itemId,
        'fromStatus': target.status,
        'preservesIssue': true,
        'clearsLabels': true,
      },
      execute: () async {
        final activations = AgentActivationStore(store, engines: agentEngines);
        await activations.beginReset(
          workspaceId: workspaceId,
          projectItemId: target.itemId,
          resetRequestId: requestId,
          actor: actor,
        );
        await github.clearProjectItemField(
          access.workspace,
          repository: target.repository,
          projectId: projectId,
          itemId: target.itemId,
          fieldId: target.statusFieldId,
        );
        await github.clearIssueLabels(
          access.workspace,
          repository: target.repository,
          number: target.issueNumber,
        );
        await activations.completeReset(
          workspaceId: workspaceId,
          projectItemId: target.itemId,
          resetRequestId: requestId,
        );
        return {
          'projectId': projectId,
          'projectItemId': target.itemId,
          'repository': target.repository,
          'issueNumber': target.issueNumber,
          'status': '',
          'reset': true,
        };
      },
    );
  }
}
