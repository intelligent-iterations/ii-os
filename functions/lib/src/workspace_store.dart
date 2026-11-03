import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'auth_service.dart';
import 'data_plane_connection.dart';
import 'domain.dart';
import 'organization.dart';
import 'organization_resources.dart';
import 'organization_store.dart';
import 'workshop_room.dart';
import 'workspace_invitation.dart';
import 'workspace_prompt_enhancement.dart';
import 'workspace_resource_grants.dart';

part 'workspace_invitation_store.dart';
part 'workspace_member_store.dart';
part 'workspace_store_validation.dart';

final class WorkspaceStore {
  WorkspaceStore(this.firestore, {this.emulated = false});

  final Firestore firestore;
  final bool emulated;
  final Uuid _uuid = const Uuid();
  static const sessionWorkspaceLimit = 200;

  Future<Workspace> getWorkspace(String workspaceId) async {
    final snapshot = await firestore
        .collection('workspaces')
        .doc(workspaceId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const ApiError(404, 'workspace_not_found', 'Workspace not found.');
    }
    final workspace = Workspace.fromData(workspaceId, data, emulated: emulated);
    if (workspace.organizationId.isEmpty) return workspace;
    // Read rather than stored on the workspace, so a tenant narrowing its
    // repository set takes effect on the next request instead of after every
    // workspace record is rewritten. Only tenanted workspaces pay for it.
    final organization = await firestore
        .collection(OrganizationStore.organizations)
        .doc(workspace.organizationId)
        .get();
    return materializeWorkspace(
      workspaceId: workspaceId,
      data: data,
      organization: organization.data(),
      emulated: emulated,
    );
  }

  /// The data plane this workspace runs on.
  ///
  /// The organization is asked first. A workspace narrows what its tenant has
  /// and never holds credentials of its own, so once the tenant is connected
  /// its connection is the answer for every workspace inside it -- which is what
  /// makes creating a second project stop being a provisioning run.
  ///
  /// The workspace's own record still answers when its organization has no
  /// connection, so a workspace whose credentials were never moved up keeps
  /// working unchanged. That fallback is a compatibility path, not a second
  /// source of truth.
  Future<DataPlaneConnection> requireConnection(
    String workspaceId, {
    required String permission,
  }) async {
    final workspace = await getWorkspace(workspaceId);
    return resolveConnection(workspace, permission: permission);
  }

  /// Reuses the current request's freshly resolved workspace without caching
  /// grants. The organization fallback retains its existing point read.
  Future<DataPlaneConnection> resolveConnection(
    Workspace workspace, {
    required String permission,
  }) async {
    final grant = workspace.resourceGrants.gcp
        .where((item) => item.primary)
        .firstOrNull;
    final resource = workspace.primaryGcpResource;
    if (workspace.resourceGrantsExplicit ||
        !workspace.organizationResources.isEmpty) {
      final errors = workspace.resourceGrants.validateAgainst(
        workspace.organizationResources,
      );
      if (errors.isNotEmpty) {
        throw ApiError(
          409,
          'workspace_resource_grant_stale',
          'The workspace resource selection is no longer allowed by its organization.',
          details: {'errors': errors.toList()..sort()},
        );
      }
      if (grant == null || resource?.active != true) {
        throw const ApiError(
          409,
          'workspace_gcp_resource_required',
          'Select an organization GCP resource for this workspace first.',
        );
      }
      if (!grant.permissions.contains(permission)) {
        throw ApiError(
          403,
          'workspace_gcp_permission_required',
          'This workspace was not granted $permission on its GCP resource.',
        );
      }
      return resource!.connection;
    }
    if (workspace.organizationId.isNotEmpty &&
        !workspace.resourceGrantsExplicit) {
      final owned = await OrganizationStore(
        firestore,
        emulated: emulated,
      ).getConnection(workspace.organizationId);
      if (owned != null) return owned;
    }
    final connection = workspace.connection;
    if (connection == null) {
      throw const ApiError(
        409,
        'workspace_not_connected',
        'Connect this workspace to its customer-owned data plane first.',
      );
    }
    return connection;
  }

  Future<Workspace> saveConnection(
    String workspaceId,
    DataPlaneConnection connection,
  ) async {
    final workspace = await getWorkspace(workspaceId);
    if (workspace.organizationId.isNotEmpty && workspace.connection == null) {
      throw const ApiError(
        409,
        'organization_connection_required',
        'Connect the organization that owns this workspace. Only an existing '
            'legacy workspace connection can be rotated during migration.',
      );
    }
    if (connection.workspaceId != workspaceId) {
      throw const ApiError(
        400,
        'workspace_connection_mismatch',
        'The connection is bound to a different ii-os workspace.',
      );
    }
    final stored = _validatedConnection(
      connection.toJson(),
      emulated: emulated,
    );
    await firestore.collection('workspaces').doc(workspaceId).update({
      'connection': stored,
      'artifactStorage': {
        'provider': 'gcs',
        'bucket': connection.bucket,
        'prefix': 'workspaces/$workspaceId',
        'publisherServiceAccount': connection.uploadServiceAccount,
        'retentionDays': 30,
      },
      'updatedAt': Timestamp.now(),
    });
    return getWorkspace(workspaceId);
  }

  Future<Membership?> getMembership(String workspaceId, String uid) async {
    final snapshot = await firestore
        .collection('workspaceMemberships')
        .doc(_membershipId(workspaceId, uid))
        .get();
    final data = snapshot.data();
    return snapshot.exists && data != null ? Membership.fromData(data) : null;
  }

  Future<Membership> requireAccess(
    AuthenticatedUser actor,
    String workspaceId,
    Capability capability,
  ) async =>
      (await requireAccessContext(actor, workspaceId, capability)).membership;

  Future<({Membership membership, Workspace workspace})> requireAccessContext(
    AuthenticatedUser actor,
    String workspaceId,
    Capability capability,
  ) async {
    final membership = await getMembership(workspaceId, actor.uid);
    if (membership == null || !membership.allows(capability)) {
      throw const ApiError(
        403,
        'forbidden',
        'Your workspace role does not allow this action.',
      );
    }
    final workspace = await getWorkspace(workspaceId);
    return (membership: membership, workspace: workspace);
  }

  Future<List<Map<String, Object?>>> listWorkspaceAccess(
    AuthenticatedUser actor,
  ) async {
    final memberships = await firestore
        .collection('workspaceMemberships')
        .where('uid', WhereFilter.equal, actor.uid)
        .limit(sessionWorkspaceLimit)
        .get();
    if (memberships.empty) return <Map<String, Object?>>[];
    final refs = memberships.docs
        .map(
          (snapshot) => firestore
              .collection('workspaces')
              .doc(snapshot.data()['workspaceId'] as String? ?? ''),
        )
        .toList();
    final workspaces = await firestore.getAll(refs);
    final rawWorkspaces = {
      for (final workspace in workspaces)
        if (workspace.exists && workspace.data() != null)
          workspace.ref.id: workspace.data()!,
    };
    final organizationIds = rawWorkspaces.values
        .map((data) => data['organizationId'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final organizationDocuments = organizationIds.isEmpty
        ? const <DocumentSnapshot<Map<String, Object?>>>[]
        : await firestore.getAll([
            for (final id in organizationIds)
              firestore.collection(OrganizationStore.organizations).doc(id),
          ]);
    final organizationsById = {
      for (final organization in organizationDocuments)
        if (organization.exists && organization.data() != null)
          organization.ref.id: organization.data()!,
    };
    final byId = {
      for (final entry in rawWorkspaces.entries)
        entry.key: materializeWorkspace(
          workspaceId: entry.key,
          data: entry.value,
          organization: organizationsById[entry.value['organizationId']],
          emulated: emulated,
        ),
    };
    return memberships.docs
        .map((snapshot) => Membership.fromData(snapshot.data()))
        // A switched-off project does not appear in the session at all. Listing
        // it greyed out would tell someone what exists inside a tenant they
        // currently have no access to.
        .where((membership) => !membership.suspended)
        .map((membership) {
          return {
            'workspace': byId[membership.workspaceId]?.toJson(),
            'membership': membership.toJson(),
          };
        })
        .where((item) => item['workspace'] != null)
        .toList();
  }

  Future<Workspace> createWorkspace({
    required String organizationId,
    required OrganizationMembership organizationActor,
    required String name,
    required String environment,
  }) async {
    if (organizationActor.organizationId != organizationId ||
        !organizationActor.allows(OrganizationCapability.workspacesCreate)) {
      throw const ApiError(
        403,
        'forbidden',
        'Your organization role does not allow workspace creation.',
      );
    }
    _validateEnvironment(environment);
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw const ApiError(
        400,
        'invalid_name',
        'A workspace name is required.',
      );
    }
    final organizationStore = OrganizationStore(firestore, emulated: emulated);
    await organizationStore.resolveGithubConfiguration(organizationId);
    final id = _uuid.v4();
    final now = Timestamp.now();
    final workspaceRef = firestore.collection('workspaces').doc(id);
    final membershipRef = firestore
        .collection('workspaceMemberships')
        .doc(_membershipId(id, organizationActor.uid));
    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    final organizationMemberRef = firestore
        .collection(OrganizationStore.memberships)
        .doc(
          organizationStore.membershipId(organizationId, organizationActor.uid),
        );
    await firestore.runTransaction<void>((transaction) async {
      final documents = await Future.wait([
        transaction.get(organizationRef),
        transaction.get(organizationMemberRef),
      ]);
      final organization = documents[0];
      final liveActor = documents[1];
      if (!organization.exists ||
          organization.data()?['deletionStartedAt'] != null) {
        throw const ApiError(
          409,
          'organization_deletion_in_progress',
          'This organization is being deleted.',
        );
      }
      if (!liveActor.exists ||
          !OrganizationMembership.fromData(
            liveActor.data()!,
          ).allows(OrganizationCapability.workspacesCreate)) {
        throw const ApiError(
          403,
          'forbidden',
          'Your organization role does not allow workspace creation.',
        );
      }
      transaction.set(workspaceRef, {
        'name': trimmed,
        'organizationId': organizationId,
        'environment': environment,
        'githubInstallationId': null,
        'repositories': <String>[],
        'projects': <Map<String, Object?>>[],
        'workflows': <String>[],
        'workshopRooms': <Map<String, Object?>>[],
        'artifactStorage': null,
        'promptEnhancement': null,
        'connection': null,
        ...const WorkspaceResourceGrants.empty().toJson(),
        'createdAt': now,
        'createdBy': organizationActor.uid,
        'updatedAt': now,
      });
      transaction.set(membershipRef, {
        'workspaceId': id,
        'organizationId': organizationId,
        'uid': organizationActor.uid,
        'email': organizationActor.email,
        'role': WorkspaceRole.owner.value,
        'featureClaims': <String>[],
        'createdAt': now,
        'updatedAt': now,
      });
    });
    return getWorkspace(id);
  }

  /// Materializes one persisted workspace with its organization resource
  /// ceiling. Kept pure so compatibility and authorization behavior is tested
  /// against the same boundary used by production reads.
  static Workspace materializeWorkspace({
    required String workspaceId,
    required Map<String, Object?> data,
    required Map<String, Object?>? organization,
    required bool emulated,
  }) {
    final allowed = organization?['repositories'];
    final organizationResources =
        organization == null || data['organizationId'] is! String
        ? const OrganizationResourceCatalog.empty()
        : OrganizationResourceCatalog.fromOrganizationData(
            data['organizationId']! as String,
            organization,
            emulated: emulated,
          );
    final resourceGrants = WorkspaceResourceGrants.fromWorkspaceData(
      data,
      organizationResources,
      workspaceId: workspaceId,
    );
    return Workspace.fromData(
      workspaceId,
      data,
      emulated: emulated,
      organizationRepositories: allowed is List<Object?>
          ? allowed.whereType<String>().toSet()
          : const <String>{},
      organizationRepositoryBoundaryDeclared:
          organization?.containsKey('repositories') ?? false,
      organizationInstallationResolved:
          organization?.containsKey('githubInstallationId') ?? false,
      organizationGithubInstallationId:
          (organization?['githubInstallationId'] as num?)?.toInt(),
      organizationResources: organizationResources,
      resourceGrants: resourceGrants,
    );
  }

  Future<Workspace> updateWorkspace(
    String workspaceId,
    Map<String, Object?> changes,
  ) async {
    const allowed = {
      'name',
      'environment',
      'githubInstallationId',
      'repositories',
      'projects',
      'workflows',
      'workshopRooms',
      'promptEnhancement',
    };
    if (changes.keys.any((key) => !allowed.contains(key))) {
      throw const ApiError(
        400,
        'invalid_workspace_update',
        'Connection and storage fields are managed by workspace validation.',
      );
    }
    final update = <String, Object?>{'updatedAt': Timestamp.now()};
    if (changes.containsKey('name')) {
      final name = changes['name'];
      if (name is! String || name.trim().isEmpty || name.length > 100) {
        throw const ApiError(
          400,
          'invalid_name',
          'A workspace name is required.',
        );
      }
      update['name'] = name.trim();
    }
    if (changes.containsKey('environment')) {
      final environment = changes['environment'];
      if (environment is! String) {
        throw const ApiError(
          400,
          'invalid_environment',
          'Environment is invalid.',
        );
      }
      _validateEnvironment(environment);
      update['environment'] = environment;
    }
    if (changes.containsKey('githubInstallationId')) {
      final id = changes['githubInstallationId'];
      if (id != null && (id is! num || id.toInt() <= 0)) {
        throw const ApiError(
          400,
          'invalid_installation',
          'GitHub installation ID must be a positive integer.',
        );
      }
      update['githubInstallationId'] = id == null ? null : (id as num).toInt();
    }
    for (final key in const ['repositories', 'workflows']) {
      if (changes.containsKey(key)) {
        update[key] = validatedWorkspaceStrings(changes[key], key);
      }
    }
    if (changes.containsKey('projects')) {
      update['projects'] = _validatedProjects(changes['projects']);
    }
    if (changes.containsKey('workshopRooms')) {
      final workspace = await getWorkspace(workspaceId);
      update['workshopRooms'] = validatedWorkshopRooms(
        changes['workshopRooms'],
        workspaceRepositories: workspace.repositories.toSet(),
        workspaceProjects: workspace.projects.map((item) => item.id).toSet(),
      ).map((room) => room.toJson()).toList();
    }
    if (changes.containsKey('promptEnhancement')) {
      update['promptEnhancement'] = validatedPromptEnhancement(
        changes['promptEnhancement'],
      );
    }
    await firestore.collection('workspaces').doc(workspaceId).update(update);
    return getWorkspace(workspaceId);
  }

  Future<void> deleteWorkspace({
    required String workspaceId,
    required AuthenticatedUser actor,
  }) async {
    final membership = await getMembership(workspaceId, actor.uid);
    if (membership == null || membership.role != WorkspaceRole.owner) {
      throw const ApiError(
        403,
        'workspace_owner_required',
        'Only the workspace owner can delete this workspace.',
      );
    }
    final members = await firestore
        .collection('workspaceMemberships')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .limit(2)
        .get();
    if (members.size > 1) {
      throw const ApiError(
        409,
        'workspace_has_members',
        'Remove other members before deleting this workspace.',
      );
    }
    final batch = firestore.batch();
    batch.delete(firestore.collection('workspaces').doc(workspaceId));
    batch.delete(
      firestore
          .collection('workspaceMemberships')
          .doc(_membershipId(workspaceId, actor.uid)),
    );
    await batch.commit();
  }

  Future<Map<String, Object?>> dashboard(String workspaceId) async {
    final results = await Future.wait<Object>([
      firestore
          .collection('workspaceMemberships')
          .where('workspaceId', WhereFilter.equal, workspaceId)
          .get(),
      firestore
          .collection('jobRuns')
          .where('workspaceId', WhereFilter.equal, workspaceId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(),
    ]);
    final members = results[0] as QuerySnapshot<Map<String, Object?>>;
    final jobs = results[1] as QuerySnapshot<Map<String, Object?>>;
    final jobData = jobs.docs
        .map((item) => item.data())
        .where((item) => item['ghostMode'] != true)
        .toList();
    const terminalStatuses = {'cleaned', 'completed', 'failed', 'cancelled'};
    return {
      'members': members.size,
      'jobs': jobData.length,
      'activeJobs': jobData.where((item) {
        return !terminalStatuses.contains(item['status']);
      }).length,
      'completedJobs': jobData
          .where(
            (item) =>
                item['status'] == 'cleaned' || item['status'] == 'completed',
          )
          .length,
      'openTickets': null,
    };
  }

  String _membershipId(String workspaceId, String uid) => '${workspaceId}_$uid';

  void _validateEnvironment(String environment) {
    if (environment != 'dev' && environment != 'prod') {
      throw const ApiError(400, 'invalid_environment', 'Use dev or prod.');
    }
  }
}
