part of 'app_controller.dart';

extension AppControllerOrganizations on AppController {
  Future<String> createWorkspace(
    String name,
    String environment, {
    String? organizationId,
  }) async {
    final selectedWorkspace = workspace;
    final organization = session?.organizationFor(selectedWorkspace?.id);
    final legacySource = session?.workspaces
        .where(
          (access) =>
              access.workspace.organizationId == organizationId &&
              access.workspace.connection?.workspaceId == access.workspace.id,
        )
        .map((access) => access.workspace)
        .firstOrNull;
    final inheritFromWorkspaceId =
        organizationId != null &&
            organization?.id == organizationId &&
            organization?.resources.gcp.isEmpty == true &&
            legacySource != null
        ? legacySource.id
        : null;
    final workspaceId = await organizations.createWorkspace(
      organizationId: organizationId,
      name: name,
      environment: environment,
      inheritFromWorkspaceId: inheritFromWorkspaceId,
    );
    await _loadSession(preferredWorkspaceId: workspaceId);
    openWorkspaceResourceSelection = true;
    await refreshDashboard();
    _notifyWorkspaceCreated();
    return workspaceId;
  }

  Future<void> workspaceResourceGrantsSaved() async {
    openWorkspaceResourceSelection = false;
    await refresh();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
