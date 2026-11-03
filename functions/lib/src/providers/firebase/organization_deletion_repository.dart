import 'dart:async';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import '../../api_error.dart';
import '../../organization.dart';
import '../../organization_invitation_store.dart';
import '../../organization_store.dart';

/// Firestore-backed cascading deletion for an organization control plane.
extension OrganizationDeletionRepository on OrganizationStore {
  static const _directoryLimit = 100;
  static const _workspaceGrantLimit = 10000;

  /// Claims deletion before reading the cascade so no invitation acceptance or
  /// access grant can race a new membership into an already-read result set.
  /// The deleting owner's membership is preserved until the final batch, which
  /// keeps an interrupted deletion safely retryable.
  Future<Map<String, Object?>> deleteOrganization({
    required String organizationId,
    required OrganizationMembership actor,
  }) async {
    if (actor.organizationId != organizationId ||
        actor.role != OrganizationRole.owner) {
      throw const ApiError(
        403,
        'organization_owner_required',
        'Only an organization owner can delete this organization.',
      );
    }

    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    final actorRef = firestore
        .collection(OrganizationStore.memberships)
        .doc(membershipId(organizationId, actor.uid));
    await firestore.runTransaction<void>((transaction) async {
      final documents = await Future.wait([
        transaction.get(organizationRef),
        transaction.get(actorRef),
      ]);
      final organization = documents[0];
      final liveActor = documents[1];
      if (!organization.exists) {
        throw const ApiError(
          404,
          'organization_not_found',
          'Organization not found.',
        );
      }
      if (!liveActor.exists ||
          liveActor.data()?['role'] != OrganizationRole.owner.value) {
        throw const ApiError(
          403,
          'organization_owner_required',
          'Only an organization owner can delete this organization.',
        );
      }
      if (organization.data()?['deletionStartedAt'] == null) {
        transaction.update(organizationRef, {
          'deletionStartedAt': Timestamp.now(),
          'deletionStartedBy': actor.uid,
        });
      }
    });

    final results = await Future.wait<Object>([
      firestore
          .collection(OrganizationStore.memberships)
          .where('organizationId', WhereFilter.equal, organizationId)
          .limit(_directoryLimit + 1)
          .get(),
      firestore
          .collection('workspaces')
          .where('organizationId', WhereFilter.equal, organizationId)
          .limit(_directoryLimit + 1)
          .get(),
      firestore
          .collection('workspaceMemberships')
          .where('organizationId', WhereFilter.equal, organizationId)
          .limit(_workspaceGrantLimit + 1)
          .get(),
      firestore
          .collection(OrganizationInvitationStore.collection)
          .where('organizationId', WhereFilter.equal, organizationId)
          .where('acceptedAt', WhereFilter.equal, null)
          .where('revokedAt', WhereFilter.equal, null)
          .orderBy('createdAt', descending: true)
          .limit(OrganizationInvitationStore.maxOutstanding + 1)
          .get(),
    ]);
    final organizationMembers =
        results[0] as QuerySnapshot<Map<String, Object?>>;
    final workspaces = results[1] as QuerySnapshot<Map<String, Object?>>;
    final workspaceMembers = results[2] as QuerySnapshot<Map<String, Object?>>;
    final invitations = results[3] as QuerySnapshot<Map<String, Object?>>;
    _requireLimit(
      organizationMembers.size,
      _directoryLimit,
      'organization_member_limit_exceeded',
      'This organization has too many people to delete safely.',
    );
    _requireLimit(
      workspaces.size,
      _directoryLimit,
      'organization_workspace_limit_exceeded',
      'This organization has too many workspaces to delete safely.',
    );
    _requireLimit(
      workspaceMembers.size,
      _workspaceGrantLimit,
      'organization_workspace_grant_limit_exceeded',
      'This organization has too many workspace assignments to delete safely.',
    );
    _requireLimit(
      invitations.size,
      OrganizationInvitationStore.maxOutstanding,
      'organization_invitation_limit_exceeded',
      'This organization has too many pending invitations to delete safely.',
    );

    final writer = firestore.bulkWriter();
    final revokedAt = Timestamp.now();
    for (final member in organizationMembers.docs) {
      if (member.data()['uid'] != actor.uid) {
        unawaited(writer.delete(member.ref));
      }
    }
    for (final member in workspaceMembers.docs) {
      if (member.data()['uid'] != actor.uid) {
        unawaited(writer.delete(member.ref));
      }
    }
    for (final invitation in invitations.docs) {
      unawaited(
        writer.update(invitation.ref, {
          FieldPath(const ['revokedAt']): revokedAt,
          FieldPath(const ['revokedByOrganizationDeletion']): true,
        }),
      );
    }
    await writer.close();

    final finalBatch = firestore.batch();
    finalBatch.delete(organizationRef);
    for (final workspace in workspaces.docs) {
      finalBatch.delete(workspace.ref);
    }
    for (final member in organizationMembers.docs) {
      if (member.data()['uid'] == actor.uid) finalBatch.delete(member.ref);
    }
    for (final member in workspaceMembers.docs) {
      if (member.data()['uid'] == actor.uid) finalBatch.delete(member.ref);
    }
    await finalBatch.commit();

    return {
      'organizationId': organizationId,
      'membersRemoved': organizationMembers.size,
      'workspacesRemoved': workspaces.size,
      'workspaceAssignmentsRemoved': workspaceMembers.size,
      'invitationsRevoked': invitations.size,
    };
  }
}

void _requireLimit(int count, int limit, String code, String message) {
  if (count > limit) throw ApiError(409, code, message);
}
