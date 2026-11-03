part of 'api.dart';

extension on IiOsApi {
  Future<Response?> _agentReadinessRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length != 4 ||
        path[3] != 'agent-readiness' ||
        request.method != 'GET') {
      return null;
    }
    await store.requireAccess(actor, workspaceId, Capability.workspaceRead);
    final workspace = await store.getWorkspace(workspaceId);
    final selected = request.url.queryParameters['repository'];
    if (selected != null && !workspace.repositories.contains(selected)) {
      throw const ApiError(
        400,
        'repository_not_allowed',
        'Select a repository connected to this workspace.',
      );
    }
    final repositories = selected == null
        ? workspace.repositories
        : <String>[selected];
    final repositoryHealth = <AgentRepositoryHealth>[];
    GitHubClient? github;
    Object? connectionError;
    try {
      github = await githubForWorkspace(workspace);
    } on Object catch (error) {
      connectionError = error;
    }
    for (final repository in repositories) {
      if (github != null) {
        repositoryHealth.add(
          await inspectAgentRepositoryHealth(
            workspace: workspace,
            repository: repository,
            github: github,
            codexAuth: workflowApi.codexAuth,
          ),
        );
        continue;
      }
      repositoryHealth.add(
        resolveAgentRepositoryHealth(
          repository: repository,
          checkedAt: DateTime.now().toUtc(),
          checks: [
            readinessCheck(
              id: 'github_installation',
              label: 'GitHub App installation connected',
              passed: false,
              repository: repository,
              detail: connectionError is ApiError
                  ? connectionError.message
                  : 'ii-os could not use this workspace GitHub App connection.',
              guidance: 'Open GitHub setup and reconnect this repository.',
            ),
          ],
        ),
      );
    }
    final repositoriesReady =
        repositoryHealth.isNotEmpty &&
        repositoryHealth.every((health) => health.dispatchAllowed);
    final checkedAt = DateTime.now().toUtc();
    return jsonResponse(200, {
      'status': repositoriesReady ? 'ready' : 'action_required',
      'checkedAt': checkedAt.toIso8601String(),
      'workspace': {
        'status': 'ready',
        'dispatchAllowed': true,
        'checkedAt': checkedAt.toIso8601String(),
        'checks': <Map<String, Object?>>[],
      },
      'repositories': repositoryHealth
          .map((health) => health.toJson())
          .toList(),
      'checks': [for (final health in repositoryHealth) ...health.checks],
    }, requestId: requestId);
  }
}
