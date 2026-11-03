import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'auth_service.dart';
import 'data_plane_connection.dart';
import 'organization.dart';
import 'organization_resource_store.dart';
import 'organization_resources.dart';

/// Owns tenant membership, shared connection identifiers, and project access.
final class OrganizationStore {
  OrganizationStore(this.firestore, {this.emulated = false});

  final Firestore firestore;
  final bool emulated;
  final Uuid _uuid = const Uuid();

  static const organizations = 'organizations';
  static const memberships = 'organizationMemberships';
  static const sessionOrganizationLimit = 100;
  static const maxOrganizationRepositories = 500;

  String membershipId(String organizationId, String uid) =>
      '${organizationId}_$uid';

  /// Starts a tenant directory. Projects are created separately inside it so
  /// an empty organization remains a valid, recoverable state if the second
  /// request is interrupted.
  Future<OrganizationMembership> createOrganization({
    required String name,
    required AuthenticatedUser actor,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw const ApiError(
        400,
        'invalid_name',
        'An organization name is required.',
      );
    }
    final id = _uuid.v4();
    final now = Timestamp.now();
    final membership = OrganizationMembership(
      organizationId: id,
      uid: actor.uid,
      email: actor.email,
      role: OrganizationRole.owner,
      featureClaims: const {},
    );
    final batch = firestore.batch();
    batch.set(firestore.collection(organizations).doc(id), {
      'name': trimmed,
      'createdAt': now,
      'createdBy': actor.uid,
      'repositories': <String>[],
      'githubInstallationId': null,
      'connection': null,
      ...const OrganizationResourceCatalog.empty().toJson(),
      'updatedAt': now,
    });
    batch.set(
      firestore.collection(memberships).doc(membershipId(id, actor.uid)),
      {
        'organizationId': id,
        'uid': actor.uid,
        'email': actor.email,
        'role': OrganizationRole.owner.value,
        'featureClaims': <String>[],
        'createdAt': now,
        'updatedAt': now,
      },
    );
    await batch.commit();
    return membership;
  }

  Future<Organization> getOrganization(String organizationId) async {
    final snapshot = await firestore
        .collection(organizations)
        .doc(organizationId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const ApiError(
        404,
        'organization_not_found',
        'Organization not found.',
      );
    }
    return Organization.fromData(organizationId, data, emulated: emulated);
  }

  Future<OrganizationMembership?> getMembership(
    String organizationId,
    String uid,
  ) async {
    final snapshot = await firestore
        .collection(memberships)
        .doc(membershipId(organizationId, uid))
        .get();
    final data = snapshot.data();
    return snapshot.exists && data != null
        ? OrganizationMembership.fromData(data)
        : null;
  }

  /// The organizations [actor] belongs to.
  ///
  /// Membership is resolved from the database, never from anything the browser
  /// sent. A system Owner appears here only where it is genuinely a member, so
  /// the flag cannot make an unjoined tenant visible.
  Future<List<Map<String, Object?>>> listOrganizationAccess(
    AuthenticatedUser actor,
  ) async {
    final snapshots = await firestore
        .collection(memberships)
        .where('uid', WhereFilter.equal, actor.uid)
        .limit(sessionOrganizationLimit)
        .get();
    if (snapshots.empty) return <Map<String, Object?>>[];
    final records = snapshots.docs
        .map((snapshot) => OrganizationMembership.fromData(snapshot.data()))
        .where((membership) => membership.organizationId.isNotEmpty)
        .toList();
    final documents = await firestore.getAll([
      for (final membership in records)
        firestore.collection(organizations).doc(membership.organizationId),
    ]);
    final byId = {
      for (final document in documents)
        if (document.exists && document.data() != null)
          document.ref.id: document.data()!,
    };
    return records
        .map((membership) {
          return {
            'organization': switch (byId[membership.organizationId]) {
              final data? => {
                ...Organization.fromData(
                  membership.organizationId,
                  data,
                  emulated: emulated,
                ).toJson(),
                'connection': _connectionFromData(
                  membership.organizationId,
                  data,
                )?.toJson(),
              },
              null => null,
            },
            'membership': membership.toJson(),
          };
        })
        .where((item) => item['organization'] != null)
        .toList();
  }

  /// The tenant's data-plane connection, or null when it has none yet.
  ///
  /// Returns null rather than throwing: an organization that has not been
  /// connected yet is an ordinary state, and the workspace's own record still
  /// answers.
  Future<DataPlaneConnection?> getConnection(
    String organizationId, {
    bool? emulated,
  }) async {
    final snapshot = await firestore
        .collection(organizations)
        .doc(organizationId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return _connectionFromData(
      organizationId,
      data,
      emulatedOverride: emulated,
    );
  }

  DataPlaneConnection? _connectionFromData(
    String organizationId,
    Map<String, Object?> data, {
    bool? emulatedOverride,
  }) {
    final raw = data['connection'];
    if (raw is! Map) return null;
    try {
      final connection = DataPlaneConnection.fromJson(
        raw.cast<String, Object?>(),
        emulated: emulatedOverride ?? emulated,
      );
      // A connection naming a different tenant is not this tenant's, however
      // it came to be stored here.
      if (!connection.isOrganizationBound ||
          connection.organizationId != organizationId) {
        return null;
      }
      return connection.configurationChecks().every((check) => check.passed)
          ? connection
          : null;
    } on FormatException {
      return null;
    }
  }

  /// Persists only a connection bound to this tenant. No workspace API can call
  /// this with a substitute binding and no workspace document is updated.
  Future<void> saveConnection(
    String organizationId,
    DataPlaneConnection connection,
  ) async {
    if (!connection.isOrganizationBound ||
        connection.organizationId != organizationId) {
      throw const ApiError(
        400,
        'organization_connection_mismatch',
        'The connection is bound to a different ii-os organization.',
      );
    }
    await OrganizationResourceStore(
      firestore,
      emulated: emulated,
    ).savePrimaryConnection(
      organizationId: organizationId,
      connection: connection,
    );
  }

  /// Resolves the tenant's shared GitHub installation and repository boundary.
  ///
  /// Organizations created by the old workspace backfill predate these
  /// fields. Before the first sibling is created, a bounded scan promotes the
  /// one legacy installation and the union of repositories already selected
  /// by that tenant. From then on, an explicit empty repository list means
  /// allow nothing rather than the legacy "not declared" state.
  Future<void> resolveGithubConfiguration(String organizationId) async {
    final ref = firestore.collection(organizations).doc(organizationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const ApiError(
        404,
        'organization_not_found',
        'Organization not found.',
      );
    }
    final needsInstallation = !data.containsKey('githubInstallationId');
    final needsRepositories = !data.containsKey('repositories');
    if (!needsInstallation && !needsRepositories) return;

    const migrationWorkspaceLimit = 200;
    final workspaces = await firestore
        .collection('workspaces')
        .where('organizationId', WhereFilter.equal, organizationId)
        .limit(migrationWorkspaceLimit + 1)
        .get();
    if (workspaces.docs.length > migrationWorkspaceLimit) {
      throw const ApiError(
        409,
        'organization_installation_migration_too_large',
        'Set the organization GitHub installation before creating another '
            'workspace.',
      );
    }
    final update = <FieldPath, Object?>{
      FieldPath(const ['updatedAt']): Timestamp.now(),
    };
    if (needsInstallation) {
      final ids = workspaces.docs
          .map((workspace) => workspace.data()['githubInstallationId'])
          .whereType<num>()
          .map((value) => value.toInt())
          .where((value) => value > 0)
          .toSet();
      if (ids.length > 1) {
        throw const ApiError(
          409,
          'organization_installation_conflict',
          'The organization has more than one legacy GitHub installation. '
              'Choose the organization installation before creating another '
              'workspace.',
        );
      }
      update[FieldPath(const ['githubInstallationId'])] = ids.firstOrNull;
    }
    if (needsRepositories) {
      final repositories = workspaces.docs
          .expand((workspace) {
            final raw = workspace.data()['repositories'];
            return raw is List<Object?>
                ? raw.whereType<String>()
                : const <String>[];
          })
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      if (repositories.length > maxOrganizationRepositories) {
        throw const ApiError(
          409,
          'organization_repository_migration_too_large',
          'Set the organization repository boundary before creating another '
              'workspace.',
        );
      }
      update[FieldPath(const ['repositories'])] = repositories.toList()..sort();
    }
    await ref.update(update);
  }

  Future<({bool declared, Set<String> repositories})> repositoryBoundary(
    String organizationId,
  ) async {
    final snapshot = await firestore
        .collection(organizations)
        .doc(organizationId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const ApiError(
        404,
        'organization_not_found',
        'Organization not found.',
      );
    }
    final raw = data['repositories'];
    return (
      declared: data.containsKey('repositories'),
      repositories: raw is List<Object?>
          ? raw.whereType<String>().toSet()
          : const <String>{},
    );
  }

  /// Widens the explicit tenant boundary without losing a concurrent update.
  Future<void> addRepositories(
    String organizationId,
    Set<String> repositoriesToAdd,
  ) async {
    if (repositoriesToAdd.isEmpty) return;
    await OrganizationResourceStore(
      firestore,
      emulated: emulated,
    ).addPrimaryRepositories(
      organizationId: organizationId,
      repositories: repositoriesToAdd,
    );
  }

  Future<void> saveGithubInstallationId(
    String organizationId,
    int? installationId,
  ) async {
    if (installationId != null && installationId <= 0) {
      throw const ApiError(
        400,
        'invalid_installation',
        'GitHub installation ID must be a positive integer.',
      );
    }
    await OrganizationResourceStore(
      firestore,
      emulated: emulated,
    ).savePrimaryGitHubConfiguration(
      organizationId: organizationId,
      installationId: installationId,
    );
  }

  /// Gives every workspace that has no organization one of its own.
  ///
  /// One organization per workspace rather than one for everything: an
  /// organization is a tenant, and merging separately-owned workspaces into a
  /// shared tenant would assert a relationship the existing data does not
  /// record. A tenant that wants several projects can create more workspaces
  /// inside the organization it now has.
  ///
  /// Idempotent, and it never touches a workspace that already resolves. Run it
  /// twice and the second run reports nothing to do, which is what makes it
  /// safe to re-run after a partial failure.
  Future<Map<String, Object?>> backfill({bool dryRun = false}) async {
    final workspaces = await firestore.collection('workspaces').get();
    final created = <Map<String, Object?>>[];
    var skipped = 0;

    for (final workspace in workspaces.docs) {
      final data = workspace.data();
      final existing = data['organizationId'];
      if (existing is String && existing.isNotEmpty) {
        skipped++;
        continue;
      }
      final workspaceId = workspace.ref.id;
      final members = await firestore
          .collection('workspaceMemberships')
          .where('workspaceId', WhereFilter.equal, workspaceId)
          .get();
      // The workspace Owner becomes the organization Owner. Absent one the
      // organization is created ownerless rather than promoting an arbitrary
      // member, and the report names it so a human can decide.
      final owners = members.docs
          .map((snapshot) => snapshot.data())
          .where((member) => member['role'] == 'owner')
          .toList();
      final organizationId = _uuid.v4();
      final now = Timestamp.now();
      final record = <String, Object?>{
        'organizationId': organizationId,
        'workspaceId': workspaceId,
        'name': data['name'] as String? ?? 'Untitled organization',
        'members': members.size,
        'owners': owners.length,
      };
      created.add(record);
      if (dryRun) continue;

      final batch = firestore.batch();
      batch.set(firestore.collection(organizations).doc(organizationId), {
        'name': data['name'] as String? ?? 'Untitled organization',
        'createdAt': now,
        'createdBy': owners.isEmpty ? '' : owners.first['uid'] as String? ?? '',
        'githubInstallationId': data['githubInstallationId'],
        'backfilledFromWorkspace': workspaceId,
      });
      for (final member in members.docs) {
        final memberData = member.data();
        final uid = memberData['uid'] as String? ?? '';
        if (uid.isEmpty) continue;
        // Everyone keeps the workspace access they already had; the
        // organization role only says how they stand at the tenant tier.
        batch.set(
          firestore
              .collection(memberships)
              .doc(membershipId(organizationId, uid)),
          {
            'organizationId': organizationId,
            'uid': uid,
            'email': memberData['email'] as String? ?? '',
            'role': memberData['role'] == 'owner'
                ? OrganizationRole.owner.value
                : OrganizationRole.member.value,
            'featureClaims': <String>[],
            'createdAt': now,
            'updatedAt': now,
            'backfilled': true,
          },
        );
        batch.update(member.ref, {
          FieldPath(const ['organizationId']): organizationId,
        });
      }
      batch.update(workspace.ref, {
        FieldPath(const ['organizationId']): organizationId,
      });
      await batch.commit();
    }

    return {
      'dryRun': dryRun,
      'workspacesScanned': workspaces.size,
      'alreadyResolved': skipped,
      'organizationsCreated': created.length,
      'organizations': created,
    };
  }
}
