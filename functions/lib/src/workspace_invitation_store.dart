part of 'workspace_store.dart';

extension WorkspaceInvitationStore on WorkspaceStore {
  Future<List<Map<String, Object?>>> listInvites(String workspaceId) async {
    final snapshots = await firestore
        .collection('workspaceInvites')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .get();
    final invites = snapshots.docs
        .where((snapshot) => snapshot.data()['acceptedAt'] == null)
        .map((snapshot) => _inviteJson(snapshot.id, snapshot.data()))
        .toList();
    invites.sort((left, right) {
      return (right['createdAt'] as String).compareTo(
        left['createdAt'] as String,
      );
    });
    return invites;
  }

  Future<List<Map<String, Object?>>> listAvailableInvites(
    AuthenticatedUser actor,
  ) async {
    if (!actor.emailVerified) {
      throw const ApiError(
        403,
        'invite_email_unverified',
        'Verify your email address before viewing invitations.',
      );
    }
    if (actor.email.isEmpty) return <Map<String, Object?>>[];
    final snapshots = await firestore
        .collection('workspaceInvites')
        .where('email', WhereFilter.equal, actor.email)
        .get();
    final active = snapshots.docs.where((snapshot) {
      final data = snapshot.data();
      final expiresAt = data['expiresAt'];
      return data['acceptedAt'] == null &&
          expiresAt is Timestamp &&
          expiresAt.toDate().toUtc().isAfter(DateTime.now().toUtc());
    }).toList();
    if (active.isEmpty) return <Map<String, Object?>>[];

    final workspaceIds = active
        .map((snapshot) => snapshot.data()['workspaceId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final workspaces = await firestore.getAll(
      workspaceIds
          .map((id) => firestore.collection('workspaces').doc(id))
          .toList(),
    );
    final workspaceById = {
      for (final workspace in workspaces)
        if (workspace.exists && workspace.data() != null)
          workspace.ref.id: Workspace.fromData(
            workspace.ref.id,
            workspace.data()!,
            emulated: emulated,
          ),
    };
    final invitations = active
        .map((snapshot) {
          final invitation = _inviteJson(snapshot.id, snapshot.data());
          final workspace = workspaceById[invitation['workspaceId']];
          if (workspace == null) return null;
          return <String, Object?>{
            ...invitation,
            'workspaceName': workspace.name,
            'workspaceEnvironment': workspace.environment,
          };
        })
        .whereType<Map<String, Object?>>()
        .toList();
    invitations.sort(
      (left, right) =>
          (right['createdAt'] as String).compareTo(left['createdAt'] as String),
    );
    return invitations;
  }

  Future<Map<String, Object?>> createInvite({
    required String workspaceId,
    required String email,
    required WorkspaceRole role,
    required Set<String> featureClaims,
    required Membership actor,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (role == WorkspaceRole.owner) {
      throw const ApiError(
        400,
        'owner_invite_not_allowed',
        'Invite the person as a member, then an owner can transfer ownership.',
      );
    }
    final memberships = await firestore
        .collection('workspaceMemberships')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .get();
    if (memberships.docs.any((snapshot) {
      return (snapshot.data()['email'] as String? ?? '').toLowerCase() ==
          normalizedEmail;
    })) {
      throw const ApiError(
        409,
        'member_already_exists',
        'This email already belongs to a workspace member.',
      );
    }
    final existingInvites = await firestore
        .collection('workspaceInvites')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .get();
    final now = DateTime.now().toUtc();
    final hasActiveInvite = existingInvites.docs.any((snapshot) {
      final data = snapshot.data();
      final expiresAt = data['expiresAt'];
      return data['acceptedAt'] == null &&
          (data['email'] as String? ?? '').toLowerCase() == normalizedEmail &&
          expiresAt is Timestamp &&
          expiresAt.toDate().toUtc().isAfter(now);
    });
    if (hasActiveInvite) {
      throw const ApiError(
        409,
        'invite_already_pending',
        'This email already has a pending invitation.',
      );
    }

    final id = _uuid.v4();
    final claims = boundedFeatureClaims(
      actor: actor,
      targetRole: role,
      requested: featureClaims,
    );
    await firestore.collection('workspaceInvites').doc(id).set({
      'workspaceId': workspaceId,
      'email': normalizedEmail,
      'role': role.value,
      'featureClaims': claims,
      'createdBy': actor.uid,
      'createdAt': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
      'acceptedAt': null,
    });
    return {
      'id': id,
      'email': normalizedEmail,
      'role': role.value,
      'featureClaims': claims,
      'expiresInHours': 168,
    };
  }

  Future<Map<String, Object?>> revokeInvite({
    required String workspaceId,
    required String inviteId,
  }) async {
    final ref = firestore.collection('workspaceInvites').doc(inviteId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId) {
      throw const ApiError(404, 'invite_not_found', 'Invitation not found.');
    }
    if (data['acceptedAt'] != null) {
      throw const ApiError(
        409,
        'invite_used',
        'An accepted invitation cannot be revoked.',
      );
    }
    final result = _inviteJson(snapshot.id, data);
    await ref.delete();
    return result;
  }

  Future<Membership> acceptInviteById(
    String invitationId,
    AuthenticatedUser actor,
  ) {
    if (!isValidInvitationId(invitationId)) {
      throw const ApiError(
        400,
        'invalid_invite_id',
        'Invitation ID is invalid.',
      );
    }
    return _acceptInvite(invitationId: invitationId, actor: actor);
  }

  Future<Membership> _acceptInvite({
    required String invitationId,
    required AuthenticatedUser actor,
  }) async {
    final inviteRef = firestore
        .collection('workspaceInvites')
        .doc(invitationId);
    return firestore.runTransaction<Membership>((transaction) async {
      final snapshot = await transaction.get(inviteRef);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw const ApiError(404, 'invite_not_found', 'Invitation not found.');
      }
      final workspaceId = data['workspaceId'] as String? ?? '';
      final membershipRef = firestore
          .collection('workspaceMemberships')
          .doc(_membershipId(workspaceId, actor.uid));
      final existingMembership = await transaction.get(membershipRef);
      final invitedEmail = (data['email'] as String? ?? '').toLowerCase();
      if (!actor.emailVerified) {
        throw const ApiError(
          403,
          'invite_email_unverified',
          'Verify your email address before accepting an invitation.',
        );
      }
      if (actor.email.isEmpty || actor.email != invitedEmail) {
        throw invitationEmailMismatch(signedInEmail: actor.email);
      }
      if (data['acceptedAt'] != null) {
        final existingData = existingMembership.data();
        if (existingMembership.exists && existingData != null) {
          return Membership.fromData(existingData);
        }
        throw const ApiError(
          409,
          'invite_used',
          'Invitation has already been used.',
        );
      }
      final role = WorkspaceRole.parse(data['role']);
      if (role == WorkspaceRole.owner) {
        throw const ApiError(
          400,
          'owner_invite_not_allowed',
          'Invite the person as a member, then an owner can transfer ownership.',
        );
      }
      final expiresAt = data['expiresAt'];
      if (expiresAt is! Timestamp ||
          expiresAt.toDate().isBefore(DateTime.now())) {
        throw const ApiError(410, 'invite_expired', 'Invitation has expired.');
      }
      if (existingMembership.exists) {
        throw const ApiError(
          409,
          'member_already_exists',
          'This account already belongs to the workspace.',
        );
      }
      final workspaceRef = firestore.collection('workspaces').doc(workspaceId);
      final workspace = await transaction.get(workspaceRef);
      if (!workspace.exists) {
        throw const ApiError(
          404,
          'workspace_not_found',
          'Workspace not found.',
        );
      }

      final membership = Membership(
        workspaceId: workspaceId,
        uid: actor.uid,
        email: actor.email,
        role: role,
        featureClaims:
            (data['featureClaims'] as List<Object?>?)
                ?.whereType<String>()
                .toSet() ??
            <String>{},
      );
      final now = Timestamp.now();
      transaction.set(membershipRef, {
        'workspaceId': workspaceId,
        'uid': actor.uid,
        'email': actor.email,
        'role': membership.role.value,
        'featureClaims': membership.featureClaims.toList(),
        'createdAt': now,
        'updatedAt': now,
      });
      transaction.update(inviteRef, {
        FieldPath(const ['acceptedAt']): now,
        FieldPath(const ['acceptedBy']): actor.uid,
      });
      return membership;
    });
  }
}

Map<String, Object?> _inviteJson(String inviteId, Map<String, Object?> data) {
  final createdAt = data['createdAt'];
  final expiresAt = data['expiresAt'];
  final acceptedAt = data['acceptedAt'];
  final expired =
      expiresAt is! Timestamp ||
      expiresAt.toDate().toUtc().isBefore(DateTime.now().toUtc());
  final role = WorkspaceRole.parse(data['role']);
  return {
    'id': inviteId,
    'workspaceId': data['workspaceId'] as String? ?? '',
    'email': data['email'] as String? ?? '',
    'role': role.value,
    'roleLabel': role.label,
    'featureClaims':
        (data['featureClaims'] as List<Object?>?)
            ?.whereType<String>()
            .toList() ??
        <String>[],
    'status': acceptedAt != null
        ? 'accepted'
        : (expired ? 'expired' : 'pending'),
    'createdAt': createdAt is Timestamp
        ? createdAt.toDate().toUtc().toIso8601String()
        : '',
    'expiresAt': expiresAt is Timestamp
        ? expiresAt.toDate().toUtc().toIso8601String()
        : '',
    if (acceptedAt is Timestamp)
      'acceptedAt': acceptedAt.toDate().toUtc().toIso8601String(),
  };
}
