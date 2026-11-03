part of 'workspace_resources_view_model.dart';

extension _WorkspaceResourceGrantOrdering on WorkspaceResourcesViewModel {
  List<WorkspaceGcpGrantModel> _sortedGcpGrants(String primaryId) =>
      (_gcpGrants.values
          .map(
            (grant) => WorkspaceGcpGrantModel(
              resourceId: grant.resourceId,
              permissions: grant.permissions,
              primary: grant.resourceId == primaryId,
            ),
          )
          .toList()
        ..sort((a, b) => a.resourceId.compareTo(b.resourceId)));

  List<WorkspaceGitHubGrantModel> _sortedGitHubGrants(String primaryId) =>
      (_githubGrants.values
          .map(
            (grant) => WorkspaceGitHubGrantModel(
              resourceId: grant.resourceId,
              repositories: grant.repositories,
              permissions: grant.permissions,
              primary: grant.resourceId == primaryId,
            ),
          )
          .toList()
        ..sort((a, b) => a.resourceId.compareTo(b.resourceId)));

  List<WorkspaceRunnerGrantModel> _sortedRunnerGrants(String primaryId) =>
      (_runnerGrants.values
          .map(
            (grant) => WorkspaceRunnerGrantModel(
              resourceId: grant.resourceId,
              capabilities: grant.capabilities,
              maxCpu: grant.maxCpu,
              maxRamMiB: grant.maxRamMiB,
              maxConcurrent: grant.maxConcurrent,
              primary: grant.resourceId == primaryId,
            ),
          )
          .toList()
        ..sort((a, b) => a.resourceId.compareTo(b.resourceId)));
}
