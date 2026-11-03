import '../models/data_plane_connection.dart';
import '../models/models.dart';
import '../services/api_client.dart';

/// The resource mutations used by the two tenant administration pages.
///
/// Keeping this interface narrower than the full tenant repository makes the
/// permission-narrowing behavior testable without Firebase or a widget tree.
abstract interface class OrganizationResourceRepository {
  Future<void> promoteLegacyWorkspace({
    required String organizationId,
    required String sourceWorkspaceId,
  });

  Future<DataPlaneValidationModel> saveGcpResource({
    required String organizationId,
    required OrganizationGcpResourceDraft resource,
  });

  Future<void> saveRunnerPool({
    required String organizationId,
    required OrganizationRunnerPoolDraft resource,
  });

  Future<void> syncFleetRunnerPool({required String organizationId});

  Future<void> saveWorkspaceResourceGrants({
    required String workspaceId,
    required WorkspaceResourceGrantsModel grants,
  });
}

/// Tenant-tier reads and writes.
///
/// Separate from the workspace repositories because the questions are
/// different: who belongs to us, and which projects may they open. Belonging to
/// a tenant is not access to its projects, so the two never share a call.
final class OrganizationRepository implements OrganizationResourceRepository {
  const OrganizationRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> promoteLegacyWorkspace({
    required String organizationId,
    required String sourceWorkspaceId,
  }) async {
    await _api.post(
      'v1/organizations/$organizationId/resources/promote',
      body: {'sourceWorkspaceId': sourceWorkspaceId},
    );
  }

  /// Creates a project inside [organizationId]. When it is omitted the server
  /// starts a new organization with the same name and creates its first
  /// workspace, preserving self-serve onboarding without creating a V1 orphan.
  Future<String> createWorkspace({
    String? organizationId,
    required String name,
    required String environment,
    String? inheritFromWorkspaceId,
  }) async {
    final id = organizationId?.trim() ?? '';
    final response = await _api.post(
      id.isEmpty ? 'v1/workspaces' : 'v1/organizations/$id/workspaces',
      body: {
        'name': name,
        'environment': environment,
        if (id.isEmpty) 'organizationName': name,
        if ((inheritFromWorkspaceId ?? '').isNotEmpty)
          'inheritFromWorkspaceId': inheritFromWorkspaceId,
      },
    );
    final workspaceId = asJsonMap(response['data'])['id']?.toString() ?? '';
    if (workspaceId.isEmpty) {
      throw const ApiFailure(
        'workspace_create_failed',
        'ii-os did not return the new workspace.',
      );
    }
    return workspaceId;
  }

  @override
  Future<void> saveWorkspaceResourceGrants({
    required String workspaceId,
    required WorkspaceResourceGrantsModel grants,
  }) async {
    await _api.put(
      'v1/workspaces/$workspaceId/resource-grants',
      body: grants.toJson(),
    );
  }

  @override
  Future<DataPlaneValidationModel> saveGcpResource({
    required String organizationId,
    required OrganizationGcpResourceDraft resource,
  }) async {
    final response = await _api.post(
      'v1/organizations/$organizationId/resources/gcp/${resource.id}/validate',
      body: resource.toJson(),
    );
    return DataPlaneValidationModel.fromJson(asJsonMap(response['data']));
  }

  @override
  Future<void> saveRunnerPool({
    required String organizationId,
    required OrganizationRunnerPoolDraft resource,
  }) async {
    await _api.put(
      'v1/organizations/$organizationId/resources/runners/${resource.id}',
      body: resource.toJson(),
    );
  }

  @override
  Future<void> syncFleetRunnerPool({required String organizationId}) async {
    await _api.post('v1/organizations/$organizationId/resources/runners/sync');
  }
}
