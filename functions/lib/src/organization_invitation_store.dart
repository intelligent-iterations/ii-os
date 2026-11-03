import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'auth_service.dart';
import 'organization.dart';
import 'organization_invitation_json.dart';
import 'organization_invitation_rate_limiter.dart';
import 'organization_store.dart';
import 'transactional_mail.dart';

/// Invitations into the tenant, and the mail that tells people about them.
///
/// Joining a tenant and being given a project are different actions and do not
/// share a flow. An invitation is addressed to someone who is not here yet, so
/// it has to be accepted; a workspace grant is given to someone already inside
/// the tenant, so it takes effect without ceremony.
final class OrganizationInvitationStore {
  OrganizationInvitationStore({
    required this.firestore,
    required this.mailer,
    required this.webOrigin,
    required this.rateLimiter,
    this.deliveryFailureReporter,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  static const collection = 'organizationInvites';

  /// How long an invitation stays usable.
  static const lifetime = Duration(days: 7);

  /// The soonest the same address may be invited again.
  ///
  /// Sending mail on an unbounded create path is how a product becomes an open
  /// relay against its own sending reputation, so the limits ship with the
  /// email rather than after it.
  static const resendCooldown =
      OrganizationInvitationRateLimiter.resendCooldown;

  /// How many invitations one organization may have outstanding at once.
  static const maxOutstanding = 100;

  /// A single invitation may grant a small, explicit set of projects.
  static const maxWorkspaceGrants = 20;

  /// Bounds the historical rows examined while enforcing [maxOutstanding].
  static const invitationScanLimit = 500;

  /// Bounds the invitation chooser shown to one signed-in address.
  static const availableInvitationLimit = 100;

  /// Bounds the explicit organization-admin invitation list.
  static const organizationInvitationLimit = 100;

  final Firestore firestore;
  final TransactionalMailer mailer;
  final String webOrigin;
  final OrganizationInvitationRateLimiter rateLimiter;
  final Future<void> Function(
    Object error,
    StackTrace stackTrace,
    String requestId,
    String actorUid,
  )?
  deliveryFailureReporter;
  final DateTime Function() _clock;
  final Uuid _uuid = const Uuid();

  /// Invites [email] into [organizationId] and tells them.
  ///
  /// The claims are bounded by the inviter's own, so an invitation cannot be
  /// used to conjure access the person sending it does not have.
  Future<Map<String, Object?>> invite({
    required String organizationId,
    required String organizationName,
    required String email,
    required OrganizationRole role,
    required Set<String> featureClaims,
    required List<String> workspaceGrants,
    required OrganizationMembership actor,
    required String clientIp,
    String requestId = '',
  }) async {
    final address = email.trim().toLowerCase();
    if (!emailPattern.hasMatch(address)) {
      throw const ApiError(
        400,
        'invalid_email',
        'Enter a valid email address.',
      );
    }
    if (role == OrganizationRole.owner) {
      throw const ApiError(
        400,
        'owner_invite_not_allowed',
        'Invite the person as a member, then an owner can transfer ownership.',
      );
    }
    final now = _clock();
    final validatedWorkspaceGrants = await _validateWorkspaceGrants(
      organizationId,
      workspaceGrants,
    );

    final existingMember = await firestore
        .collection(OrganizationStore.memberships)
        .where('organizationId', WhereFilter.equal, organizationId)
        .where('email', WhereFilter.equal, address)
        .limit(1)
        .get();
    if (!existingMember.empty) {
      throw const ApiError(
        409,
        'member_already_exists',
        'This email already belongs to the organization.',
      );
    }

    final outstanding = await firestore
        .collection(collection)
        .where('organizationId', WhereFilter.equal, organizationId)
        .limit(invitationScanLimit + 1)
        .get();
    if (outstanding.docs.length > invitationScanLimit) {
      throw const ApiError(
        429,
        'too_many_invitations',
        'This organization has too much invitation history to safely scan. '
            'Revoke or archive old invitations before sending more.',
      );
    }
    final live = outstanding.docs.where((doc) => _isLive(doc.data(), now));
    DocumentReference<Map<String, Object?>>? pendingRef;
    Map<String, Object?>? pendingData;
    for (final doc in live) {
      final data = doc.data();
      if ((data['email'] as String? ?? '') != address) continue;
      final sentAt = data['lastSentAt'];
      if (sentAt is Timestamp &&
          now.difference(sentAt.toDate().toUtc()) < resendCooldown) {
        throw const ApiError(
          429,
          'invite_cooldown',
          'That address was invited moments ago. Try again shortly.',
        );
      }
      pendingRef = doc.ref;
      pendingData = data;
      break;
    }
    if (pendingRef == null && live.length >= maxOutstanding) {
      throw const ApiError(
        429,
        'too_many_invitations',
        'This organization has too many invitations outstanding. Revoke some '
            'before sending more.',
      );
    }

    final claims = boundedOrganizationClaims(
      actor: actor,
      targetRole: role,
      requested: featureClaims,
    );
    await rateLimiter.consume(
      email: address,
      clientIp: clientIp,
      organizationId: organizationId,
      actorUid: actor.uid,
    );
    final invitationRef =
        pendingRef ?? firestore.collection(collection).doc(_uuid.v4());
    final id = invitationRef.id;
    final effectiveWorkspaceGrants = {
      ..._normalizedWorkspaceGrantIds(pendingData?['workspaceGrants']),
      ...validatedWorkspaceGrants,
    }.toList(growable: false);
    if (effectiveWorkspaceGrants.length > maxWorkspaceGrants) {
      throw const ApiError(
        400,
        'too_many_workspace_grants',
        'An invitation can grant at most 20 workspaces.',
      );
    }
    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    if (pendingRef == null) {
      await firestore.runTransaction<void>((transaction) async {
        final organization = await transaction.get(organizationRef);
        if (!organization.exists ||
            organization.data()?['deletionStartedAt'] != null) {
          throw const ApiError(
            410,
            'organization_deleted',
            'This organization no longer accepts invitations.',
          );
        }
        transaction.set(invitationRef, {
          'organizationId': organizationId,
          'email': address,
          'role': role.value,
          'featureClaims': claims,
          'workspaceGrants': effectiveWorkspaceGrants,
          'createdBy': actor.uid,
          'createdByEmail': actor.email,
          'createdAt': Timestamp.fromDate(now),
          'lastSentAt': Timestamp.fromDate(now),
          'expiresAt': Timestamp.fromDate(now.add(lifetime)),
          'acceptedAt': null,
          'revokedAt': null,
        });
      });
    } else {
      await invitationRef.update({
        FieldPath(const ['role']): role.value,
        FieldPath(const ['featureClaims']): claims,
        FieldPath(const ['workspaceGrants']): effectiveWorkspaceGrants,
        FieldPath(const ['lastSentAt']): Timestamp.fromDate(now),
        FieldPath(const ['expiresAt']): Timestamp.fromDate(now.add(lifetime)),
        FieldPath(const ['delivered']): null,
        FieldPath(const ['deliveryError']): null,
      });
    }

    // Delivery failure does not undo the invitation. The person can still
    // accept it from inside ii-os exactly as they could before mail existed,
    // and the admin can see that the message did not land, revoke it, and try
    // again after the send cooldown.
    var delivered = true;
    String? deliveryError;
    try {
      await mailer.send(
        to: address,
        message: OrganizationInviteEmail(
          organizationName: organizationName,
          inviterEmail: actor.email,
          acceptUrl:
              '${webOrigin.replaceAll(RegExp(r"/$"), "")}'
              '/invitations/$id',
          expiresInDays: lifetime.inDays,
        ),
      );
    } on Object catch (error, stackTrace) {
      delivered = false;
      deliveryError = 'The invitation email could not be sent.';
      final reporter = deliveryFailureReporter;
      if (reporter != null) {
        try {
          await reporter(error, stackTrace, requestId, actor.uid);
        } on Object {
          // Observability never changes the invitation result.
        }
      }
    }
    await invitationRef.update({
      FieldPath(const ['delivered']): delivered,
      FieldPath(const ['deliveryError']): deliveryError,
    });

    return {
      'id': id,
      'email': address,
      'role': role.value,
      'featureClaims': claims,
      'workspaceGrants': effectiveWorkspaceGrants,
      'delivered': delivered,
      'deliveryError': ?deliveryError,
      'expiresInDays': lifetime.inDays,
    };
  }

  /// Accepts an invitation for [actor].
  ///
  /// The link is not the credential. Acceptance requires a verified address
  /// that exactly matches the invitation, so forwarding the mail hands the
  /// recipient nothing.
  Future<OrganizationMembership> accept(
    String invitationId,
    AuthenticatedUser actor,
  ) async {
    final ref = firestore.collection(collection).doc(invitationId);
    return firestore.runTransaction<OrganizationMembership>((
      transaction,
    ) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw const ApiError(404, 'invite_not_found', 'Invitation not found.');
      }
      if (!actor.emailVerified) {
        throw const ApiError(
          403,
          'invite_email_unverified',
          'Verify your email address before accepting an invitation.',
        );
      }
      final invited = (data['email'] as String? ?? '').toLowerCase();
      if (actor.email.isEmpty || actor.email != invited) {
        throw ApiError(
          403,
          'invite_email_mismatch',
          'This invitation belongs to a different email address. Sign in with '
              'the account that was invited.',
          details: {'signedInEmail': actor.email},
        );
      }
      final now = _clock();
      if (data['revokedAt'] != null) {
        throw const ApiError(410, 'invite_revoked', 'Invitation was revoked.');
      }
      if (data['acceptedAt'] != null) {
        throw const ApiError(
          409,
          'invite_used',
          'Invitation has already been used.',
        );
      }
      final expiresAt = data['expiresAt'];
      if (expiresAt is! Timestamp || expiresAt.toDate().toUtc().isBefore(now)) {
        throw const ApiError(410, 'invite_expired', 'Invitation has expired.');
      }

      final organizationId = data['organizationId'] as String? ?? '';
      final organizationRef = firestore
          .collection(OrganizationStore.organizations)
          .doc(organizationId);
      final organization = await transaction.get(organizationRef);
      if (!organization.exists ||
          organization.data()?['deletionStartedAt'] != null) {
        throw const ApiError(
          410,
          'organization_deleted',
          'This organization no longer exists.',
        );
      }
      final role = OrganizationRole.parse(data['role']);
      final claims =
          (data['featureClaims'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          <String>[];
      final membershipRef = firestore
          .collection(OrganizationStore.memberships)
          .doc('${organizationId}_${actor.uid}');
      if ((await transaction.get(membershipRef)).exists) {
        throw const ApiError(
          409,
          'member_already_exists',
          'This account already belongs to the organization.',
        );
      }
      final workspaceGrantIds = _normalizedWorkspaceGrantIds(
        data['workspaceGrants'],
      );
      if (workspaceGrantIds.length > maxWorkspaceGrants) {
        throw const ApiError(
          400,
          'too_many_workspace_grants',
          'An invitation can grant at most 20 workspaces.',
        );
      }
      final workspaceRefs = [
        for (final workspaceId in workspaceGrantIds)
          firestore.collection('workspaces').doc(workspaceId),
      ];
      for (final workspaceRef in workspaceRefs) {
        final workspace = await transaction.get(workspaceRef);
        if (!workspace.exists ||
            workspace.data()?['organizationId'] != organizationId) {
          throw const ApiError(
            400,
            'workspace_grant_outside_organization',
            'Every workspace grant must belong to the invited organization.',
          );
        }
      }
      final stamp = Timestamp.fromDate(now);
      transaction.set(membershipRef, {
        'organizationId': organizationId,
        'uid': actor.uid,
        'email': actor.email,
        'role': role.value,
        'featureClaims': claims,
        'createdAt': stamp,
        'updatedAt': stamp,
      });
      // Workspace grants ride along so one acceptance puts the person in the
      // projects they were brought on for, rather than leaving an admin to
      // grant each one after the fact.
      for (final workspaceId in workspaceGrantIds) {
        transaction.set(
          firestore
              .collection('workspaceMemberships')
              .doc('${workspaceId}_${actor.uid}'),
          {
            'workspaceId': workspaceId,
            'organizationId': organizationId,
            'uid': actor.uid,
            'email': actor.email,
            'role': 'view_only',
            'featureClaims': <String>['workspace.read'],
            'status': 'active',
            'createdAt': stamp,
            'updatedAt': stamp,
          },
        );
      }
      transaction.update(ref, {
        FieldPath(const ['acceptedAt']): stamp,
        FieldPath(const ['acceptedBy']): actor.uid,
      });
      return OrganizationMembership(
        organizationId: organizationId,
        uid: actor.uid,
        email: actor.email,
        role: role,
        featureClaims: claims.toSet(),
      );
    });
  }

  /// Withdraws an invitation without erasing that it happened.
  Future<void> revoke({
    required String organizationId,
    required String invitationId,
  }) async {
    final ref = firestore.collection(collection).doc(invitationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['organizationId'] != organizationId) {
      throw const ApiError(404, 'invite_not_found', 'Invitation not found.');
    }
    if (data['acceptedAt'] != null) {
      throw const ApiError(
        409,
        'invite_used',
        'An accepted invitation cannot be revoked.',
      );
    }
    // Soft: a deleted row cannot answer "who invited this person, and who
    // changed their mind".
    await ref.update({
      FieldPath(const ['revokedAt']): Timestamp.fromDate(_clock()),
    });
  }

  /// Pending invitations visible to an organization administrator.
  Future<List<Map<String, Object?>>> listForOrganization(
    String organizationId,
  ) async {
    final snapshots = await firestore
        .collection(collection)
        .where('organizationId', WhereFilter.equal, organizationId)
        .where('acceptedAt', WhereFilter.equal, null)
        .where('revokedAt', WhereFilter.equal, null)
        .orderBy('createdAt', descending: true)
        .limit(organizationInvitationLimit + 1)
        .get();
    if (snapshots.size > organizationInvitationLimit) {
      throw const ApiError(
        409,
        'organization_invitation_limit_exceeded',
        'This organization has too many pending invitations to show at once.',
      );
    }
    final now = _clock();
    return snapshots.docs.where((item) => _isLive(item.data(), now)).map((
      item,
    ) {
      final data = item.data();
      return organizationInvitationAdminJson(
        item.ref.id,
        data,
        createdAt: _timestampIso(data['createdAt']),
        expiresAt: _timestampIso(data['expiresAt']),
      );
    }).toList();
  }

  /// Notifies an existing organization member about a first-time project
  /// grant. The grant remains effective if the provider is unavailable.
  Future<bool> notifyWorkspaceAccess({
    required String email,
    required String organizationName,
    required String workspaceId,
    required String workspaceName,
  }) async {
    if (!emailPattern.hasMatch(email)) return false;
    final base = Uri.parse(webOrigin);
    final workspaceUrl = base
        .replace(
          pathSegments: ['workspaces', workspaceId, 'home'],
          queryParameters: null,
          fragment: null,
        )
        .toString();
    try {
      await mailer.send(
        to: email,
        message: WorkspaceAccessEmail(
          workspaceName: workspaceName,
          organizationName: organizationName,
          workspaceUrl: workspaceUrl,
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  /// Invitations addressed to [actor], for the acceptance surface.
  Future<List<Map<String, Object?>>> availableTo(
    AuthenticatedUser actor,
  ) async {
    if (!actor.emailVerified || actor.email.isEmpty) {
      return <Map<String, Object?>>[];
    }
    final snapshots = await firestore
        .collection(collection)
        .where('email', WhereFilter.equal, actor.email)
        .limit(availableInvitationLimit)
        .get();
    final now = _clock();
    return snapshots.docs
        .where((doc) => _isLive(doc.data(), now))
        .map(
          (doc) => {
            'id': doc.ref.id,
            'organizationId': doc.data()['organizationId'],
            'role': doc.data()['role'],
            'invitedBy': doc.data()['createdByEmail'],
          },
        )
        .toList();
  }

  bool _isLive(Map<String, Object?> data, DateTime now) {
    if (data['acceptedAt'] != null || data['revokedAt'] != null) return false;
    final expiresAt = data['expiresAt'];
    return expiresAt is Timestamp && expiresAt.toDate().toUtc().isAfter(now);
  }

  Future<List<String>> _validateWorkspaceGrants(
    String organizationId,
    List<String> requested,
  ) async {
    final workspaceIds = _normalizedWorkspaceGrantIds(requested);
    if (workspaceIds.length > maxWorkspaceGrants) {
      throw const ApiError(
        400,
        'too_many_workspace_grants',
        'An invitation can grant at most 20 workspaces.',
      );
    }
    if (workspaceIds.isEmpty) return const <String>[];
    final snapshots = await firestore.getAll([
      for (final workspaceId in workspaceIds)
        firestore.collection('workspaces').doc(workspaceId),
    ]);
    if (snapshots.length != workspaceIds.length ||
        snapshots.any(
          (workspace) =>
              !workspace.exists ||
              workspace.data()?['organizationId'] != organizationId,
        )) {
      throw const ApiError(
        400,
        'workspace_grant_outside_organization',
        'Every workspace grant must belong to the invited organization.',
      );
    }
    return workspaceIds;
  }

  List<String> _normalizedWorkspaceGrantIds(Object? raw) {
    final values = raw is List<Object?>
        ? raw.whereType<String>()
        : raw is List<String>
        ? raw
        : const <String>[];
    return {
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    }.toList(growable: false);
  }
}

String? _timestampIso(Object? value) =>
    value is Timestamp ? value.toDate().toUtc().toIso8601String() : null;
