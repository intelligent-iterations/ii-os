part of 'api.dart';

extension on IiOsApi {
  Future<Response?> _githubSetupRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length != 4 ||
        path[3] != 'github-setup' ||
        request.method != 'GET') {
      return null;
    }
    await store.requireAccess(actor, workspaceId, Capability.workspaceRead);
    final workspace = await store.getWorkspace(workspaceId);
    final checkedAt = DateTime.now().toUtc();
    final repositoryHealth = <AgentRepositoryHealth>[];
    var githubAppSettingsUrl = '';

    GitHubClient? github;
    Object? connectionError;
    if (workspace.githubInstallationId != null) {
      try {
        github = await githubForWorkspace(workspace);
      } on Object catch (error) {
        connectionError = error;
      }
    }

    for (final repository in workspace.repositories) {
      final checks = <Map<String, Object?>>[
        readinessCheck(
          id: 'github_installation',
          label: 'GitHub App installation is connected',
          passed: workspace.githubInstallationId != null,
          repository: repository,
          detail: workspace.githubInstallationId == null
              ? 'No GitHub App installation is connected.'
              : 'Installation ${workspace.githubInstallationId} is connected.',
          guidance:
              'Connect the GitHub App installation that owns this repository.',
        ),
        readinessCheck(
          id: 'repository_selected',
          label: 'Repository is selected',
          passed: true,
          repository: repository,
          detail: '$repository is selected for this workspace.',
          guidance: 'Select the repository ii-os may access.',
        ),
      ];
      if (github == null) {
        checks.add({
          'id': 'github_repository_access',
          'label': 'GitHub App credential and repository access work',
          'status': 'unable_to_verify',
          'detail': connectionError is ApiError
              ? connectionError.message
              : 'ii-os could not use the workspace GitHub App credential.',
          'guidance':
              'Check the customer Secret Manager key, its service-account access, and the installation ID, then retry.',
          'repository': repository,
        });
      } else {
        try {
          checks.addAll(
            await github.inspectGitHubSetupRepository(
              workspace,
              repository: repository,
            ),
          );
          if (githubAppSettingsUrl.isEmpty) {
            try {
              githubAppSettingsUrl = await github.permissionActionUrl(
                workspace,
              );
            } on Object {
              // The direct checks remain authoritative. The UI has a safe
              // manual GitHub settings fallback when this link is unavailable.
            }
          }
        } on ApiError catch (error) {
          checks.add(
            readinessUnable(
              id: 'github_repository_access',
              label: 'GitHub App credential and repository access work',
              repository: repository,
              error: error,
              guidance:
                  'Grant this installation access to the repository and verify the customer Secret Manager key, then retry.',
            ),
          );
        } on Object {
          checks.add({
            'id': 'github_repository_access',
            'label': 'GitHub App credential and repository access work',
            'status': 'unable_to_verify',
            'detail': 'ii-os could not complete the direct GitHub check.',
            'guidance':
                'Verify the customer Secret Manager key and repository selection, then retry.',
            'repository': repository,
          });
        }
      }
      repositoryHealth.add(
        resolveGitHubSetupRepositoryHealth(
          repository: repository,
          checks: checks,
          checkedAt: checkedAt,
        ),
      );
    }

    final globalChecks = <Map<String, Object?>>[
      if (workspace.repositories.isEmpty) ...[
        readinessCheck(
          id: 'github_installation',
          label: 'GitHub App installation is connected',
          passed: workspace.githubInstallationId != null,
          detail: workspace.githubInstallationId == null
              ? 'No GitHub App installation is connected.'
              : 'Installation ${workspace.githubInstallationId} is saved.',
          guidance: 'Connect a GitHub App installation.',
        ),
        readinessCheck(
          id: 'repository_selected',
          label: 'Repository is selected',
          passed: false,
          detail: 'No repository is selected for this workspace.',
          guidance: 'Select the repository ii-os may access.',
        ),
      ],
    ];
    final ready =
        repositoryHealth.isNotEmpty &&
        repositoryHealth.every((health) => health.dispatchAllowed);

    return jsonResponse(200, {
      'status': ready ? 'ready' : 'action_required',
      'checkedAt': checkedAt.toIso8601String(),
      'githubAppSettingsUrl': githubAppSettingsUrl,
      'workspace': {
        'status': workspace.githubInstallationId != null
            ? 'ready'
            : 'action_required',
        'dispatchAllowed': workspace.githubInstallationId != null,
        'checkedAt': checkedAt.toIso8601String(),
        'checks': <Object?>[],
      },
      'repositories': repositoryHealth
          .map((health) => health.toJson())
          .toList(),
      'checks': [
        ...globalChecks,
        for (final health in repositoryHealth) ...health.checks,
      ],
    }, requestId: requestId);
  }
}
