import 'dart:convert';

import 'data_plane_connection.dart';
import 'models.dart';

final class OrganizationResourceCatalogModel {
  const OrganizationResourceCatalogModel({
    this.gcp = const [],
    this.github = const [],
    this.runners = const [],
  });

  factory OrganizationResourceCatalogModel.fromJson(JsonMap json) =>
      OrganizationResourceCatalogModel(
        gcp: _maps(
          json['gcpResources'],
        ).map(OrganizationGcpResourceModel.fromJson).toList(),
        github: _maps(
          json['githubResources'],
        ).map(OrganizationGitHubResourceModel.fromJson).toList(),
        runners: _maps(
          json['runnerPools'],
        ).map(OrganizationRunnerPoolModel.fromJson).toList(),
      );

  final List<OrganizationGcpResourceModel> gcp;
  final List<OrganizationGitHubResourceModel> github;
  final List<OrganizationRunnerPoolModel> runners;

  OrganizationGcpResourceModel? gcpById(String id) =>
      gcp.where((item) => item.id == id).firstOrNull;
}

final class OrganizationGcpResourceModel {
  const OrganizationGcpResourceModel({
    required this.id,
    required this.name,
    required this.connection,
    required this.permissions,
    required this.active,
    this.legacySourceWorkspaceId = '',
  });

  factory OrganizationGcpResourceModel.fromJson(JsonMap json) =>
      OrganizationGcpResourceModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'GCP project',
        connection: DataPlaneConnectionModel.fromJson(
          asJsonMap(json['connection']),
        ),
        permissions: _strings(json['permissionEnvelope']).toSet(),
        active: json['active'] != false,
        legacySourceWorkspaceId:
            json['legacySourceWorkspaceId']?.toString() ?? '',
      );

  final String id;
  final String name;
  final DataPlaneConnectionModel connection;
  final Set<String> permissions;
  final bool active;
  final String legacySourceWorkspaceId;
}

final class OrganizationGitHubResourceModel {
  const OrganizationGitHubResourceModel({
    required this.id,
    required this.name,
    required this.secretGcpResourceId,
    required this.appId,
    required this.privateKeySecret,
    required this.installationId,
    required this.repositories,
    required this.permissions,
    required this.active,
  });

  factory OrganizationGitHubResourceModel.fromJson(JsonMap json) =>
      OrganizationGitHubResourceModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'GitHub App',
        secretGcpResourceId: json['secretGcpResourceId']?.toString() ?? '',
        appId: json['appId']?.toString() ?? '',
        privateKeySecret: json['privateKeySecret']?.toString() ?? '',
        installationId: (json['installationId'] as num?)?.toInt() ?? 0,
        repositories: _strings(json['repositories']).toSet(),
        permissions: _strings(json['permissionEnvelope']).toSet(),
        active: json['active'] != false,
      );

  final String id;
  final String name;
  final String secretGcpResourceId;
  final String appId;
  final String privateKeySecret;
  final int installationId;
  final Set<String> repositories;
  final Set<String> permissions;
  final bool active;
}

final class OrganizationRunnerPoolModel {
  const OrganizationRunnerPoolModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.capabilities,
    required this.maxCpu,
    required this.maxRamMiB,
    required this.maxConcurrent,
    required this.active,
    this.providerPoolId = '',
  });

  factory OrganizationRunnerPoolModel.fromJson(JsonMap json) =>
      OrganizationRunnerPoolModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Runner pool',
        provider: json['provider']?.toString() ?? '',
        capabilities: _strings(json['capabilities']).toSet(),
        maxCpu: (json['maxCpu'] as num?)?.toInt() ?? 0,
        maxRamMiB: (json['maxRamMiB'] as num?)?.toInt() ?? 0,
        maxConcurrent: (json['maxConcurrent'] as num?)?.toInt() ?? 0,
        active: json['active'] != false,
        providerPoolId: json['providerPoolId']?.toString() ?? '',
      );

  final String id;
  final String name;
  final String provider;
  final Set<String> capabilities;
  final int maxCpu;
  final int maxRamMiB;
  final int maxConcurrent;
  final bool active;
  final String providerPoolId;
}

/// Organization Admin input for one validated GCP project envelope.
final class OrganizationGcpResourceDraft {
  const OrganizationGcpResourceDraft({
    required this.id,
    required this.name,
    required this.serviceAccountJson,
    required this.permissions,
    this.bucket = '',
    this.uploadServiceAccount = '',
    this.workloadIdentityProvider = '',
  });

  final String id;
  final String name;
  final String serviceAccountJson;
  final Set<String> permissions;
  final String bucket;
  final String uploadServiceAccount;
  final String workloadIdentityProvider;

  JsonMap toJson() => {
    'name': name,
    'serviceAccount': _serviceAccount(),
    if (bucket.isNotEmpty) 'bucket': bucket,
    if (uploadServiceAccount.isNotEmpty)
      'uploadServiceAccount': uploadServiceAccount,
    if (workloadIdentityProvider.isNotEmpty)
      'workloadIdentityProvider': workloadIdentityProvider,
    'permissions': permissions.toList()..sort(),
  };

  JsonMap _serviceAccount() {
    final value = jsonDecode(serviceAccountJson);
    if (value is! Map) {
      throw const FormatException('Service account JSON must be an object.');
    }
    return value.cast<String, Object?>();
  }
}

/// Organization Admin input for one Fleet-managed or customer runner pool.
final class OrganizationRunnerPoolDraft {
  const OrganizationRunnerPoolDraft({
    required this.id,
    required this.name,
    required this.provider,
    required this.capabilities,
    required this.maxCpu,
    required this.maxRamMiB,
    required this.maxConcurrent,
    required this.providerPoolId,
  });

  final String id;
  final String name;
  final String provider;
  final Set<String> capabilities;
  final int maxCpu;
  final int maxRamMiB;
  final int maxConcurrent;
  final String providerPoolId;

  JsonMap toJson() => {
    'name': name,
    'provider': provider,
    'capabilities': capabilities.toList()..sort(),
    'maxCpu': maxCpu,
    'maxRamMiB': maxRamMiB,
    'maxConcurrent': maxConcurrent,
    'providerPoolId': providerPoolId,
  };
}

final class WorkspaceResourceGrantsModel {
  const WorkspaceResourceGrantsModel({
    this.gcp = const [],
    this.github = const [],
    this.runners = const [],
  });

  factory WorkspaceResourceGrantsModel.fromJson(JsonMap workspace) {
    final grants = asJsonMap(workspace['resourceGrants']);
    return WorkspaceResourceGrantsModel(
      gcp: _maps(grants['gcp']).map(WorkspaceGcpGrantModel.fromJson).toList(),
      github: _maps(
        grants['github'],
      ).map(WorkspaceGitHubGrantModel.fromJson).toList(),
      runners: _maps(
        grants['runners'],
      ).map(WorkspaceRunnerGrantModel.fromJson).toList(),
    );
  }

  final List<WorkspaceGcpGrantModel> gcp;
  final List<WorkspaceGitHubGrantModel> github;
  final List<WorkspaceRunnerGrantModel> runners;

  WorkspaceGcpGrantModel? get primaryGcp =>
      gcp.where((item) => item.primary).firstOrNull;

  JsonMap toJson() => {
    'gcp': gcp.map((item) => item.toJson()).toList(),
    'github': github.map((item) => item.toJson()).toList(),
    'runners': runners.map((item) => item.toJson()).toList(),
  };
}

final class WorkspaceGcpGrantModel {
  const WorkspaceGcpGrantModel({
    required this.resourceId,
    required this.permissions,
    required this.primary,
  });

  factory WorkspaceGcpGrantModel.fromJson(JsonMap json) =>
      WorkspaceGcpGrantModel(
        resourceId: json['resourceId']?.toString() ?? '',
        permissions: _strings(json['permissions']).toSet(),
        primary: json['primary'] == true,
      );

  final String resourceId;
  final Set<String> permissions;
  final bool primary;

  JsonMap toJson() => {
    'resourceId': resourceId,
    'permissions': permissions.toList()..sort(),
    'primary': primary,
  };
}

final class WorkspaceGitHubGrantModel {
  const WorkspaceGitHubGrantModel({
    required this.resourceId,
    required this.repositories,
    required this.permissions,
    required this.primary,
  });

  factory WorkspaceGitHubGrantModel.fromJson(JsonMap json) =>
      WorkspaceGitHubGrantModel(
        resourceId: json['resourceId']?.toString() ?? '',
        repositories: _strings(json['repositories']).toSet(),
        permissions: _strings(json['permissions']).toSet(),
        primary: json['primary'] == true,
      );

  final String resourceId;
  final Set<String> repositories;
  final Set<String> permissions;
  final bool primary;

  JsonMap toJson() => {
    'resourceId': resourceId,
    'repositories': repositories.toList()..sort(),
    'permissions': permissions.toList()..sort(),
    'primary': primary,
  };
}

final class WorkspaceRunnerGrantModel {
  const WorkspaceRunnerGrantModel({
    required this.resourceId,
    required this.capabilities,
    required this.maxCpu,
    required this.maxRamMiB,
    required this.maxConcurrent,
    required this.primary,
  });

  factory WorkspaceRunnerGrantModel.fromJson(JsonMap json) =>
      WorkspaceRunnerGrantModel(
        resourceId: json['resourceId']?.toString() ?? '',
        capabilities: _strings(json['capabilities']).toSet(),
        maxCpu: (json['maxCpu'] as num?)?.toInt() ?? 0,
        maxRamMiB: (json['maxRamMiB'] as num?)?.toInt() ?? 0,
        maxConcurrent: (json['maxConcurrent'] as num?)?.toInt() ?? 0,
        primary: json['primary'] == true,
      );

  final String resourceId;
  final Set<String> capabilities;
  final int maxCpu;
  final int maxRamMiB;
  final int maxConcurrent;
  final bool primary;

  JsonMap toJson() => {
    'resourceId': resourceId,
    'capabilities': capabilities.toList()..sort(),
    'maxCpu': maxCpu,
    'maxRamMiB': maxRamMiB,
    'maxConcurrent': maxConcurrent,
    'primary': primary,
  };
}

List<JsonMap> _maps(Object? value) => (value as List<Object?>? ?? const [])
    .map(asJsonMap)
    .where((item) => item.isNotEmpty)
    .toList();

List<String> _strings(Object? value) =>
    (value as List<Object?>? ?? const []).whereType<String>().toList();

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
