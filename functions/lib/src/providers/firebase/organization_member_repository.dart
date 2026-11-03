import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import '../../api_error.dart';
import '../../domain.dart';
import '../../organization.dart';
import '../../organization_membership_policy.dart';
import '../../organization_store.dart';

/// Firestore-backed tenant-member mutations and their bounded ownership reads.
extension OrganizationMemberRepository on OrganizationStore {
  static const _memberLimit = 100;
  static const _workspaceLimit = 100;

  Future<OrganizationMembership> updateOrganizationMember({
    required String organizationId,
    required String actorUid,
    required String uid,
    required OrganizationRole role,
    required Set<String> featureClaims,
  }) {
    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    final membersQuery = firestore
        .collection(OrganizationStore.memberships)
        .where('organizationId', WhereFilter.equal, organizationId)
        .limit(_memberLimit + 1);
    return firestore.runTransaction<OrganizationMembership>((
      transaction,
    ) async {
      final results = await Future.wait([
        transaction.get(organizationRef),
        transaction.getQuery(membersQuery),
      ]);
      _requireAcceptingChanges(
        results[0] as DocumentSnapshot<Map<String, Object?>>,
      );
      final snapshots = results[1] as QuerySnapshot<Map<String, Object?>>;
      _requireLimit(
        snapshots.size,
        _memberLimit,
        'organization_member_limit_exceeded',
        'This organization has too many people to edit safely.',
      );
      final members = snapshots.docs
          .map((snapshot) => OrganizationMembership.fromData(snapshot.data()))
          .toList(growable: false);
      final actor = members
          .where((member) => member.uid == actorUid)
          .firstOrNull;
      if (actor == null ||
          !actor.allows(OrganizationCapability.membersManage)) {
        throw const ApiError(
          403,
          'forbidden',
          'Your organization role does not allow this action.',
        );
      }
      final target = members.where((member) => member.uid == uid).firstOrNull;
      if (target == null) {
        throw const ApiError(
          404,
          'organization_member_not_found',
          'That person does not belong to this organization.',
        );
      }
      requireOrganizationMemberUpdateAllowed(
        actor: actor,
        target: target,
        nextRole: role,
        members: members,
      );
      final claims = boundedOrganizationClaims(
        actor: actor,
        targetRole: role,
        requested: featureClaims,
      );
      transaction.update(
        firestore
            .collection(OrganizationStore.memberships)
            .doc(membershipId(organizationId, uid)),
        {
          'role': role.value,
          'featureClaims': claims,
          'updatedAt': Timestamp.now(),
        },
      );
      return OrganizationMembership(
        organizationId: organizationId,
        uid: target.uid,
        email: target.email,
        role: role,
        featureClaims: claims.toSet(),
      );
    });
  }

  Future<int> removeOrganizationMember({
    required String organizationId,
    required String actorUid,
    required String uid,
  }) {
    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    final membersQuery = firestore
        .collection(OrganizationStore.memberships)
        .where('organizationId', WhereFilter.equal, organizationId)
        .limit(_memberLimit + 1);
    final targetWorkspacesQuery = firestore
        .collection('workspaceMemberships')
        .where('organizationId', WhereFilter.equal, organizationId)
        .where('uid', WhereFilter.equal, uid)
        .limit(_workspaceLimit + 1);
    return firestore.runTransaction<int>((transaction) async {
      final results = await Future.wait([
        transaction.get(organizationRef),
        transaction.getQuery(membersQuery),
        transaction.getQuery(targetWorkspacesQuery),
      ]);
      _requireAcceptingChanges(
        results[0] as DocumentSnapshot<Map<String, Object?>>,
      );
      final memberSnapshots = results[1] as QuerySnapshot<Map<String, Object?>>;
      final targetWorkspaceSnapshots =
          results[2] as QuerySnapshot<Map<String, Object?>>;
      _requireLimit(
        memberSnapshots.size,
        _memberLimit,
        'organization_member_limit_exceeded',
        'This organization has too many people to edit safely.',
      );
      _requireLimit(
        targetWorkspaceSnapshots.size,
        _workspaceLimit,
        'member_workspace_limit_exceeded',
        'This person has too many workspace assignments to remove.',
      );
      final members = memberSnapshots.docs
          .map((snapshot) => OrganizationMembership.fromData(snapshot.data()))
          .toList(growable: false);
      final actor = members
          .where((member) => member.uid == actorUid)
          .firstOrNull;
      if (actor == null ||
          !actor.allows(OrganizationCapability.membersManage)) {
        throw const ApiError(
          403,
          'forbidden',
          'Your organization role does not allow this action.',
        );
      }
      final target = members.where((member) => member.uid == uid).firstOrNull;
      if (target == null) {
        throw const ApiError(
          404,
          'organization_member_not_found',
          'That person does not belong to this organization.',
        );
      }
      final targetWorkspaces = targetWorkspaceSnapshots.docs
          .map((snapshot) => Membership.fromData(snapshot.data()))
          .toList(growable: false);
      final ownedWorkspaceIds = targetWorkspaces
          .where((membership) => membership.role == WorkspaceRole.owner)
          .map((membership) => membership.workspaceId)
          .toSet();
      final ownerQueries = await Future.wait([
        for (final workspaceId in ownedWorkspaceIds)
          transaction.getQuery(
            firestore
                .collection('workspaceMemberships')
                .where('workspaceId', WhereFilter.equal, workspaceId)
                .where('role', WhereFilter.equal, WorkspaceRole.owner.value)
                .limit(2),
          ),
      ]);
      final workspaceOwners = ownerQueries
          .expand((query) => query.docs)
          .map((snapshot) => Membership.fromData(snapshot.data()))
          .toList(growable: false);
      requireOrganizationMemberRemovalAllowed(
        actor: actor,
        target: target,
        organizationMembers: members,
        targetWorkspaceMemberships: targetWorkspaces,
        workspaceOwnerMemberships: workspaceOwners,
      );

      for (final snapshot in targetWorkspaceSnapshots.docs) {
        transaction.delete(snapshot.ref);
      }
      transaction.delete(
        firestore
            .collection(OrganizationStore.memberships)
            .doc(membershipId(organizationId, uid)),
      );
      return targetWorkspaceSnapshots.size;
    });
  }
}

void _requireLimit(int count, int limit, String code, String message) {
  if (count > limit) throw ApiError(409, code, message);
}

void _requireAcceptingChanges(
  DocumentSnapshot<Map<String, Object?>> organization,
) {
  if (!organization.exists) {
    throw const ApiError(
      404,
      'organization_not_found',
      'Organization not found.',
    );
  }
  if (organization.data()?['deletionStartedAt'] != null) {
    throw const ApiError(
      409,
      'organization_deletion_in_progress',
      'This organization is being deleted.',
    );
  }
}
