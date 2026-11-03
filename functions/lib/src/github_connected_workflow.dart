part of 'github_workflow_coordinator.dart';

const editorRenderWorkflowId = 'video-editor-render';
const editorRenderMinimumCpu = 4;
const editorRenderMinimumRamMiB = 8192;
const editorRenderRequiredCapabilities = {
  'runtime-docker',
  'ffmpeg-client-validation',
};

enum ConnectedWorkflowStatus { unknown, unavailable, available }

final class ConnectedWorkflowDiscoveryResult {
  const ConnectedWorkflowDiscoveryResult({
    required this.workflowKey,
    required this.failed,
  });

  final String? workflowKey;
  final bool failed;
}

final class ConnectedWorkflowDiscoveryCache {
  ConnectedWorkflowDiscoveryCache({
    this.ttl = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, _ConnectedWorkflowCacheEntry> _entries = {};

  ConnectedWorkflowDiscoveryResult? read(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!_clock().isBefore(entry.createdAt.add(ttl))) {
      _entries.remove(key);
      return null;
    }
    return entry.discovery;
  }

  void write(String key, ConnectedWorkflowDiscoveryResult discovery) {
    _entries[key] = _ConnectedWorkflowCacheEntry(
      discovery: discovery,
      createdAt: _clock(),
    );
  }
}

final class _ConnectedWorkflowCacheEntry {
  const _ConnectedWorkflowCacheEntry({
    required this.discovery,
    required this.createdAt,
  });

  final ConnectedWorkflowDiscoveryResult discovery;
  final DateTime createdAt;
}

/// A stable workflow route exists; Fleet still decides momentary placement.
final class ConnectedWorkflowCapability {
  const ConnectedWorkflowCapability({required this.status, this.workflowKey});

  final ConnectedWorkflowStatus status;

  /// Server-owned provider identity. It is deliberately omitted from JSON.
  final String? workflowKey;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'requiredCapabilities': editorRenderRequiredCapabilities.toList()..sort(),
    'minimumCpu': editorRenderMinimumCpu,
    'minimumRamMiB': editorRenderMinimumRamMiB,
  };
}

/// Applies the product resource ceiling after provider discovery.
ConnectedWorkflowCapability evaluateEditorRenderCapability({
  required Workspace workspace,
  String? workflowKey,
  bool discoveryFailed = false,
}) {
  if (workflowKey == null) {
    return ConnectedWorkflowCapability(
      status: discoveryFailed
          ? ConnectedWorkflowStatus.unknown
          : ConnectedWorkflowStatus.unavailable,
    );
  }
  if (!workspace.resourceGrantsExplicit) {
    return ConnectedWorkflowCapability(
      status: ConnectedWorkflowStatus.available,
      workflowKey: workflowKey,
    );
  }

  final grants = workspace.resourceGrants.runners
      .where((grant) => grant.primary)
      .toList(growable: false);
  final grant = grants.length == 1 ? grants.single : null;
  final pool = grant == null
      ? null
      : workspace.organizationResources.runner(grant.resourceId);
  final compatible =
      grant != null &&
      pool != null &&
      pool.active &&
      grant.maxCpu >= editorRenderMinimumCpu &&
      grant.maxRamMiB >= editorRenderMinimumRamMiB &&
      pool.maxCpu >= editorRenderMinimumCpu &&
      pool.maxRamMiB >= editorRenderMinimumRamMiB &&
      grant.capabilities.containsAll(editorRenderRequiredCapabilities) &&
      pool.capabilities.containsAll(editorRenderRequiredCapabilities);
  return ConnectedWorkflowCapability(
    status: compatible
        ? ConnectedWorkflowStatus.available
        : ConnectedWorkflowStatus.unavailable,
    workflowKey: compatible ? workflowKey : null,
  );
}

extension ConnectedWorkflowDiscovery on GitHubWorkflowCoordinator {
  /// Finds an active editor-render workflow in a workspace-owned repository.
  ///
  /// Repository checks run concurrently and do not read Firestore. A provider
  /// outage stays distinct from a confirmed absence so the UI never claims
  /// that an unknown runner route is unavailable.
  Future<ConnectedWorkflowCapability> discoverEditorRenderCapability(
    Workspace workspace,
  ) async {
    final repositories = workspace.repositories.toList()..sort();
    if (repositories.isEmpty) {
      return evaluateEditorRenderCapability(workspace: workspace);
    }
    final cacheKey = [
      workspace.id,
      '${workspace.githubInstallationId}',
      ...repositories,
    ].join('\n');
    var discovery = connectedWorkflowCache.read(cacheKey);
    if (discovery == null) {
      final discoveries = await Future.wait([
        for (final repository in repositories)
          _discoverEditorRenderWorkflow(workspace, repository),
      ]);
      final workflowKeys =
          discoveries
              .where((item) => item.workflowKey != null)
              .map((item) => item.workflowKey!)
              .toList()
            ..sort();
      discovery = ConnectedWorkflowDiscoveryResult(
        workflowKey: workflowKeys.firstOrNull,
        failed: discoveries.any((item) => item.failed),
      );
      connectedWorkflowCache.write(cacheKey, discovery);
    }
    return evaluateEditorRenderCapability(
      workspace: workspace,
      workflowKey: discovery.workflowKey,
      discoveryFailed: discovery.failed,
    );
  }

  Future<({String? workflowKey, bool failed})> _discoverEditorRenderWorkflow(
    Workspace workspace,
    String repository,
  ) async {
    try {
      final catalog = await _readCatalog(workspace, repository);
      return (
        workflowKey: catalog.find(editorRenderWorkflowId) == null
            ? null
            : workflowKey(repository, editorRenderWorkflowId),
        failed: false,
      );
    } on ApiError catch (error) {
      final confirmedAbsent =
          error.code == 'github_resource_not_found' ||
          error.code == 'workflow_catalog_invalid';
      return (workflowKey: null, failed: !confirmedAbsent);
    }
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
