import 'dart:convert';

import 'data_plane_connection.dart';

part 'organization_legacy_resource_promotion.dart';

const organizationResourceCatalogVersion = 1;
const defaultGcpResourceId = 'gcp_primary';
const defaultGithubResourceId = 'github_primary';
const legacyGcpResourceId = 'gcp_legacy_primary';
const legacyGithubResourceId = 'github_legacy_primary';
const maxOrganizationGcpResources = 20;
const maxOrganizationGithubResources = 20;
const maxOrganizationRunnerPools = 20;
const maxOrganizationResourceRepositories = 500;
const maxOrganizationResourceCatalogBytes = 700 * 1024;

const gcpResourcePermissions = {
  'assets.read',
  'assets.write',
  'workflows.upload',
};
const githubResourcePermissions = {
  'actions:read',
  'actions:write',
  'administration:read',
  'contents:read',
  'contents:write',
  'deployments:read',
  'issues:read',
  'issues:write',
  'organization_projects:read',
  'organization_projects:write',
  'pull_requests:read',
  'pull_requests:write',
  'secrets:read',
  'secrets:write',
};
const legacyGitHubMigrationPermissions = {
  'actions:write',
  'contents:write',
  'deployments:read',
  'pull_requests:write',
};
const legacyGitHubWorkshopPermissions = {
  'issues:write',
  'organization_projects:write',
};

Set<String> githubPermissionEnvelope(Map<String, String> permissions) {
  final result = <String>{};
  for (final entry in permissions.entries) {
    if (entry.value != 'read' && entry.value != 'write') continue;
    final value = '${entry.key}:${entry.value}';
    if (githubResourcePermissions.contains(value)) result.add(value);
  }
  if (result.isEmpty) throw const FormatException();
  return result;
}

bool isUnderScopedLegacyGitHubMigration(Set<String> permissions) {
  const required = {'actions:write', 'contents:write', 'pull_requests:write'};
  return permissions.containsAll(required) &&
      permissions.difference(legacyGitHubMigrationPermissions).isEmpty;
}

/// Nonsecret infrastructure and provider resources owned by one organization.
final class OrganizationResourceCatalog {
  const OrganizationResourceCatalog({
    required this.gcpResources,
    required this.githubResources,
    required this.runnerPools,
  });

  const OrganizationResourceCatalog.empty()
    : gcpResources = const [],
      githubResources = const [],
      runnerPools = const [];

  factory OrganizationResourceCatalog.fromOrganizationData(
    String organizationId,
    Map<String, Object?> data, {
    required bool emulated,
  }) {
    if (data['resourceCatalogVersion'] == organizationResourceCatalogVersion) {
      return _restoreLegacyGitHubCatalogPermissions(
        OrganizationResourceCatalog(
          gcpResources: _maps(data['gcpResources'])
              .map(
                (json) =>
                    OrganizationGcpResource.fromJson(json, emulated: emulated),
              )
              .toList(),
          githubResources: _maps(
            data['githubResources'],
          ).map(OrganizationGitHubResource.fromJson).toList(),
          runnerPools: _maps(
            data['runnerPools'],
          ).map(OrganizationRunnerPool.fromJson).toList(),
        ),
      );
    }
    return _legacyCatalog(organizationId, data, emulated: emulated);
  }

  final List<OrganizationGcpResource> gcpResources;
  final List<OrganizationGitHubResource> githubResources;
  final List<OrganizationRunnerPool> runnerPools;

  bool get isEmpty =>
      gcpResources.isEmpty && githubResources.isEmpty && runnerPools.isEmpty;

  OrganizationGcpResource? gcp(String id) =>
      gcpResources.where((item) => item.id == id).firstOrNull;

  OrganizationGitHubResource? github(String id) =>
      githubResources.where((item) => item.id == id).firstOrNull;

  OrganizationRunnerPool? runner(String id) =>
      runnerPools.where((item) => item.id == id).firstOrNull;

  OrganizationResourceCatalog upsertGcp(OrganizationGcpResource resource) =>
      OrganizationResourceCatalog(
        gcpResources: _upsert(gcpResources, resource, (item) => item.id),
        githubResources: githubResources,
        runnerPools: runnerPools,
      );

  OrganizationResourceCatalog upsertGitHub(
    OrganizationGitHubResource resource,
  ) => OrganizationResourceCatalog(
    gcpResources: gcpResources,
    githubResources: _upsert(githubResources, resource, (item) => item.id),
    runnerPools: runnerPools,
  );

  OrganizationResourceCatalog upsertRunner(OrganizationRunnerPool resource) =>
      OrganizationResourceCatalog(
        gcpResources: gcpResources,
        githubResources: githubResources,
        runnerPools: _upsert(runnerPools, resource, (item) => item.id),
      );

  OrganizationResourceCatalog upsertRunners(
    Iterable<OrganizationRunnerPool> resources,
  ) {
    var updated = this;
    for (final resource in resources) {
      updated = updated.upsertRunner(resource);
    }
    return updated;
  }

  Set<String> validateForOrganization(String organizationId) {
    final errors = validate();
    if (gcpResources.any((resource) => !resource.isOwnedBy(organizationId))) {
      errors.add('gcp_resource_organization_mismatch');
    }
    return errors;
  }

  Set<String> validate() {
    final errors = <String>{};
    if (gcpResources.length > maxOrganizationGcpResources) {
      errors.add('too_many_gcp_resources');
    }
    if (githubResources.length > maxOrganizationGithubResources) {
      errors.add('too_many_github_resources');
    }
    if (runnerPools.length > maxOrganizationRunnerPools) {
      errors.add('too_many_runner_pools');
    }
    _validateUniqueIds(gcpResources.map((item) => item.id), errors, 'gcp');
    _validateUniqueIds(
      githubResources.map((item) => item.id),
      errors,
      'github',
    );
    _validateUniqueIds(runnerPools.map((item) => item.id), errors, 'runner');

    for (final resource in gcpResources) {
      if (!_resourceId.hasMatch(resource.id) || !_validName(resource.name)) {
        errors.add('invalid_gcp_resource');
      }
      if (!gcpResourcePermissions.containsAll(resource.permissionEnvelope)) {
        errors.add('invalid_gcp_permission_envelope');
      }
      if ((!resource.connection.isOrganizationBound &&
              !resource.isLegacyWorkspacePromotion) ||
          resource.connection.configurationChecks().any(
            (check) => !check.passed,
          )) {
        errors.add('invalid_gcp_connection');
      }
    }

    for (final resource in githubResources) {
      if (!_resourceId.hasMatch(resource.id) ||
          !_validName(resource.name) ||
          !_positiveId.hasMatch(resource.appId) ||
          resource.installationId <= 0 ||
          !githubResourcePermissions.containsAll(resource.permissionEnvelope)) {
        errors.add('invalid_github_resource');
      }
      final gcpResource = gcp(resource.secretGcpResourceId);
      if (gcpResource == null) {
        errors.add('github_secret_gcp_resource_missing');
      } else if (!_secretBelongsToProject(
        resource.privateKeySecret,
        gcpResource.connection.projectId,
        gcpResource.connection.projectNumber,
      )) {
        errors.add('github_secret_project_mismatch');
      }
      if (resource.repositories.any((name) => !_repository.hasMatch(name))) {
        errors.add('invalid_github_repository');
      }
    }

    final repositoryCount = githubResources.fold<int>(
      0,
      (total, item) => total + item.repositories.length,
    );
    if (repositoryCount > maxOrganizationResourceRepositories) {
      errors.add('too_many_organization_repositories');
    }

    for (final pool in runnerPools) {
      if (!_resourceId.hasMatch(pool.id) ||
          !_validName(pool.name) ||
          !const {'fleet', 'customer'}.contains(pool.provider) ||
          (pool.providerPoolId.isNotEmpty &&
              !_providerPoolId.hasMatch(pool.providerPoolId)) ||
          pool.capabilities.isEmpty ||
          pool.capabilities.any((item) => !_capability.hasMatch(item)) ||
          pool.maxCpu <= 0 ||
          pool.maxRamMiB <= 0 ||
          pool.maxConcurrent <= 0) {
        errors.add('invalid_runner_pool');
      }
    }

    if (utf8.encode(jsonEncode(toJson())).length >
        maxOrganizationResourceCatalogBytes) {
      errors.add('organization_resource_catalog_too_large');
    }
    return errors;
  }

  Map<String, Object?> toJson() => {
    'resourceCatalogVersion': organizationResourceCatalogVersion,
    'gcpResources': gcpResources.map((item) => item.toJson()).toList(),
    'githubResources': githubResources.map((item) => item.toJson()).toList(),
    'runnerPools': runnerPools.map((item) => item.toJson()).toList(),
  };
}

final class OrganizationGcpResource {
  const OrganizationGcpResource({
    required this.id,
    required this.name,
    required this.connection,
    required this.permissionEnvelope,
    this.legacySourceWorkspaceId = '',
    this.active = true,
  });

  factory OrganizationGcpResource.fromJson(
    Map<String, Object?> json, {
    required bool emulated,
  }) => OrganizationGcpResource(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    connection: DataPlaneConnection.fromJson(
      _map(json['connection']),
      emulated: emulated,
    ),
    permissionEnvelope: _strings(json['permissionEnvelope']),
    legacySourceWorkspaceId: _string(json, 'legacySourceWorkspaceId'),
    active: json['active'] != false,
  );

  final String id;
  final String name;
  final DataPlaneConnection connection;
  final Set<String> permissionEnvelope;
  final String legacySourceWorkspaceId;
  final bool active;

  bool get isLegacyWorkspacePromotion =>
      id == legacyGcpResourceId &&
      legacySourceWorkspaceId.isNotEmpty &&
      !connection.isOrganizationBound &&
      connection.workspaceId == legacySourceWorkspaceId;

  bool isOwnedBy(String organizationId) =>
      (connection.isOrganizationBound &&
          connection.organizationId == organizationId) ||
      isLegacyWorkspacePromotion;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'connection': connection.toJson(),
    'permissionEnvelope': permissionEnvelope.toList()..sort(),
    if (legacySourceWorkspaceId.isNotEmpty)
      'legacySourceWorkspaceId': legacySourceWorkspaceId,
    'active': active,
  };
}

/// Adds deterministic catalog references for a workspace-owned V1 connection.
///
/// The connection and Secret Manager reference are preserved byte-for-byte.
/// The source workspace remains the anti-substitution binding until the legacy
/// resource is rotated through organization bootstrap.
final class OrganizationGitHubResource {
  const OrganizationGitHubResource({
    required this.id,
    required this.name,
    required this.secretGcpResourceId,
    required this.appId,
    required this.privateKeySecret,
    required this.installationId,
    required this.repositories,
    required this.permissionEnvelope,
    this.active = true,
  });

  factory OrganizationGitHubResource.fromJson(Map<String, Object?> json) =>
      OrganizationGitHubResource(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        secretGcpResourceId: _string(json, 'secretGcpResourceId'),
        appId: _string(json, 'appId'),
        privateKeySecret: _string(json, 'privateKeySecret'),
        installationId: (json['installationId'] as num?)?.toInt() ?? 0,
        repositories: _strings(json['repositories']),
        permissionEnvelope: _strings(json['permissionEnvelope']),
        active: json['active'] != false,
      );

  final String id;
  final String name;
  final String secretGcpResourceId;
  final String appId;
  final String privateKeySecret;
  final int installationId;
  final Set<String> repositories;
  final Set<String> permissionEnvelope;
  final bool active;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'secretGcpResourceId': secretGcpResourceId,
    'appId': appId,
    'privateKeySecret': privateKeySecret,
    'installationId': installationId,
    'repositories': repositories.toList()..sort(),
    'permissionEnvelope': permissionEnvelope.toList()..sort(),
    'active': active,
  };
}

final class OrganizationRunnerPool {
  const OrganizationRunnerPool({
    required this.id,
    required this.name,
    required this.provider,
    required this.capabilities,
    required this.maxCpu,
    required this.maxRamMiB,
    required this.maxConcurrent,
    this.providerPoolId = '',
    this.active = true,
  });

  factory OrganizationRunnerPool.fromJson(Map<String, Object?> json) =>
      OrganizationRunnerPool(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        provider: _string(json, 'provider'),
        capabilities: _strings(json['capabilities']),
        maxCpu: (json['maxCpu'] as num?)?.toInt() ?? 0,
        maxRamMiB: (json['maxRamMiB'] as num?)?.toInt() ?? 0,
        maxConcurrent: (json['maxConcurrent'] as num?)?.toInt() ?? 0,
        providerPoolId: _string(json, 'providerPoolId'),
        active: json['active'] != false,
      );

  final String id;
  final String name;
  final String provider;
  final Set<String> capabilities;
  final int maxCpu;
  final int maxRamMiB;
  final int maxConcurrent;
  final String providerPoolId;
  final bool active;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'provider': provider,
    'capabilities': capabilities.toList()..sort(),
    'maxCpu': maxCpu,
    'maxRamMiB': maxRamMiB,
    'maxConcurrent': maxConcurrent,
    if (providerPoolId.isNotEmpty) 'providerPoolId': providerPoolId,
    'active': active,
  };
}

/// Why an Organization Admin cannot save [pool] by hand, or null.
///
/// A `fleet` pool's provider pool id is what placement enforces, so it comes
/// only from the organization's own capacity report through sync. A pool kept
/// by hand is therefore always `customer`, and it never replaces a reported
/// pool that happens to share its id.
String? manualRunnerPoolRefusal(
  OrganizationResourceCatalog catalog,
  OrganizationRunnerPool pool,
) {
  if (pool.provider != 'customer') return 'runner_provider_not_manual';
  final existing = catalog.runner(pool.id);
  if (existing != null && existing.provider != 'customer') {
    return 'runner_pool_reported';
  }
  return null;
}

OrganizationResourceCatalog _legacyCatalog(
  String organizationId,
  Map<String, Object?> data, {
  required bool emulated,
}) {
  DataPlaneConnection? connection;
  try {
    final raw = data['connection'];
    if (raw is Map) {
      final parsed = DataPlaneConnection.fromJson(
        raw.cast<String, Object?>(),
        emulated: emulated,
      );
      if (parsed.isOrganizationBound &&
          parsed.organizationId == organizationId) {
        connection = parsed;
      }
    }
  } on FormatException {
    connection = null;
  }
  if (connection == null) return const OrganizationResourceCatalog.empty();
  final installationId = (data['githubInstallationId'] as num?)?.toInt();
  final repositories = _strings(data['repositories']);
  return OrganizationResourceCatalog(
    gcpResources: [
      OrganizationGcpResource(
        id: legacyGcpResourceId,
        name: 'Primary GCP project',
        connection: connection,
        permissionEnvelope: gcpResourcePermissions,
      ),
    ],
    githubResources:
        installationId != null &&
            installationId > 0 &&
            connection.githubAppId.isNotEmpty &&
            connection.githubAppSecret.isNotEmpty
        ? [
            OrganizationGitHubResource(
              id: legacyGithubResourceId,
              name: 'Primary GitHub App',
              secretGcpResourceId: legacyGcpResourceId,
              appId: connection.githubAppId,
              privateKeySecret: connection.githubAppSecret,
              installationId: installationId,
              repositories: repositories,
              permissionEnvelope: legacyGitHubMigrationPermissions,
            ),
          ]
        : const [],
    runnerPools: const [],
  );
}

OrganizationResourceCatalog _restoreLegacyGitHubCatalogPermissions(
  OrganizationResourceCatalog catalog,
) {
  final gcp = catalog.gcp(legacyGcpResourceId);
  final github = catalog.github(legacyGithubResourceId);
  if (gcp?.isLegacyWorkspacePromotion != true ||
      github == null ||
      !isUnderScopedLegacyGitHubMigration(github.permissionEnvelope)) {
    return catalog;
  }
  return catalog.upsertGitHub(
    OrganizationGitHubResource(
      id: github.id,
      name: github.name,
      secretGcpResourceId: github.secretGcpResourceId,
      appId: github.appId,
      privateKeySecret: github.privateKeySecret,
      installationId: github.installationId,
      repositories: github.repositories,
      permissionEnvelope: {
        ...github.permissionEnvelope,
        ...legacyGitHubWorkshopPermissions,
      },
      active: github.active,
    ),
  );
}

void _validateUniqueIds(Iterable<String> ids, Set<String> errors, String kind) {
  final values = ids.toList();
  if (values.toSet().length != values.length) {
    errors.add('duplicate_${kind}_resource');
  }
}

List<T> _upsert<T>(List<T> values, T replacement, String Function(T) id) => [
  for (final value in values)
    if (id(value) != id(replacement)) value,
  replacement,
];

bool _validName(String value) => value.isNotEmpty && value.length <= 100;

bool _secretBelongsToProject(String value, String projectId, String number) {
  final parts = value.split('/');
  return parts.length == 4 &&
      parts[0] == 'projects' &&
      parts[2] == 'secrets' &&
      (parts[1] == projectId || parts[1] == number);
}

String _string(Map<String, Object?> json, String key) =>
    json[key]?.toString().trim() ?? '';

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

List<Map<String, Object?>> _maps(Object? value) => value is List<Object?>
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.cast<String, Object?>())
          .toList()
    : const [];

Set<String> _strings(Object? value) => value is List<Object?>
    ? value.whereType<String>().map((item) => item.trim()).toSet()
    : const {};

final _resourceId = RegExp(r'^[a-z][a-z0-9_]{2,63}$');
final _positiveId = RegExp(r'^[1-9][0-9]{0,19}$');
final _repository = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$',
);
final _capability = RegExp(r'^[a-z0-9][a-z0-9._-]{1,99}$');
final _providerPoolId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
