part of 'workspace_store.dart';

const workspaceMemberMutationLimit = 100;

extension WorkspaceMemberStore on WorkspaceStore {
  Future<List<Map<String, Object?>>> listMembers(String workspaceId) async {
    final snapshots = await firestore
        .collection('workspaceMemberships')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .get();
    return snapshots.docs
        .map((snapshot) => Membership.fromData(snapshot.data()).toJson())
        .toList();
  }

  Future<Membership> updateMember({
    required String workspaceId,
    required String actorUid,
    required String uid,
    required WorkspaceRole role,
    required Set<String> featureClaims,
  }) async {
    final targetRef = firestore
        .collection('workspaceMemberships')
        .doc(_membershipId(workspaceId, uid));
    final membersQuery = firestore
        .collection('workspaceMemberships')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .limit(workspaceMemberMutationLimit + 1);

    return firestore.runTransaction<Membership>((transaction) async {
      final snapshots = await transaction.getQuery(membersQuery);
      if (snapshots.size > workspaceMemberMutationLimit) {
        throw const ApiError(
          409,
          'workspace_member_limit_exceeded',
          'This workspace has too many people to edit safely.',
        );
      }
      final members = <String, Membership>{};
      for (final snapshot in snapshots.docs) {
        final data = snapshot.data();
        final member = Membership.fromData(data);
        if (member.workspaceId == workspaceId) {
          members[member.uid] = member;
        }
      }

      final actor = members[actorUid];
      if (actor == null || !actor.allows(Capability.membersManage)) {
        throw const ApiError(
          403,
          'forbidden',
          'Your workspace role does not allow this action.',
        );
      }
      final target = members[uid];
      if (target == null) {
        throw const ApiError(
          404,
          'member_not_found',
          'Workspace member not found.',
        );
      }

      final changesOwner =
          target.role == WorkspaceRole.owner || role == WorkspaceRole.owner;
      if (changesOwner && actor.role != WorkspaceRole.owner) {
        throw const ApiError(
          403,
          'workspace_owner_required',
          'Only a workspace owner can assign or remove the Owner role.',
        );
      }
      if (target.role == WorkspaceRole.owner &&
          role != WorkspaceRole.owner &&
          !members.values.any(
            (member) => member.uid != uid && member.role == WorkspaceRole.owner,
          )) {
        throw const ApiError(
          409,
          'last_workspace_owner',
          'Promote another member to Owner before changing the last owner.',
        );
      }

      final boundedClaims = boundedFeatureClaims(
        actor: actor,
        targetRole: role,
        requested: featureClaims,
      );

      transaction.update(targetRef, {
        'role': role.value,
        'featureClaims': boundedClaims,
        'updatedAt': Timestamp.now(),
      });
      return Membership(
        workspaceId: workspaceId,
        uid: target.uid,
        email: target.email,
        role: role,
        featureClaims: boundedClaims.toSet(),
        suspended: target.suspended,
      );
    });
  }

  Future<void> leaveWorkspace({
    required String workspaceId,
    required AuthenticatedUser actor,
  }) async {
    final membership = await getMembership(workspaceId, actor.uid);
    if (membership == null) {
      throw const ApiError(
        404,
        'member_not_found',
        'Workspace member not found.',
      );
    }
    if (membership.role == WorkspaceRole.owner) {
      throw const ApiError(
        409,
        'owner_cannot_leave',
        'Delete the workspace or transfer ownership before leaving.',
      );
    }
    await firestore
        .collection('workspaceMemberships')
        .doc(_membershipId(workspaceId, actor.uid))
        .delete();
  }
}
