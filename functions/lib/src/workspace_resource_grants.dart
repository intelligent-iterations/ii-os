import 'organization_resources.dart';

const workspaceResourceGrantVersion = 1;
const maxWorkspaceResourceGrantsPerKind = 20;

/// References to organization resources, always narrower than their envelope.
final class WorkspaceResourceGrants {
  const WorkspaceResourceGrants({
    required this.gcp,
    required this.github,
    required this.runners,
  });

  const WorkspaceResourceGrants.empty()
    : gcp = const [],
      github = const [],
      runners = const [];

  factory WorkspaceResourceGrants.fromWorkspaceData(
    Map<String, Object?> data,
    OrganizationResourceCatalog catalog, {
    String workspaceId = '',
  }) {
    if (data['resourceGrantVersion'] == workspaceResourceGrantVersion) {
      final raw = _map(data['resourceGrants']);
      final parsed = WorkspaceResourceGrants(
        gcp: _maps(raw['gcp']).map(WorkspaceGcpGrant.fromJson).toList(),
        github: _maps(
          raw['github'],
        ).map(WorkspaceGitHubGrant.fromJson).toList(),
        runners: _maps(
          raw['runners'],
        ).map(WorkspaceRunnerGrant.fromJson).toList(),
      );
      return _restoreLegacySourceGitHubGrant(
        parsed,
        data: data,
        catalog: catalog,
        workspaceId: workspaceId,
      );
    }
    return _legacyGrants(data, catalog);
  }

  final List<WorkspaceGcpGrant> gcp;
  final List<WorkspaceGitHubGrant> github;
  final List<WorkspaceRunnerGrant> runners;

  bool get isEmpty => gcp.isEmpty && github.isEmpty && runners.isEmpty;

  Set<String> validateAgainst(OrganizationResourceCatalog catalog) {
    final errors = <String>{};
    if (gcp.length > maxWorkspaceResourceGrantsPerKind ||
        github.length > maxWorkspaceResourceGrantsPerKind ||
        runners.length > maxWorkspaceResourceGrantsPerKind) {
      errors.add('too_many_workspace_resource_grants');
    }
    _validatePrimary(gcp, errors, 'gcp');
    _validatePrimary(github, errors, 'github');
    _validatePrimary(runners, errors, 'runner');
    _validateUnique(gcp.map((item) => item.resourceId), errors, 'gcp');
    _validateUnique(github.map((item) => item.resourceId), errors, 'github');
    _validateUnique(runners.map((item) => item.resourceId), errors, 'runner');

    for (final grant in gcp) {
      final resource = catalog.gcp(grant.resourceId);
      if (resource == null || !resource.active) {
        errors.add('gcp_resource_unavailable');
      } else if (!resource.permissionEnvelope.containsAll(grant.permissions)) {
        errors.add('gcp_permission_outside_organization');
      }
    }
    for (final grant in github) {
      final resource = catalog.github(grant.resourceId);
      if (resource == null || !resource.active) {
        errors.add('github_resource_unavailable');
        continue;
      }
      if (!resource.repositories.containsAll(grant.repositories)) {
        errors.add('github_repository_outside_organization');
      }
      if (!resource.permissionEnvelope.containsAll(grant.permissions)) {
        errors.add('github_permission_outside_organization');
      }
    }
    for (final grant in runners) {
      final resource = catalog.runner(grant.resourceId);
      if (resource == null || !resource.active) {
        errors.add('runner_pool_unavailable');
        continue;
      }
      if (grant.capabilities.isEmpty ||
          !resource.capabilities.containsAll(grant.capabilities)) {
        errors.add('runner_capability_outside_organization');
      }
      if (grant.maxCpu > resource.maxCpu ||
          grant.maxRamMiB > resource.maxRamMiB ||
          grant.maxConcurrent > resource.maxConcurrent ||
          grant.maxCpu <= 0 ||
          grant.maxRamMiB <= 0 ||
          grant.maxConcurrent <= 0) {
        errors.add('runner_capacity_outside_organization');
      }
    }
    return errors;
  }

  OrganizationGcpResource? primaryGcp(OrganizationResourceCatalog catalog) {
    final grant = gcp.where((item) => item.primary).firstOrNull;
    return grant == null ? null : catalog.gcp(grant.resourceId);
  }

  OrganizationGitHubResource? primaryGitHub(
    OrganizationResourceCatalog catalog,
  ) {
    final grant = github.where((item) => item.primary).firstOrNull;
    return grant == null ? null : catalog.github(grant.resourceId);
  }

  WorkspaceGitHubGrant? primaryGitHubGrant() =>
      github.where((item) => item.primary).firstOrNull;

  bool allowsRepository(
    OrganizationResourceCatalog catalog,
    String repository,
  ) {
    final grant = primaryGitHubGrant();
    if (grant == null) return false;
    final resource = catalog.github(grant.resourceId);
    return resource?.active == true &&
        resource!.repositories.contains(repository) &&
        grant.repositories.contains(repository);
  }

  bool allowsGitHubPermission(
    OrganizationResourceCatalog catalog,
    String permission, {
    String? repository,
  }) {
    final grant = primaryGitHubGrant();
    if (grant == null || !grant.permissions.contains(permission)) return false;
    final resource = catalog.github(grant.resourceId);
    if (resource?.active != true ||
        !resource!.permissionEnvelope.contains(permission)) {
      return false;
    }
    return repository == null ||
        (resource.repositories.contains(repository) &&
            grant.repositories.contains(repository));
  }

  Map<String, Object?> toJson() => {
    'resourceGrantVersion': workspaceResourceGrantVersion,
    'resourceGrants': {
      'gcp': gcp.map((item) => item.toJson()).toList(),
      'github': github.map((item) => item.toJson()).toList(),
      'runners': runners.map((item) => item.toJson()).toList(),
    },
  };
}

WorkspaceResourceGrants _restoreLegacySourceGitHubGrant(
  WorkspaceResourceGrants grants, {
  required Map<String, Object?> data,
  required OrganizationResourceCatalog catalog,
  required String workspaceId,
}) {
  final sourceWorkspaceId = catalog
      .gcp(legacyGcpResourceId)
      ?.legacySourceWorkspaceId;
  final hasWorkshop = _maps(data['projects']).isNotEmpty;
  if (workspaceId.isEmpty || workspaceId != sourceWorkspaceId || !hasWorkshop) {
    return grants;
  }
  return WorkspaceResourceGrants(
    gcp: grants.gcp,
    github: grants.github.map((grant) {
      final resource = catalog.github(grant.resourceId);
      if (grant.resourceId != legacyGithubResourceId ||
          resource?.active != true ||
          !isUnderScopedLegacyGitHubMigration(grant.permissions)) {
        return grant;
      }
      return WorkspaceGitHubGrant(
        resourceId: grant.resourceId,
        repositories: grant.repositories,
        // Promotion persists GitHub's exact accepted permission envelope on
        // the organization resource. The source workspace used that envelope
        // before workspace token scopes existed, so preserve it here without
        // hard-coding or widening beyond what GitHub actually granted.
        permissions: {...grant.permissions, ...resource!.permissionEnvelope},
        primary: grant.primary,
      );
    }).toList(),
    runners: grants.runners,
  );
}

abstract interface class WorkspaceResourceGrant {
  String get resourceId;
  bool get primary;
}

final class WorkspaceGcpGrant implements WorkspaceResourceGrant {
  const WorkspaceGcpGrant({
    required this.resourceId,
    required this.permissions,
    required this.primary,
  });

  factory WorkspaceGcpGrant.fromJson(Map<String, Object?> json) =>
      WorkspaceGcpGrant(
        resourceId: _string(json, 'resourceId'),
        permissions: _strings(json['permissions']),
        primary: json['primary'] == true,
      );

  @override
  final String resourceId;
  final Set<String> permissions;
  @override
  final bool primary;

  Map<String, Object?> toJson() => {
    'resourceId': resourceId,
    'permissions': permissions.toList()..sort(),
    'primary': primary,
  };
}

final class WorkspaceGitHubGrant implements WorkspaceResourceGrant {
  const WorkspaceGitHubGrant({
    required this.resourceId,
    required this.repositories,
    required this.permissions,
    required this.primary,
  });

  factory WorkspaceGitHubGrant.fromJson(Map<String, Object?> json) =>
      WorkspaceGitHubGrant(
        resourceId: _string(json, 'resourceId'),
        repositories: _strings(json['repositories']),
        permissions: _strings(json['permissions']),
        primary: json['primary'] == true,
      );

  @override
  final String resourceId;
  final Set<String> repositories;
  final Set<String> permissions;
  @override
  final bool primary;

  Map<String, Object?> toJson() => {
    'resourceId': resourceId,
    'repositories': repositories.toList()..sort(),
    'permissions': permissions.toList()..sort(),
    'primary': primary,
  };
}

final class WorkspaceRunnerGrant implements WorkspaceResourceGrant {
  const WorkspaceRunnerGrant({
    required this.resourceId,
    required this.capabilities,
    required this.maxCpu,
    required this.maxRamMiB,
    required this.maxConcurrent,
    required this.primary,
  });

  factory WorkspaceRunnerGrant.fromJson(Map<String, Object?> json) =>
      WorkspaceRunnerGrant(
        resourceId: _string(json, 'resourceId'),
        capabilities: _strings(json['capabilities']),
        maxCpu: (json['maxCpu'] as num?)?.toInt() ?? 0,
        maxRamMiB: (json['maxRamMiB'] as num?)?.toInt() ?? 0,
        maxConcurrent: (json['maxConcurrent'] as num?)?.toInt() ?? 0,
        primary: json['primary'] == true,
      );

  @override
  final String resourceId;
  final Set<String> capabilities;
  final int maxCpu;
  final int maxRamMiB;
  final int maxConcurrent;
  @override
  final bool primary;

  Map<String, Object?> toJson() => {
    'resourceId': resourceId,
    'capabilities': capabilities.toList()..sort(),
    'maxCpu': maxCpu,
    'maxRamMiB': maxRamMiB,
    'maxConcurrent': maxConcurrent,
    'primary': primary,
  };
}

WorkspaceResourceGrants _legacyGrants(
  Map<String, Object?> data,
  OrganizationResourceCatalog catalog,
) {
  final gcp = catalog.gcpResources.where((item) => item.active).firstOrNull;
  final github = catalog.githubResources
      .where((item) => item.active)
      .firstOrNull;
  final repositories = _strings(data['repositories']);
  return WorkspaceResourceGrants(
    gcp: gcp == null
        ? const []
        : [
            WorkspaceGcpGrant(
              resourceId: gcp.id,
              permissions: gcp.permissionEnvelope,
              primary: true,
            ),
          ],
    github: github == null
        ? const []
        : [
            WorkspaceGitHubGrant(
              resourceId: github.id,
              repositories: repositories.intersection(github.repositories),
              permissions: github.permissionEnvelope,
              primary: true,
            ),
          ],
    runners: const [],
  );
}

void _validatePrimary<T extends WorkspaceResourceGrant>(
  List<T> grants,
  Set<String> errors,
  String kind,
) {
  final primaryCount = grants.where((item) => item.primary).length;
  if (grants.isNotEmpty && primaryCount != 1) {
    errors.add(
      primaryCount > 1 ? 'multiple_primary_$kind' : 'missing_primary_$kind',
    );
  }
}

void _validateUnique(Iterable<String> ids, Set<String> errors, String kind) {
  final values = ids.toList();
  if (values.toSet().length != values.length) {
    errors.add('duplicate_${kind}_grant');
  }
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
