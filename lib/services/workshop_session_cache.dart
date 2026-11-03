import '../models/models.dart';
import '../models/agent_permission.dart';
import '../models/github_setup_readiness.dart';

final class WorkshopSessionCacheKey {
  const WorkshopSessionCacheKey({
    required this.workspaceId,
    required this.projectId,
    required this.repository,
  });

  final String workspaceId;
  final String projectId;
  final String repository;

  @override
  bool operator ==(Object other) =>
      other is WorkshopSessionCacheKey &&
      other.workspaceId == workspaceId &&
      other.projectId == projectId &&
      other.repository == repository;

  @override
  int get hashCode => Object.hash(workspaceId, projectId, repository);
}

final class WorkshopSessionSnapshot {
  const WorkshopSessionSnapshot({
    required this.projectResponse,
    this.profileResponse,
    this.readinessResponse,
    this.automationError,
  });

  final JsonMap projectResponse;
  final JsonMap? profileResponse;
  final JsonMap? readinessResponse;
  final String? automationError;
}

/// Loads the independent Workshop reads concurrently into one cache snapshot.
///
/// The project board is required. Permission and readiness diagnostics remain
/// optional so either one can fail without hiding the board.
Future<WorkshopSessionSnapshot> loadWorkshopSessionSnapshot({
  required Future<JsonMap> Function() loadProject,
  required Future<JsonMap> Function() loadProfiles,
  required Future<JsonMap> Function() loadReadiness,
}) async {
  final project = loadProject();
  final profiles = _loadOptionalWorkshopResponse(
    loadProfiles,
    failureLabel: 'Permission profiles could not be verified',
  );
  final readiness = _loadOptionalWorkshopResponse(
    loadReadiness,
    failureLabel: 'Agent readiness could not be verified',
  );
  final results = await Future.wait<Object>([project, profiles, readiness]);
  final profileResult = results[1] as _OptionalWorkshopResponse;
  final readinessResult = results[2] as _OptionalWorkshopResponse;
  return WorkshopSessionSnapshot(
    projectResponse: results[0] as JsonMap,
    profileResponse: profileResult.response,
    readinessResponse: readinessResult.response,
    automationError: [
      profileResult.error,
      readinessResult.error,
    ].whereType<String>().join('\n').nullIfEmpty,
  );
}

Future<_OptionalWorkshopResponse> _loadOptionalWorkshopResponse(
  Future<JsonMap> Function() load, {
  required String failureLabel,
}) async {
  try {
    return _OptionalWorkshopResponse(response: await load());
  } on Object catch (error) {
    return _OptionalWorkshopResponse(error: '$failureLabel: $error');
  }
}

final class _OptionalWorkshopResponse {
  const _OptionalWorkshopResponse({this.response, this.error});

  final JsonMap? response;
  final String? error;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

final class WorkshopSessionPresentation {
  WorkshopSessionPresentation.fromSnapshot(WorkshopSessionSnapshot snapshot)
    : project = asJsonMap(snapshot.projectResponse['project']),
      agentDispatches = asJsonMap(
        snapshot.projectResponse['agentDispatches'],
      ).map((key, value) => MapEntry(key, asJsonMap(value))),
      profiles = snapshot.profileResponse == null
          ? const []
          : (snapshot.profileResponse!['profiles'] as List<Object?>? ??
                    const [])
                .map(asJsonMap)
                .map(AgentPermissionModel.fromJson)
                .toList(),
      profilesVerified = snapshot.profileResponse != null,
      automationReadiness = snapshot.readinessResponse == null
          ? null
          : GitHubSetupReadinessModel.fromJson(snapshot.readinessResponse!),
      automationError = snapshot.automationError;

  final JsonMap project;
  final Map<String, JsonMap> agentDispatches;
  final List<AgentPermissionModel> profiles;
  final bool profilesVerified;
  final GitHubSetupReadinessModel? automationReadiness;
  final String? automationError;
}

WorkshopSessionCacheKey? workshopSessionCacheKey({
  required String? workspaceId,
  required String? projectId,
  required String? repository,
}) {
  if (workspaceId == null || projectId == null || repository == null) {
    return null;
  }
  return WorkshopSessionCacheKey(
    workspaceId: workspaceId,
    projectId: projectId,
    repository: repository,
  );
}

/// A small session-local LRU cache for Workshop tab navigation.
///
/// It deliberately has no timer or background refresh. A person refreshes the
/// visible Workshop explicitly, and successful mutations replace the snapshot.
final class WorkshopSessionCache {
  WorkshopSessionCache({this.maxEntries = 8}) : assert(maxEntries > 0);

  final int maxEntries;
  final Map<WorkshopSessionCacheKey, WorkshopSessionSnapshot> _entries = {};

  WorkshopSessionSnapshot? get(WorkshopSessionCacheKey key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void put(WorkshopSessionCacheKey key, WorkshopSessionSnapshot value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
