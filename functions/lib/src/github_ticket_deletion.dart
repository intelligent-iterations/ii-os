part of 'github_client.dart';

extension GitHubTicketDeletion on GitHubClient {
  Future<Map<String, Object?>> removeWorkshopTicket(
    Workspace workspace, {
    required String repository,
    required int issueNumber,
    required String projectId,
    required String itemId,
  }) async {
    _requireRepository(workspace, repository);
    if (!workspace.containsProject(projectId)) {
      throw const ApiError(
        400,
        'project_not_allowed',
        'Project is not configured for this workspace.',
      );
    }
    _requireGitHubProjectPermission(workspace, level: 'write');
    _requireGitHubIssuePermission(workspace, level: 'write');
    final target = TicketDeletionTarget.fromProject(
      projectId: projectId,
      itemId: itemId,
      repository: repository,
      issueNumber: issueNumber,
      project: await getProject(workspace, projectId, repository: repository),
    );

    if (target.issueOpen) {
      await updateIssue(
        workspace,
        repository: repository,
        number: issueNumber,
        body: target.content.withAgentReady(false).toMarkdown(),
        state: 'closed',
      );
    }
    try {
      await _graphql(
        workspace,
        r'''
          mutation RemoveWorkshopTicket($projectId: ID!, $itemId: ID!) {
            deleteProjectV2Item(input: {projectId: $projectId, itemId: $itemId}) {
              deletedItemId
            }
          }
        ''',
        {'projectId': projectId, 'itemId': itemId},
        repository: repository,
      );
    } on Object {
      if (target.issueOpen) {
        try {
          await updateIssue(
            workspace,
            repository: repository,
            number: issueNumber,
            body: target.content.toMarkdown(),
            state: 'open',
          );
        } on Object {
          // Preserve the original Project-removal failure for the caller and
          // audit trail. A refresh will show the actual GitHub state.
        }
      }
      rethrow;
    }
    return {
      'repository': repository,
      'number': issueNumber,
      'projectId': projectId,
      'itemId': itemId,
      'issueClosed': target.issueOpen,
      'removedFromWorkshop': true,
    };
  }
}
