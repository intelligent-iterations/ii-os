part of 'api.dart';

extension _WorkspaceResourceRoutes on IiOsApi {
  Future<Response?> _workspaceResourceRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length != 4 || path[3] != 'resource-grants') return null;
    if (request.method != 'PUT') return null;

    final workspace = await store.getWorkspace(workspaceId);
    final workspaceMembership = await store.getMembership(
      workspaceId,
      actor.uid,
    );
    final workspaceAllowed =
        workspaceMembership?.allows(Capability.workspaceManage) == true;
    final organizationMembership =
        workspaceAllowed || workspace.organizationId.isEmpty
        ? null
        : await organizations.getMembership(
            workspace.organizationId,
            actor.uid,
          );
    final allowed =
        workspaceAllowed ||
        organizationMembership?.allows(
              OrganizationCapability.integrationsManage,
            ) ==
            true;
    if (!allowed) {
      throw const ApiError(
        403,
        'forbidden',
        'Your role does not allow workspace resource selection.',
      );
    }
    final body = await readJsonObject(request);
    final grants = WorkspaceResourceGrants.fromWorkspaceData({
      'resourceGrantVersion': workspaceResourceGrantVersion,
      'resourceGrants': body,
    }, const OrganizationResourceCatalog.empty());
    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: 'workspace.resource_grants.save',
      targetType: 'workspace_resource_grants',
      targetId: workspaceId,
      metadata: {'organizationId': workspace.organizationId},
      execute: () =>
          WorkspaceResourceGrantStore(
            store.firestore,
            emulated: store.emulated,
          ).save(
            organizationId: workspace.organizationId,
            workspaceId: workspaceId,
            grants: grants,
          ),
    );
  }
}
