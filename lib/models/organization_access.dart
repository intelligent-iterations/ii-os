import 'data_plane_connection.dart';
import 'models.dart';

/// One organization the signed-in person belongs to, and how they stand in it.
final class OrganizationAccess {
  const OrganizationAccess({
    required this.id,
    required this.name,
    required this.role,
    required this.capabilities,
    this.roleId = 'member',
    this.resources = const OrganizationResourceCatalogModel(),
    this.connection,
  });

  factory OrganizationAccess.fromJson(JsonMap json) {
    final organization = asJsonMap(json['organization']);
    final membership = asJsonMap(json['membership']);
    final id = organization['id']?.toString() ?? '';
    final rawConnection = asJsonMap(organization['connection']);
    final connection = rawConnection.isEmpty
        ? null
        : DataPlaneConnectionModel.fromJson(rawConnection);
    return OrganizationAccess(
      id: id,
      name: organization['name']?.toString() ?? 'Organization',
      role:
          membership['roleLabel']?.toString() ??
          membership['role']?.toString() ??
          'Member',
      roleId: membership['role']?.toString() ?? 'member',
      capabilities:
          (membership['effectiveCapabilities'] as List<Object?>? ?? const [])
              .whereType<String>()
              .toSet(),
      resources: OrganizationResourceCatalogModel.fromJson(organization),
      connection:
          connection?.isOrganizationBound == true &&
              connection?.organizationId == id
          ? connection
          : null,
    );
  }

  final String id;
  final String name;
  final String role;
  final String roleId;
  final Set<String> capabilities;
  final OrganizationResourceCatalogModel resources;
  final DataPlaneConnectionModel? connection;

  bool can(String capability) => capabilities.contains(capability);
}

extension SessionOrganizationConnection on SessionModel {
  /// The credential owner for [workspaceId].
  ///
  /// Schema 3 lives on the organization. The workspace value is only the V1
  /// migration shim, and is accepted solely when it is bound to that exact
  /// workspace.
  DataPlaneConnectionModel? connectionForWorkspace(String? workspaceId) {
    if (workspaceId == null || workspaceId.isEmpty) return null;
    final access = workspaces
        .where((item) => item.workspace.id == workspaceId)
        .firstOrNull;
    if (access == null) return null;
    final serverResolved = access.workspace.resolvedConnection;
    if (serverResolved != null) return serverResolved;
    final organization = organizationFor(workspaceId);
    final grant = access.workspace.resourceGrants.primaryGcp;
    final selected = grant == null
        ? null
        : organization?.resources.gcpById(grant.resourceId);
    final owned = selected?.active == true ? selected?.connection : null;
    final promotedLegacy =
        owned != null &&
        selected?.legacySourceWorkspaceId.isNotEmpty == true &&
        !owned.isOrganizationBound &&
        owned.workspaceId == selected?.legacySourceWorkspaceId;
    if (owned != null &&
        (owned.isBoundTo(
              workspaceId: workspaceId,
              organizationId: access.workspace.organizationId,
            ) ||
            promotedLegacy)) {
      return owned;
    }
    if (organization?.resources.gcp.isNotEmpty == true ||
        access.workspace.resourceGrantVersion == 1) {
      return null;
    }
    final migrated = organization?.connection;
    if (migrated != null &&
        migrated.isBoundTo(
          workspaceId: workspaceId,
          organizationId: access.workspace.organizationId,
        )) {
      return migrated;
    }
    final legacy = access.workspace.connection;
    return legacy?.isBoundTo(
              workspaceId: workspaceId,
              organizationId: access.workspace.organizationId,
            ) ==
            true
        ? legacy
        : null;
  }
}
