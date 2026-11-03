import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'organization_resources.dart';
import 'organization_store.dart';
import 'workspace_resource_grants.dart';

/// Persists a workspace's subset of its organization's resource envelopes.
final class WorkspaceResourceGrantStore {
  const WorkspaceResourceGrantStore(this.firestore, {this.emulated = false});

  final Firestore firestore;
  final bool emulated;

  Future<Map<String, Object?>> save({
    required String organizationId,
    required String workspaceId,
    required WorkspaceResourceGrants grants,
  }) async {
    final workspaceRef = firestore.collection('workspaces').doc(workspaceId);
    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    await firestore.runTransaction<void>((transaction) async {
      final workspace = await transaction.get(workspaceRef);
      final organization = await transaction.get(organizationRef);
      final workspaceData = workspace.data();
      final organizationData = organization.data();
      if (!workspace.exists ||
          workspaceData == null ||
          workspaceData['organizationId'] != organizationId) {
        throw const ApiError(
          404,
          'workspace_not_found',
          'Workspace not found in this organization.',
        );
      }
      if (!organization.exists || organizationData == null) {
        throw const ApiError(
          404,
          'organization_not_found',
          'Organization not found.',
        );
      }
      final catalog = OrganizationResourceCatalog.fromOrganizationData(
        organizationId,
        organizationData,
        emulated: emulated,
      );
      final errors = grants.validateAgainst(catalog);
      if (errors.isNotEmpty) {
        throw ApiError(
          400,
          'workspace_resource_grant_invalid',
          'A workspace can select only organization resources and lower limits.',
          details: {'errors': errors.toList()..sort()},
        );
      }
      final fields = grants.toJson();
      final repositories =
          grants.github.expand((grant) => grant.repositories).toSet().toList()
            ..sort();
      transaction.update(workspaceRef, {
        FieldPath(const ['resourceGrantVersion']):
            fields['resourceGrantVersion'],
        FieldPath(const ['resourceGrants']): fields['resourceGrants'],
        // Keep callers that still read the legacy field safe. This is derived
        // compatibility state, never an alternative authority.
        FieldPath(const ['repositories']): repositories,
        FieldPath(const ['githubInstallationId']): null,
        FieldPath(const ['updatedAt']): Timestamp.now(),
      });
    });
    return grants.toJson();
  }
}
