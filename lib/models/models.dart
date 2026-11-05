import 'data_plane_connection.dart';
import 'organization_access.dart';
import 'organization_resources.dart';
import 'project_connection.dart';
import 'runtime_estimate.dart';
import 'workflow_runtime_requirement.dart';
import 'workshop_room.dart';

export 'customer_runner_pool.dart';
export 'fleet.dart';
export 'interactive_session.dart';
export 'organization_access.dart';
export 'organization_people.dart';
export 'organization_resources.dart';
export 'project_connection.dart';
export 'runtime_estimate.dart';
export 'workflow_runtime_requirement.dart';

typedef JsonMap = Map<String, Object?>;

final class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.isOwner,
  });

  factory UserProfile.fromJson(JsonMap json) => UserProfile(
    uid: json['uid'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    isOwner: json['isOwner'] as bool? ?? false,
  );

  final String uid;
  final String email;
  final String displayName;
  final bool isOwner;
}

final class WorkspaceModel {
  const WorkspaceModel({
    required this.id,
    required this.name,
    this.organizationId = '',
    required this.environment,
    required this.githubInstallationId,
    required this.repositories,
    required this.projects,
    required this.workflows,
    required this.artifactStorage,
    this.workshopRooms = const [],
    this.promptEnhancement,
    this.connection,
    this.resolvedConnection,
    this.resourceGrantVersion = 0,
    this.resourceGrants = const WorkspaceResourceGrantsModel(),
  });

  factory WorkspaceModel.fromJson(JsonMap json) => WorkspaceModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    // Empty until this deployment moves to the tenant tier.
    organizationId: json['organizationId'] as String? ?? '',
    environment: json['environment'] as String? ?? 'dev',
    githubInstallationId: (json['githubInstallationId'] as num?)?.toInt(),
    repositories: _strings(json['repositories']),
    projects: _maps(json['projects']).map(ProjectConnection.fromJson).toList(),
    workflows: _strings(json['workflows']),
    workshopRooms: _maps(
      json['workshopRooms'],
    ).map(WorkshopRoomModel.fromJson).toList(),
    artifactStorage: json['artifactStorage'] == null
        ? null
        : ArtifactStorageModel.fromJson(asJsonMap(json['artifactStorage'])),
    promptEnhancement: json['promptEnhancement'] == null
        ? null
        : PromptEnhancementModel.fromJson(asJsonMap(json['promptEnhancement'])),
    connection: json['connection'] == null
        ? null
        : DataPlaneConnectionModel.fromJson(asJsonMap(json['connection'])),
    resolvedConnection: json['resolvedConnection'] == null
        ? null
        : DataPlaneConnectionModel.fromJson(
            asJsonMap(json['resolvedConnection']),
          ),
    resourceGrantVersion: (json['resourceGrantVersion'] as num?)?.toInt() ?? 0,
    resourceGrants: WorkspaceResourceGrantsModel.fromJson(json),
  );

  final String id;
  final String name;

  /// The tenant that owns this project, or empty before the backfill.
  final String organizationId;
  final String environment;
  final int? githubInstallationId;
  final List<String> repositories;
  final List<ProjectConnection> projects;
  final List<String> workflows;
  final List<WorkshopRoomModel> workshopRooms;
  final ArtifactStorageModel? artifactStorage;
  final PromptEnhancementModel? promptEnhancement;
  final DataPlaneConnectionModel? connection;
  final DataPlaneConnectionModel? resolvedConnection;
  final int resourceGrantVersion;
  final WorkspaceResourceGrantsModel resourceGrants;
}

final class PromptEnhancementModel {
  const PromptEnhancementModel({
    required this.enabled,
    required this.apiKeySecretVersion,
    this.hasApiKey = false,
    this.apiKeyLast4 = '',
  });

  factory PromptEnhancementModel.fromJson(JsonMap json) {
    return PromptEnhancementModel(
      enabled: json['enabled'] == true,
      apiKeySecretVersion: json['apiKeySecretVersion'] as String? ?? '',
      hasApiKey: json['hasApiKey'] == true,
      apiKeyLast4: json['apiKeyLast4'] as String? ?? '',
    );
  }

  final bool enabled;
  final String apiKeySecretVersion;

  /// True when a key is stored in ii-os. The key itself never travels here --
  /// only its last four characters, enough to tell one credential from another.
  final bool hasApiKey;
  final String apiKeyLast4;
}

final class ArtifactStorageModel {
  const ArtifactStorageModel({
    required this.bucket,
    required this.prefix,
    required this.publisherServiceAccount,
    required this.retentionDays,
  });

  factory ArtifactStorageModel.fromJson(JsonMap json) => ArtifactStorageModel(
    bucket: json['bucket'] as String? ?? '',
    prefix: json['prefix'] as String? ?? '',
    publisherServiceAccount: json['publisherServiceAccount'] as String? ?? '',
    retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 30,
  );

  final String bucket;
  final String prefix;
  final String publisherServiceAccount;
  final int retentionDays;

  JsonMap toJson() => {
    'provider': 'gcs',
    'bucket': bucket,
    'publisherServiceAccount': publisherServiceAccount,
    'retentionDays': retentionDays,
  };
}

final class WorkflowInputModel {
  const WorkflowInputModel({
    required this.type,
    required this.required,
    this.maxLength,
    this.allowedValues = const [],
    this.minimum,
    this.maximum,
    this.defaultNumber,
  });

  factory WorkflowInputModel.fromJson(JsonMap json) => WorkflowInputModel(
    type: json['type'] as String? ?? '',
    required: json['required'] as bool? ?? false,
    maxLength: (json['maxLength'] as num?)?.toInt(),
    allowedValues: switch (json['allowedValues']) {
      final List<Object?> values => values.whereType<String>().toList(),
      _ => const [],
    },
    minimum: (json['minimum'] as num?)?.toDouble(),
    maximum: (json['maximum'] as num?)?.toDouble(),
    defaultNumber: (json['default'] as num?)?.toDouble(),
  );

  final String type;
  final bool required;

  /// The catalog's character budget, which differs by an order of magnitude
  /// between fields -- 4,000 for a song description, 30,000 for its lyrics.
  final int? maxLength;
  final List<String> allowedValues;
  final double? minimum;
  final double? maximum;
  final double? defaultNumber;
}

final class WorkflowTemplateModel {
  const WorkflowTemplateModel({
    required this.id,
    required this.workflowId,
    required this.version,
    required this.displayName,
    required this.model,
    required this.repository,
    required this.enabled,
    required this.disabledReason,
    this.inputs = const {},
    this.runtimeEstimates = const [],
    this.runtime,
  });

  factory WorkflowTemplateModel.fromJson(JsonMap json) {
    final displayName = json['displayName'] as String? ?? '';
    return WorkflowTemplateModel(
      id: json['id'] as String? ?? '',
      workflowId: json['workflowId'] as String? ?? '',
      version: json['version'] as String? ?? '',
      displayName: displayName,
      model: json['model'] as String? ?? displayName,
      repository: json['repository'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      disabledReason: json['disabledReason'] as String? ?? '',
      inputs: switch (json['inputs']) {
        final Map<Object?, Object?> values => values.map(
          (key, value) => MapEntry(
            key.toString(),
            WorkflowInputModel.fromJson(asJsonMap(value)),
          ),
        ),
        _ => const {},
      },
      runtimeEstimates: switch (json['runtimeEstimates']) {
        final List<Object?> values =>
          values
              .map(
                (value) =>
                    WorkflowRuntimeEstimateModel.fromJson(asJsonMap(value)),
              )
              .toList(growable: false),
        _ => const [],
      },
      runtime: WorkflowRuntimeRequirement.fromJson(json['runtime']),
    );
  }

  final String id;
  final String workflowId;
  final String version;
  final String displayName;
  final String model;
  final String repository;
  final bool enabled;
  final String disabledReason;
  final Map<String, WorkflowInputModel> inputs;
  final List<WorkflowRuntimeEstimateModel> runtimeEstimates;

  /// The execution runtime this workflow needs, when it declares one.
  final WorkflowRuntimeRequirement? runtime;

  RuntimeEstimateSnapshot? estimateRuntime(Map<String, Object?> inputs) {
    for (final estimate in runtimeEstimates) {
      final resolved = estimate.resolve(inputs);
      if (resolved != null) return resolved;
    }
    return null;
  }
}

final class MembershipModel {
  const MembershipModel({
    required this.workspaceId,
    required this.uid,
    required this.email,
    required this.role,
    required this.roleLabel,
    required this.featureClaims,
    required this.capabilities,
  });

  factory MembershipModel.fromJson(JsonMap json) => MembershipModel(
    workspaceId: json['workspaceId'] as String? ?? '',
    uid: json['uid'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: json['role'] as String? ?? 'view_only',
    roleLabel: json['roleLabel'] as String? ?? 'View Only',
    featureClaims: _strings(json['featureClaims']).toSet(),
    capabilities: _strings(json['effectiveCapabilities']).toSet(),
  );

  final String workspaceId;
  final String uid;
  final String email;
  final String role;
  final String roleLabel;
  final Set<String> featureClaims;
  final Set<String> capabilities;

  bool can(String capability) => capabilities.contains(capability);
}

final class WorkspaceAccess {
  const WorkspaceAccess({required this.workspace, required this.membership});

  factory WorkspaceAccess.fromJson(JsonMap json) => WorkspaceAccess(
    workspace: WorkspaceModel.fromJson(asJsonMap(json['workspace'])),
    membership: MembershipModel.fromJson(asJsonMap(json['membership'])),
  );

  final WorkspaceModel workspace;
  final MembershipModel membership;
}

final class SessionModel {
  const SessionModel({
    required this.user,
    required this.workspaces,
    this.organizations = const [],
  });

  factory SessionModel.fromJson(JsonMap json) => SessionModel(
    user: UserProfile.fromJson(asJsonMap(json['user'])),
    workspaces: _maps(
      json['workspaces'],
    ).map(WorkspaceAccess.fromJson).toList(),
    // Absent on a deployment that has not moved to the tenant tier yet, which
    // is an ordinary state rather than an error.
    organizations: _maps(
      json['organizations'],
    ).map(OrganizationAccess.fromJson).toList(),
  );

  final UserProfile user;
  final List<WorkspaceAccess> workspaces;
  final List<OrganizationAccess> organizations;

  /// The tenant that owns [workspaceId], when the session knows of one.
  OrganizationAccess? organizationFor(String? workspaceId) {
    if (workspaceId == null || workspaceId.isEmpty) return null;
    final workspace = workspaces
        .where((access) => access.workspace.id == workspaceId)
        .firstOrNull;
    final id = workspace?.workspace.organizationId ?? '';
    if (id.isEmpty) return null;
    return organizations.where((org) => org.id == id).firstOrNull;
  }
}

JsonMap asJsonMap(Object? value) {
  if (value is JsonMap) return value;
  if (value is Map) return value.cast<String, Object?>();
  return <String, Object?>{};
}

List<JsonMap> _maps(Object? value) {
  if (value is! List<Object?>) return <JsonMap>[];
  return value.map(asJsonMap).toList();
}

List<String> _strings(Object? value) {
  return value is List<Object?>
      ? value.whereType<String>().toList()
      : <String>[];
}
