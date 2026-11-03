import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'domain.dart';
import 'organization.dart';
import 'organization_store.dart';

/// Bounded organization-directory reads and per-project access mutations.
extension OrganizationPeopleStore on OrganizationStore {
  static const directoryLimit = 100;
  static const memberWorkspaceLimit = 100;

  /// People who belong to [organizationId], independently of project access.
  Future<List<Map<String, Object?>>> listPeople(String organizationId) async {
    final snapshots = await firestore
        .collection(OrganizationStore.memberships)
        .where('organizationId', WhereFilter.equal, organizationId)
        .limit(directoryLimit + 1)
        .get();
    _requireWithinLimit(
      snapshots.size,
      directoryLimit,
      code: 'organization_member_limit_exceeded',
      message: 'This organization has too many people to show on one page.',
    );
    final people = snapshots.docs
        .map((item) => OrganizationMembership.fromData(item.data()).toJson())
        .toList();
    people.sort(
      (left, right) =>
          (left['email'] as String).compareTo(right['email'] as String),
    );
    return people;
  }

  /// Projects inside [organizationId], including ones the caller does not use.
  ///
  /// This is available only behind the organization access-management route;
  /// session discovery remains limited to the caller's own grants.
  Future<List<Map<String, Object?>>> listWorkspacesForPeople(
    String organizationId,
  ) async {
    final snapshots = await firestore
        .collection('workspaces')
        .where('organizationId', WhereFilter.equal, organizationId)
        .limit(directoryLimit + 1)
        .get();
    _requireWithinLimit(
      snapshots.size,
      directoryLimit,
      code: 'organization_workspace_limit_exceeded',
      message: 'This organization has too many workspaces to show at once.',
    );
    final workspaces = snapshots.docs
        .map(
          (item) => <String, Object?>{
            'id': item.ref.id,
            'name': item.data()['name'] as String? ?? 'Untitled workspace',
            'environment': item.data()['environment'] as String? ?? 'dev',
          },
        )
        .toList();
    workspaces.sort(
      (left, right) =>
          (left['name'] as String).compareTo(right['name'] as String),
    );
    return workspaces;
  }

  /// The projects currently or formerly assigned to one organization member.
  Future<List<Map<String, Object?>>> listMemberWorkspaceAccess({
    required String organizationId,
    required String uid,
  }) async {
    final organizationMember = await firestore
        .collection(OrganizationStore.memberships)
        .doc(membershipId(organizationId, uid))
        .get();
    if (!organizationMember.exists) {
      throw const ApiError(
        404,
        'organization_member_not_found',
        'That person does not belong to this organization.',
      );
    }
    final snapshots = await firestore
        .collection('workspaceMemberships')
        .where('organizationId', WhereFilter.equal, organizationId)
        .where('uid', WhereFilter.equal, uid)
        .limit(memberWorkspaceLimit + 1)
        .get();
    _requireWithinLimit(
      snapshots.size,
      memberWorkspaceLimit,
      code: 'member_workspace_limit_exceeded',
      message: 'This person has too many workspace assignments to show.',
    );
    return snapshots.docs
        .map((item) => Membership.fromData(item.data()).toJson())
        .toList();
  }

  /// Turns one person's access to one project on or off.
  ///
  /// A missing workspace membership is a first-time grant when [suspended] is
  /// false. Suspension retains an existing record so restoring it keeps the
  /// prior role and feature claims.
  Future<Map<String, Object?>> setWorkspaceAccess({
    required String organizationId,
    required String workspaceId,
    required String uid,
    required bool suspended,
  }) async {
    final workspaceRef = firestore.collection('workspaces').doc(workspaceId);
    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    final organizationMemberRef = firestore
        .collection(OrganizationStore.memberships)
        .doc(membershipId(organizationId, uid));
    final workspaceMemberRef = firestore
        .collection('workspaceMemberships')
        .doc('${workspaceId}_$uid');

    return firestore.runTransaction<Map<String, Object?>>((transaction) async {
      final documents = await Future.wait([
        transaction.get(workspaceRef),
        transaction.get(organizationRef),
        transaction.get(organizationMemberRef),
        transaction.get(workspaceMemberRef),
      ]);
      final workspace = documents[0];
      final organization = documents[1];
      final organizationMember = documents[2];
      final workspaceMember = documents[3];
      if (!workspace.exists ||
          workspace.data()?['organizationId'] != organizationId ||
          !organization.exists) {
        throw const ApiError(
          404,
          'workspace_not_found',
          'That workspace does not belong to this organization.',
        );
      }
      if (organization.data()?['deletionStartedAt'] != null) {
        throw const ApiError(
          409,
          'organization_deletion_in_progress',
          'This organization is being deleted.',
        );
      }
      if (!organizationMember.exists) {
        throw const ApiError(
          404,
          'organization_member_not_found',
          'That person does not belong to this organization.',
        );
      }

      final now = Timestamp.now();
      final existing = workspaceMember.data();
      if (!workspaceMember.exists || existing == null) {
        if (suspended) {
          throw const ApiError(
            404,
            'workspace_access_not_found',
            'That person does not have access to this workspace.',
          );
        }
        final email = organizationMember.data()?['email'] as String? ?? '';
        transaction.set(workspaceMemberRef, {
          'workspaceId': workspaceId,
          'organizationId': organizationId,
          'uid': uid,
          'email': email,
          'role': WorkspaceRole.viewOnly.value,
          'featureClaims': <String>[Capability.workspaceRead.value],
          'status': 'active',
          'createdAt': now,
          'updatedAt': now,
        });
        return _accessResult(
          organizationId: organizationId,
          organizationName:
              organization.data()?['name'] as String? ?? 'Organization',
          workspaceId: workspaceId,
          workspaceName: workspace.data()?['name'] as String? ?? 'Workspace',
          uid: uid,
          email: email,
          suspended: false,
          changed: true,
          granted: true,
        );
      }

      if (existing['role'] == WorkspaceRole.owner.value && suspended) {
        throw const ApiError(
          409,
          'owner_access_required',
          'Transfer ownership before switching off the owner of a workspace.',
        );
      }
      final boundOrganization = existing['organizationId'] as String? ?? '';
      if (boundOrganization.isNotEmpty && boundOrganization != organizationId) {
        throw const ApiError(
          409,
          'workspace_membership_tenant_mismatch',
          'That workspace access record belongs to another organization.',
        );
      }
      final wasSuspended = existing['status'] == 'suspended';
      final changed = wasSuspended != suspended || boundOrganization.isEmpty;
      if (changed) {
        transaction.update(workspaceMemberRef, {
          FieldPath(const ['organizationId']): organizationId,
          FieldPath(const ['status']): suspended ? 'suspended' : 'active',
          FieldPath(const ['updatedAt']): now,
        });
      }
      return _accessResult(
        organizationId: organizationId,
        organizationName:
            organization.data()?['name'] as String? ?? 'Organization',
        workspaceId: workspaceId,
        workspaceName: workspace.data()?['name'] as String? ?? 'Workspace',
        uid: uid,
        email: organizationMember.data()?['email'] as String? ?? '',
        suspended: suspended,
        changed: changed,
        granted: false,
      );
    });
  }
}

void _requireWithinLimit(
  int count,
  int limit, {
  required String code,
  required String message,
}) {
  if (count > limit) throw ApiError(409, code, message);
}

Map<String, Object?> _accessResult({
  required String organizationId,
  required String organizationName,
  required String workspaceId,
  required String workspaceName,
  required String uid,
  required String email,
  required bool suspended,
  required bool changed,
  required bool granted,
}) => {
  'organizationId': organizationId,
  'organizationName': organizationName,
  'workspaceId': workspaceId,
  'workspaceName': workspaceName,
  'uid': uid,
  'email': email,
  'suspended': suspended,
  'changed': changed,
  'granted': granted,
};
