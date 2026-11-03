import 'data_plane_connection.dart';
import 'organization_resources.dart';
import 'retention_policy.dart';
import 'workshop_room.dart';
import 'workspace_resource_grants.dart';

enum WorkspaceRole {
  owner('owner', 'Workspace Owner'),
  admin('admin', 'Workspace Admin'),
  editor('editor', 'Workspace Editor'),
  viewOnly('view_only', 'Workspace Viewer'),
  ai('ai', 'Workspace AI');

  const WorkspaceRole(this.value, this.label);

  final String value;
  final String label;

  static WorkspaceRole parse(Object? value) {
    return WorkspaceRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => throw const FormatException('Unknown workspace role'),
    );
  }
}

enum Capability {
  workspaceRead('workspace.read', 'View workspace'),
  workspaceManage('workspace.manage', 'Manage workspace settings'),
  membersManage('members.manage', 'Manage workspace members'),
  ticketsRead('tickets.read', 'View tickets'),
  ticketsWrite('tickets.write', 'Create and edit tickets'),
  pullRequestsMerge('pull_requests.merge', 'Merge pull requests'),
  agentPermissionsRead('agent.permissions.read', 'View agent permissions'),
  agentPermissionsManage(
    'agent.permissions.manage',
    'Install agent permissions',
  ),
  projectFieldsManage('project.fields.manage', 'Edit project status types'),
  charactersRead('characters.read', 'View characters'),
  charactersWrite('characters.write', 'Create and edit characters'),
  jobsRead('jobs.read', 'View jobs'),
  jobsTrigger('jobs.trigger', 'Launch jobs'),
  interactiveSessionsRead(
    'interactive.sessions.read',
    'View interactive agent sessions',
  ),
  interactiveSessionsLaunch(
    'interactive.sessions.launch',
    'Launch interactive agent sessions',
  ),
  interactiveSessionsManage(
    'interactive.sessions.manage',
    'Manage interactive agent sessions',
  ),
  auditRead('audit.read', 'View workspace activity'),
  agentUsageWrite('agent.usage.write', 'Report aggregate AI usage'),
  linesRead('lines.read', 'View production lines'),
  linesManage('lines.manage', 'Manage production lines'),
  linesMembersManage('lines.members.manage', 'Manage production-line access');

  const Capability(this.value, this.label);

  final String value;
  final String label;

  static Capability? tryParse(String value) {
    for (final capability in Capability.values) {
      if (capability.value == value) return capability;
    }
    return null;
  }
}

const Map<WorkspaceRole, Set<Capability>> roleCapabilityCeilings = {
  WorkspaceRole.owner: {...Capability.values},
  WorkspaceRole.admin: {...Capability.values},
  WorkspaceRole.editor: {
    Capability.workspaceRead,
    Capability.ticketsRead,
    Capability.ticketsWrite,
    Capability.pullRequestsMerge,
    Capability.agentPermissionsRead,
    Capability.charactersRead,
    Capability.charactersWrite,
    Capability.jobsRead,
    Capability.jobsTrigger,
    Capability.interactiveSessionsRead,
    Capability.interactiveSessionsLaunch,
    Capability.auditRead,
    Capability.agentUsageWrite,
    Capability.linesRead,
  },
  WorkspaceRole.viewOnly: {
    Capability.workspaceRead,
    Capability.ticketsRead,
    Capability.agentPermissionsRead,
    Capability.charactersRead,
    Capability.jobsRead,
    Capability.auditRead,
    Capability.interactiveSessionsRead,
    Capability.linesRead,
  },
  WorkspaceRole.ai: {
    Capability.workspaceRead,
    Capability.ticketsRead,
    Capability.agentPermissionsRead,
    Capability.charactersRead,
    Capability.charactersWrite,
    Capability.jobsRead,
    Capability.jobsTrigger,
    Capability.interactiveSessionsRead,
    Capability.interactiveSessionsLaunch,
    Capability.agentUsageWrite,
    // Read only, deliberately. An AI identity that could grant itself a
    // production line, or widen the permission scope a line carries, would not
    // be scoped at all.
    Capability.linesRead,
  },
};

/// The role ceilings and human labels rendered by the workspace access editor.
///
/// The API owns this catalog so a newly added backend capability cannot remain
/// invisible or be represented by a raw authorization string in the client.
List<Map<String, Object?>> workspacePermissionRoleCatalog() => [
  for (final role in WorkspaceRole.values)
    {
      'id': role.value,
      'label': role.label,
      'capabilities': [
        for (final capability
            in (roleCapabilityCeilings[role] ?? const <Capability>{}).toList()
              ..sort((left, right) => left.label.compareTo(right.label)))
          {'id': capability.value, 'label': capability.label},
      ],
    },
];

final class Membership {
  const Membership({
    required this.workspaceId,
    required this.uid,
    required this.email,
    required this.role,
    required this.featureClaims,
    this.suspended = false,
  });

  factory Membership.fromData(Map<String, Object?> data) {
    final rawFeatures = data['featureClaims'];
    final features = rawFeatures is List<Object?>
        ? rawFeatures.whereType<String>().toSet()
        : <String>{};
    return Membership(
      // Absent means active: every membership written before access could be
      // switched off is one that was never switched off.
      suspended: data['status'] == 'suspended',
      workspaceId: data['workspaceId'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: WorkspaceRole.parse(data['role']),
      featureClaims: features,
    );
  }

  final String workspaceId;
  final String uid;
  final String email;
  final WorkspaceRole role;
  final Set<String> featureClaims;

  /// Whether this access is currently switched off.
  ///
  /// Suspending keeps the record so turning access back on restores the role
  /// and claims the person had, and so the question "who was on this project"
  /// still has an answer afterwards.
  final bool suspended;

  Set<Capability> get effectiveCapabilities {
    // Suspension is enforced here rather than at each call site, so a route
    // that forgets to ask cannot accidentally honour switched-off access.
    if (suspended) return const <Capability>{};
    final ceiling = roleCapabilityCeilings[role] ?? const <Capability>{};
    if (role == WorkspaceRole.owner) return {...ceiling};
    final effective = featureClaims
        .map(Capability.tryParse)
        .whereType<Capability>()
        .where(ceiling.contains)
        .toSet();
    if (effective.contains(Capability.jobsTrigger) &&
        ceiling.contains(Capability.jobsRead)) {
      effective.add(Capability.jobsRead);
    }
    // Creating and queueing a ticket requires resolving the exact installed
    // permission profile shown in the Workshop. Ticket authors therefore need
    // read-only profile visibility, while installation remains independently
    // protected by agentPermissionsManage.
    if (effective.contains(Capability.ticketsWrite) &&
        ceiling.contains(Capability.agentPermissionsRead)) {
      effective.add(Capability.agentPermissionsRead);
    }
    return effective;
  }

  bool allows(Capability capability) =>
      effectiveCapabilities.contains(capability);

  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'uid': uid,
    'email': email,
    'role': role.value,
    'roleLabel': role.label,
    'suspended': suspended,
    'featureClaims': featureClaims.toList()..sort(),
    'effectiveCapabilities':
        effectiveCapabilities.map((item) => item.value).toList()..sort(),
  };
}

/// The capabilities [actor] may place on a membership carrying [targetRole].
///
/// A grant is bounded twice: by the ceiling of the role being assigned, and by
/// what the actor personally holds. Authority an actor does not have is
/// authority it cannot hand out, so `members.manage` delegates the access its
/// holder already has instead of unlocking every other capability in the
/// workspace -- including on the actor's own membership.
Set<Capability> grantableCapabilities({
  required Membership actor,
  required WorkspaceRole targetRole,
}) {
  final ceiling = roleCapabilityCeilings[targetRole] ?? const <Capability>{};
  return ceiling.intersection(actor.effectiveCapabilities);
}

/// [requested] reduced to the claims [actor] may grant, sorted and normalized.
///
/// Unknown claim strings are dropped rather than rejected, matching how the
/// role ceiling has always treated them.
List<String> boundedFeatureClaims({
  required Membership actor,
  required WorkspaceRole targetRole,
  required Set<String> requested,
}) {
  final grantable = grantableCapabilities(actor: actor, targetRole: targetRole);
  return requested
      .map(Capability.tryParse)
      .whereType<Capability>()
      .where(grantable.contains)
      .map((item) => item.value)
      .toList()
    ..sort();
}

final class GitHubProjectConfig {
  const GitHubProjectConfig({
    required this.id,
    required this.number,
    required this.owner,
    required this.title,
  });

  factory GitHubProjectConfig.fromJson(Map<String, Object?> json) {
    return GitHubProjectConfig(
      id: json['id'] as String? ?? '',
      number: (json['number'] as num?)?.toInt() ?? 0,
      owner: json['owner'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }

  final String id;
  final int number;
  final String owner;
  final String title;

  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'owner': owner,
    'title': title,
  };
}

final class PromptEnhancementConfig {
  const PromptEnhancementConfig({
    required this.enabled,
    required this.apiKeySecretVersion,
    this.hasApiKey = false,
    this.apiKeyLast4 = '',
  });

  factory PromptEnhancementConfig.fromJson(Map<String, Object?> json) {
    return PromptEnhancementConfig(
      enabled: json['enabled'] == true,
      apiKeySecretVersion: json['apiKeySecretVersion'] as String? ?? '',
      hasApiKey: json['hasApiKey'] == true,
      apiKeyLast4: json['apiKeyLast4'] as String? ?? '',
    );
  }

  final bool enabled;
  final String apiKeySecretVersion;

  /// True when a DeepSeek key has been pasted into ii-os and stored encrypted.
  ///
  /// The key itself never travels on this object. The workspace document holds
  /// only the fact that one exists plus its last four characters, so a person
  /// can tell which key is installed without the API ever being able to hand it
  /// back.
  final bool hasApiKey;
  final String apiKeyLast4;

  /// Where the DeepSeek credential comes from, for display and for metadata.
  String get keySource => switch (this) {
    _ when hasApiKey => 'inline',
    _ when apiKeySecretVersion.isNotEmpty => 'secret_manager',
    _ => 'none',
  };

  /// True when enhancement is on and some credential is installed.
  bool get isConfigured => enabled && keySource != 'none';

  Map<String, Object?> toJson() => {
    'provider': 'deepseek',
    'enabled': enabled,
    'apiKeySecretVersion': apiKeySecretVersion,
    'hasApiKey': hasApiKey,
    'apiKeyLast4': apiKeyLast4,
  };
}

final class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    this.organizationId = '',
    required this.environment,
    required this.githubInstallationId,
    required this.repositories,
    required this.projects,
    required this.workflows,
    required this.artifactStorage,
    this.organizationRepositories = const <String>{},
    this.organizationRepositoryBoundaryDeclared = false,
    this.organizationResources = const OrganizationResourceCatalog.empty(),
    this.resourceGrants = const WorkspaceResourceGrants.empty(),
    this.resourceGrantsExplicit = false,
    this.workshopRooms = const [],
    this.promptEnhancement,
    this.connection,
  });

  factory Workspace.fromData(
    String id,
    Map<String, Object?> data, {
    bool emulated = false,
    Set<String> organizationRepositories = const <String>{},
    bool organizationRepositoryBoundaryDeclared = false,
    bool organizationInstallationResolved = false,
    int? organizationGithubInstallationId,
    OrganizationResourceCatalog organizationResources =
        const OrganizationResourceCatalog.empty(),
    WorkspaceResourceGrants? resourceGrants,
  }) {
    final rawProjects = data['projects'];
    final projects = <GitHubProjectConfig>[];
    if (rawProjects is List<Object?>) {
      for (final value in rawProjects) {
        if (value is Map<String, Object?>) {
          projects.add(GitHubProjectConfig.fromJson(value));
        } else if (value is Map) {
          projects.add(
            GitHubProjectConfig.fromJson(value.cast<String, Object?>()),
          );
        }
      }
    }
    final workshopRooms = parseWorkshopRooms(data['workshopRooms']);
    final effectiveGrants =
        resourceGrants ??
        WorkspaceResourceGrants.fromWorkspaceData(
          data,
          organizationResources,
          workspaceId: id,
        );
    final primaryGitHub = effectiveGrants.primaryGitHub(organizationResources);
    final storedRepositories = _stringList(data['repositories']);
    final grantedRepositories =
        effectiveGrants.github
            .expand((grant) => grant.repositories)
            .toSet()
            .toList()
          ..sort();
    return Workspace(
      id: id,
      organizationRepositories: organizationRepositories,
      organizationRepositoryBoundaryDeclared:
          organizationRepositoryBoundaryDeclared,
      organizationResources: organizationResources,
      resourceGrants: effectiveGrants,
      resourceGrantsExplicit:
          data['resourceGrantVersion'] == workspaceResourceGrantVersion,
      name: data['name'] as String? ?? 'Untitled workspace',
      organizationId: data['organizationId'] as String? ?? '',
      environment: data['environment'] as String? ?? 'dev',
      githubInstallationId:
          primaryGitHub?.installationId ??
          (organizationInstallationResolved
              ? organizationGithubInstallationId
              : (data['githubInstallationId'] as num?)?.toInt()),
      repositories:
          data['resourceGrantVersion'] == workspaceResourceGrantVersion
          ? grantedRepositories
          : storedRepositories,
      projects: projects,
      workflows: _stringList(data['workflows']),
      workshopRooms: workshopRooms,
      artifactStorage: data['artifactStorage'] is Map
          ? ArtifactStorageConfig.fromJson(
              (data['artifactStorage']! as Map).cast<String, Object?>(),
            )
          : null,
      promptEnhancement: data['promptEnhancement'] is Map
          ? PromptEnhancementConfig.fromJson(
              (data['promptEnhancement']! as Map).cast<String, Object?>(),
            )
          : null,
      connection: _connectionFromData(data['connection'], emulated: emulated),
    );
  }

  final String id;
  final String name;

  /// The tenant this project belongs to, or empty before the backfill runs.
  ///
  /// Empty is a real state rather than an error: a workspace that has not been
  /// assigned to an organization yet still works exactly as it did.
  final String organizationId;
  final String environment;
  final int? githubInstallationId;
  final List<String> repositories;

  /// What this workspace's organization allows, or empty when it allows
  /// everything because it has not declared a set yet.
  ///
  /// Populated when the workspace is loaded rather than stored on it, so a
  /// tenant narrowing its own set takes effect immediately instead of after
  /// every workspace record is rewritten.
  final Set<String> organizationRepositories;
  final bool organizationRepositoryBoundaryDeclared;
  final OrganizationResourceCatalog organizationResources;
  final WorkspaceResourceGrants resourceGrants;
  final bool resourceGrantsExplicit;
  final List<GitHubProjectConfig> projects;
  final List<String> workflows;
  final List<WorkshopRoomConfig> workshopRooms;
  final ArtifactStorageConfig? artifactStorage;
  final PromptEnhancementConfig? promptEnhancement;
  final DataPlaneConnection? connection;

  /// Whether this workspace may act on [repository].
  ///
  /// Two steps, not one. One GitHub App installation now serves every
  /// workspace in a tenant, so a workspace's own selection is no longer
  /// sufficient: without the organization's set as an outer bound, any
  /// workspace admin could select any repository the tenant's App can reach
  /// and act on another project's code. Every dispatch, token, and health
  /// check already routes through here, which is why the check lives here
  /// rather than at each of them.
  bool containsRepository(String repository) {
    if (!organizationResources.isEmpty || !resourceGrants.isEmpty) {
      return resourceGrants.allowsRepository(organizationResources, repository);
    }
    if (!repositories.contains(repository)) return false;
    if (!organizationRepositoryBoundaryDeclared) return true;
    return organizationRepositories.contains(repository);
  }

  bool allowsGitHubPermission(String permission, {String? repository}) =>
      resourceGrants.allowsGitHubPermission(
        organizationResources,
        permission,
        repository: repository,
      );

  bool get usesOrganizationResourceGrants =>
      resourceGrantsExplicit || !organizationResources.isEmpty;

  bool containsProject(String projectId) =>
      projects.any((item) => item.id == projectId);

  OrganizationGcpResource? get primaryGcpResource =>
      resourceGrants.primaryGcp(organizationResources);

  /// The data-plane connection this materialized workspace is authorized to
  /// use.
  ///
  /// Session clients must not need a second organization-directory result to
  /// recover this answer. The workspace access read has already loaded the
  /// organization catalog and validated the workspace's narrowed grants, so
  /// it can carry the resolved result without another Firestore read.
  DataPlaneConnection? get resolvedConnection {
    if (!usesOrganizationResourceGrants) return connection;
    if (resourceGrants.validateAgainst(organizationResources).isNotEmpty) {
      return null;
    }
    final resource = primaryGcpResource;
    return resource?.active == true ? resource!.connection : null;
  }

  OrganizationGitHubResource? get primaryGitHubResource =>
      resourceGrants.primaryGitHub(organizationResources);

  WorkspaceGitHubGrant? get primaryGitHubGrant =>
      resourceGrants.primaryGitHubGrant();

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'organizationId': organizationId,
    'environment': environment,
    'githubInstallationId': githubInstallationId,
    'repositories': repositories,
    'projects': projects.map((item) => item.toJson()).toList(),
    'workflows': workflows,
    'workshopRooms': workshopRooms.map((item) => item.toJson()).toList(),
    'artifactStorage': artifactStorage?.toJson(),
    'promptEnhancement': promptEnhancement?.toJson(),
    'connection': connection?.toJson(),
    'resolvedConnection': resolvedConnection?.toJson(),
    'resourceGrants': resourceGrants.toJson()['resourceGrants'],
    if (resourceGrantsExplicit)
      'resourceGrantVersion': workspaceResourceGrantVersion,
  };
}

final class ArtifactStorageConfig {
  const ArtifactStorageConfig({
    required this.bucket,
    required this.prefix,
    required this.publisherServiceAccount,
    required this.retentionDays,
  });

  factory ArtifactStorageConfig.fromJson(Map<String, Object?> json) {
    return ArtifactStorageConfig(
      bucket: json['bucket'] as String? ?? '',
      prefix: json['prefix'] as String? ?? '',
      publisherServiceAccount: json['publisherServiceAccount'] as String? ?? '',
      retentionDays:
          (json['retentionDays'] as num?)?.toInt() ??
          defaultArtifactRetentionDays,
    );
  }

  final String bucket;
  final String prefix;
  final String publisherServiceAccount;
  final int retentionDays;

  Map<String, Object?> toJson() => {
    'provider': 'gcs',
    'bucket': bucket,
    'prefix': prefix,
    'publisherServiceAccount': publisherServiceAccount,
    'retentionDays': retentionDays,
  };
}

List<String> _stringList(Object? value) {
  return value is List<Object?>
      ? value.whereType<String>().toList()
      : <String>[];
}

DataPlaneConnection? _connectionFromData(
  Object? value, {
  required bool emulated,
}) {
  if (value is! Map) return null;
  try {
    final connection = DataPlaneConnection.fromJson(
      value.cast<String, Object?>(),
      emulated: emulated,
    );
    return connection.configurationChecks().every((check) => check.passed)
        ? connection
        : null;
  } on FormatException {
    // Legacy connector-shaped records are treated as disconnected and must be
    // replaced through the workspace-scoped validation route.
    return null;
  }
}
