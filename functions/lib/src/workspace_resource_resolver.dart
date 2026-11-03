import 'api_error.dart';
import 'domain.dart';
import 'organization_resources.dart';
import 'workspace_resource_grants.dart';
import 'workspace_store.dart';

/// Resolves a workspace reference through its organization's current envelope.
final class WorkspaceResourceResolver {
  const WorkspaceResourceResolver(this.store);

  final WorkspaceStore store;

  Future<OrganizationGitHubResource> requirePrimaryGitHub(
    Workspace workspace,
  ) async {
    _requireValid(workspace);
    final resource = workspace.primaryGitHubResource;
    if (resource == null || !resource.active) {
      throw const ApiError(
        409,
        'workspace_github_resource_required',
        'Ask an Organization Admin to make a GitHub App available, then select it for this workspace.',
      );
    }
    return resource;
  }

  Future<({OrganizationRunnerPool pool, WorkspaceRunnerGrant grant})>
  requirePrimaryRunner(Workspace workspace) async {
    _requireValid(workspace);
    final grant = workspace.resourceGrants.runners
        .where((item) => item.primary)
        .firstOrNull;
    final pool = grant == null
        ? null
        : workspace.organizationResources.runner(grant.resourceId);
    if (grant == null || pool == null || !pool.active) {
      throw const ApiError(
        409,
        'workspace_runner_pool_required',
        'Ask an Organization Admin to make a runner pool available, then select it for this workspace.',
      );
    }
    return (pool: pool, grant: grant);
  }

  Future<Workspace> load(String workspaceId) async {
    final workspace = await store.getWorkspace(workspaceId);
    _requireValid(workspace);
    return workspace;
  }

  void _requireValid(Workspace workspace) {
    final errors = workspace.resourceGrants.validateAgainst(
      workspace.organizationResources,
    );
    if (errors.isNotEmpty) {
      throw ApiError(
        409,
        'workspace_resource_grant_stale',
        'The workspace resource selection is no longer allowed by its organization.',
        details: {'errors': errors.toList()..sort()},
      );
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
