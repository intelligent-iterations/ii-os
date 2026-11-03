import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/organization_repository.dart';

part 'workspace_resources_view_model_grants.dart';

/// Owns one workspace's explicit subset of its organization resource pool.
final class WorkspaceResourcesViewModel extends BaseViewModel {
  WorkspaceResourcesViewModel({
    required this.organization,
    required this.workspace,
    required this.canManage,
    required this.repository,
    required this.onSaved,
  }) {
    final grants = workspace.resourceGrants;
    for (final grant in grants.gcp) {
      if (_activeGcp(grant.resourceId) != null) {
        _gcpGrants[grant.resourceId] = grant;
      }
    }
    for (final grant in grants.github) {
      if (_activeGitHub(grant.resourceId) != null) {
        _githubGrants[grant.resourceId] = grant;
      }
    }
    for (final grant in grants.runners) {
      if (_activeRunner(grant.resourceId) != null) {
        _runnerGrants[grant.resourceId] = grant;
      }
    }
    final gcp = _gcpGrants.values.where((item) => item.primary).firstOrNull;
    final github = _githubGrants.values
        .where((item) => item.primary)
        .firstOrNull;
    final runner = _runnerGrants.values
        .where((item) => item.primary)
        .firstOrNull;
    gcpId = gcp?.resourceId;
    githubId = github?.resourceId;
    runnerId = runner?.resourceId;
    gcpPermissions = {...?gcp?.permissions};
    githubPermissions = {...?github?.permissions};
    repositories = {...?github?.repositories};
    runnerCapabilities = {...?runner?.capabilities};
    runnerMaxCpu = runner?.maxCpu ?? 0;
    runnerMaxRamMiB = runner?.maxRamMiB ?? 0;
    runnerMaxConcurrent = runner?.maxConcurrent ?? 0;
  }

  final OrganizationAccess organization;
  final WorkspaceModel workspace;
  final bool canManage;
  final OrganizationResourceRepository repository;
  final Future<void> Function() onSaved;

  String? gcpId;
  String? githubId;
  String? runnerId;
  Set<String> gcpPermissions = {};
  Set<String> githubPermissions = {};
  Set<String> repositories = {};
  Set<String> runnerCapabilities = {};
  int runnerMaxCpu = 0;
  int runnerMaxRamMiB = 0;
  int runnerMaxConcurrent = 0;
  String? errorMessage;

  final Map<String, WorkspaceGcpGrantModel> _gcpGrants = {};
  final Map<String, WorkspaceGitHubGrantModel> _githubGrants = {};
  final Map<String, WorkspaceRunnerGrantModel> _runnerGrants = {};

  Set<String> get assignedGcpIds => _gcpGrants.keys.toSet();
  Set<String> get assignedGitHubIds => _githubGrants.keys.toSet();
  Set<String> get assignedRunnerIds => _runnerGrants.keys.toSet();

  OrganizationGcpResourceModel? get selectedGcp => _activeGcp(gcpId);

  OrganizationGitHubResourceModel? get selectedGitHub =>
      _activeGitHub(githubId);

  OrganizationRunnerPoolModel? get selectedRunner => _activeRunner(runnerId);

  bool get runnerSelectionValid {
    final runner = selectedRunner;
    if (runner == null) return runnerId == null;
    return runnerCapabilities.isNotEmpty &&
        runner.capabilities.containsAll(runnerCapabilities) &&
        runnerMaxCpu > 0 &&
        runnerMaxCpu <= runner.maxCpu &&
        runnerMaxRamMiB > 0 &&
        runnerMaxRamMiB <= runner.maxRamMiB &&
        runnerMaxConcurrent > 0 &&
        runnerMaxConcurrent <= runner.maxConcurrent;
  }

  bool get canSave =>
      canManage &&
      (selectedGcp != null || _gcpGrants.isEmpty) &&
      runnerSelectionValid &&
      _allSelectionsValid &&
      !isBusy;

  void selectGcp(String? value) {
    final resource = _activeGcp(value);
    if (resource == null) {
      gcpId = null;
      gcpPermissions = {};
      _gcpGrants.clear();
    } else {
      final existing = _gcpGrants[resource.id];
      gcpId = resource.id;
      gcpPermissions = {...(existing?.permissions ?? resource.permissions)};
      _writeSelectedGcp();
    }
    errorMessage = null;
    notifyListeners();
  }

  void selectGitHub(String? value) {
    final resource = _activeGitHub(value);
    if (resource == null) {
      githubId = null;
      githubPermissions = {};
      repositories = {};
      _githubGrants.clear();
    } else {
      final existing = _githubGrants[resource.id];
      githubId = resource.id;
      githubPermissions = {...?existing?.permissions};
      repositories = {...?existing?.repositories};
      _writeSelectedGitHub();
    }
    errorMessage = null;
    notifyListeners();
  }

  void selectRunner(String? value) {
    final resource = _activeRunner(value);
    if (resource == null) {
      runnerId = null;
      runnerCapabilities = {};
      runnerMaxCpu = 0;
      runnerMaxRamMiB = 0;
      runnerMaxConcurrent = 0;
      _runnerGrants.clear();
    } else {
      final existing = _runnerGrants[resource.id];
      runnerId = resource.id;
      runnerCapabilities = {
        ...(existing?.capabilities ?? resource.capabilities),
      };
      runnerMaxCpu = existing?.maxCpu ?? resource.maxCpu;
      runnerMaxRamMiB = existing?.maxRamMiB ?? resource.maxRamMiB;
      runnerMaxConcurrent = existing?.maxConcurrent ?? resource.maxConcurrent;
      _writeSelectedRunner();
    }
    errorMessage = null;
    notifyListeners();
  }

  void setGcpAssigned(String resourceId, bool assigned) {
    if (resourceId == gcpId) return;
    final resource = _activeGcp(resourceId);
    if (resource == null) return;
    if (assigned) {
      if (gcpId == null) {
        selectGcp(resourceId);
        return;
      }
      _gcpGrants.putIfAbsent(
        resourceId,
        () => WorkspaceGcpGrantModel(
          resourceId: resourceId,
          permissions: resource.permissions,
          primary: false,
        ),
      );
    } else {
      _gcpGrants.remove(resourceId);
    }
    notifyListeners();
  }

  void setGitHubAssigned(String resourceId, bool assigned) {
    if (resourceId == githubId) return;
    final resource = _activeGitHub(resourceId);
    if (resource == null) return;
    if (assigned) {
      if (githubId == null) {
        selectGitHub(resourceId);
        return;
      }
      _githubGrants.putIfAbsent(
        resourceId,
        () => WorkspaceGitHubGrantModel(
          resourceId: resourceId,
          repositories: const {},
          permissions: const {},
          primary: false,
        ),
      );
    } else {
      _githubGrants.remove(resourceId);
    }
    notifyListeners();
  }

  void setRunnerAssigned(String resourceId, bool assigned) {
    if (resourceId == runnerId) return;
    final resource = _activeRunner(resourceId);
    if (resource == null) return;
    if (assigned) {
      if (runnerId == null) {
        selectRunner(resourceId);
        return;
      }
      _runnerGrants.putIfAbsent(
        resourceId,
        () => WorkspaceRunnerGrantModel(
          resourceId: resourceId,
          capabilities: resource.capabilities,
          maxCpu: resource.maxCpu,
          maxRamMiB: resource.maxRamMiB,
          maxConcurrent: resource.maxConcurrent,
          primary: false,
        ),
      );
    } else {
      _runnerGrants.remove(resourceId);
    }
    notifyListeners();
  }

  void setGcpPermissions(Set<String> value) {
    gcpPermissions = value;
    _writeSelectedGcp();
    notifyListeners();
  }

  void setGitHubPermissions(Set<String> value) {
    githubPermissions = value;
    _writeSelectedGitHub();
    notifyListeners();
  }

  void setRepositories(Set<String> value) {
    repositories = value;
    _writeSelectedGitHub();
    notifyListeners();
  }

  void setRunnerCapabilities(Set<String> value) {
    runnerCapabilities = value;
    _writeSelectedRunner();
    notifyListeners();
  }

  void setRunnerMaxCpu(String value) {
    runnerMaxCpu = int.tryParse(value.trim()) ?? 0;
    _writeSelectedRunner();
    notifyListeners();
  }

  void setRunnerMaxRamMiB(String value) {
    runnerMaxRamMiB = int.tryParse(value.trim()) ?? 0;
    _writeSelectedRunner();
    notifyListeners();
  }

  void setRunnerMaxConcurrent(String value) {
    runnerMaxConcurrent = int.tryParse(value.trim()) ?? 0;
    _writeSelectedRunner();
    notifyListeners();
  }

  Future<bool> save() async {
    final gcp = selectedGcp;
    if (!canSave) return false;
    final github = selectedGitHub;
    final runner = selectedRunner;
    errorMessage = null;
    setBusy(true);
    try {
      await repository.saveWorkspaceResourceGrants(
        workspaceId: workspace.id,
        grants: WorkspaceResourceGrantsModel(
          gcp: gcp == null ? const [] : _sortedGcpGrants(gcp.id),
          github: github == null ? const [] : _sortedGitHubGrants(github.id),
          runners: runner == null ? const [] : _sortedRunnerGrants(runner.id),
        ),
      );
      await onSaved();
      return true;
    } on Object {
      errorMessage =
          'Workspace access could not be saved. Review the selected limits '
          'and try again.';
      return false;
    } finally {
      setBusy(false);
    }
  }

  OrganizationGcpResourceModel? _activeGcp(String? id) => organization
      .resources
      .gcp
      .where((item) => item.id == id && item.active)
      .firstOrNull;

  OrganizationGitHubResourceModel? _activeGitHub(String? id) => organization
      .resources
      .github
      .where((item) => item.id == id && item.active)
      .firstOrNull;

  OrganizationRunnerPoolModel? _activeRunner(String? id) => organization
      .resources
      .runners
      .where((item) => item.id == id && item.active)
      .firstOrNull;

  void _writeSelectedGcp() {
    final id = gcpId;
    if (id == null) return;
    _gcpGrants[id] = WorkspaceGcpGrantModel(
      resourceId: id,
      permissions: {...gcpPermissions},
      primary: true,
    );
  }

  void _writeSelectedGitHub() {
    final id = githubId;
    if (id == null) return;
    _githubGrants[id] = WorkspaceGitHubGrantModel(
      resourceId: id,
      repositories: {...repositories},
      permissions: {...githubPermissions},
      primary: true,
    );
  }

  void _writeSelectedRunner() {
    final id = runnerId;
    if (id == null) return;
    _runnerGrants[id] = WorkspaceRunnerGrantModel(
      resourceId: id,
      capabilities: {...runnerCapabilities},
      maxCpu: runnerMaxCpu,
      maxRamMiB: runnerMaxRamMiB,
      maxConcurrent: runnerMaxConcurrent,
      primary: true,
    );
  }

  bool get _allSelectionsValid =>
      _gcpGrants.values.every((grant) {
        final resource = _activeGcp(grant.resourceId);
        return resource != null &&
            resource.permissions.containsAll(grant.permissions);
      }) &&
      _githubGrants.values.every((grant) {
        final resource = _activeGitHub(grant.resourceId);
        return resource != null &&
            resource.permissions.containsAll(grant.permissions) &&
            resource.repositories.containsAll(grant.repositories);
      }) &&
      _runnerGrants.values.every((grant) {
        final resource = _activeRunner(grant.resourceId);
        return resource != null &&
            grant.capabilities.isNotEmpty &&
            resource.capabilities.containsAll(grant.capabilities) &&
            grant.maxCpu > 0 &&
            grant.maxCpu <= resource.maxCpu &&
            grant.maxRamMiB > 0 &&
            grant.maxRamMiB <= resource.maxRamMiB &&
            grant.maxConcurrent > 0 &&
            grant.maxConcurrent <= resource.maxConcurrent;
      });
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
