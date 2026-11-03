import 'dart:async';

import 'package:stacked/stacked.dart';

import '../models/agent_permission.dart';
import '../models/codex_auth_session.dart';
import '../models/models.dart';
import '../repositories/agent_permissions_repository.dart';
import '../services/api_client.dart';

final class AgentPermissionsViewModel extends BaseViewModel {
  AgentPermissionsViewModel({
    required this.workspaceId,
    required this.repositories,
    required this.repositoryApi,
    required String? initialRepository,
    this.onSelectionChanged,
  }) : repository = repositories.contains(initialRepository)
           ? initialRepository
           : repositories.firstOrNull;

  static const ref = 'dev';

  final String workspaceId;
  final List<String> repositories;
  final AgentPermissionsRepository repositoryApi;
  final void Function(String?, String)? onSelectionChanged;

  String? repository;
  List<AgentPermissionModel> profiles = const [];
  String? errorMessage;
  bool accessNeedsUpdate = false;
  CodexAuthSessionModel? codexSession;
  String? codexError;
  bool startingCodex = false;
  bool installing = false;
  Timer? _codexPoll;
  int _generation = 0;

  bool get hasRecommendedAccess => profiles.any(
    (profile) =>
        profile.id == repositoryMaintainerPermissionId &&
        (profile.runtime.isNotEmpty ||
            profile.version == defaultAgentPermissionVersion),
  );

  List<AgentPermissionModel> get permissionShapes {
    final installedById = {for (final profile in profiles) profile.id: profile};
    final defaults = defaultAgentPermissionJsons()
        .map(AgentPermissionModel.fromJson)
        .map((profile) {
          final installed = installedById.remove(profile.id);
          return installed != null &&
                  (installed.runtime.isNotEmpty ||
                      installed.version == defaultAgentPermissionVersion)
              ? installed
              : profile;
        });
    return [...defaults, ...installedById.values];
  }

  bool isInstalled(AgentPermissionModel profile) => profiles.any(
    (installed) =>
        installed.id == profile.id && installed.version == profile.version,
  );

  bool isDefaultShape(AgentPermissionModel profile) => const {
    repositoryMaintainerPermissionId,
    pullRequestAuthorPermissionId,
    pullRequestReviewerPermissionId,
  }.contains(profile.id);

  Future<void> start() => load();

  Future<void> selectRepository(String? value) async {
    if (repository == value) return;
    _codexPoll?.cancel();
    repository = value;
    codexSession = null;
    codexError = null;
    onSelectionChanged?.call(repository, ref);
    notifyListeners();
    await load();
  }

  Future<void> load() async {
    final selected = repository;
    if (selected == null) return;
    final generation = ++_generation;
    setBusy(true);
    try {
      final next = await repositoryApi.listProfiles(
        workspaceId: workspaceId,
        repository: selected,
      );
      if (generation == _generation) {
        profiles = next;
        errorMessage = null;
        accessNeedsUpdate = false;
      }
    } on Object catch (error) {
      if (generation == _generation) {
        errorMessage = error.toString();
        accessNeedsUpdate = isOutdatedAgentAccess(error);
      }
    } finally {
      if (generation == _generation) setBusy(false);
    }
  }

  Future<bool> install(JsonMap profile) async {
    final selected = repository;
    if (selected == null || installing) return false;
    installing = true;
    errorMessage = null;
    notifyListeners();
    try {
      await repositoryApi.install(
        workspaceId: workspaceId,
        repository: selected,
        profile: profile,
      );
      return true;
    } on Object catch (error) {
      errorMessage = error.toString();
      return false;
    } finally {
      installing = false;
      notifyListeners();
    }
  }

  Future<void> startCodexVerification() async {
    final selected = repository;
    if (selected == null || startingCodex) return;
    final previous = codexSession;
    final reauthenticate =
        previous?.repository == selected &&
        previous?.terminal == true &&
        previous?.status == 'failed' &&
        const {
          'codex_auth_refresh_failed',
          'codex_auth_request_unauthorized',
          'codex_auth_repository_secret_invalid',
        }.contains(previous?.errorCode);
    _codexPoll?.cancel();
    startingCodex = true;
    codexError = null;
    notifyListeners();
    try {
      final session = await repositoryApi.startCodex(
        workspaceId: workspaceId,
        repository: selected,
        reauthenticate: reauthenticate,
      );
      if (selected != repository) return;
      codexSession = session;
      _scheduleCodexPoll(session);
    } on Object catch (error) {
      codexError = error.toString();
    } finally {
      startingCodex = false;
      notifyListeners();
    }
  }

  void _scheduleCodexPoll(CodexAuthSessionModel session) {
    _codexPoll?.cancel();
    if (session.terminal || session.id.isEmpty) {
      if (session.succeeded) load();
      return;
    }
    _codexPoll = Timer(
      const Duration(seconds: 2),
      () => _pollCodexVerification(session.id, session.repository),
    );
  }

  Future<void> _pollCodexVerification(
    String sessionId,
    String expectedRepository,
  ) async {
    if (expectedRepository != repository) return;
    try {
      final session = await repositoryApi.readCodex(
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
      if (expectedRepository != repository) return;
      codexSession = session;
      codexError = null;
      notifyListeners();
      _scheduleCodexPoll(session);
    } on Object catch (error) {
      if (expectedRepository != repository) return;
      codexError = error.toString();
      notifyListeners();
      _codexPoll = Timer(
        const Duration(seconds: 4),
        () => _pollCodexVerification(sessionId, expectedRepository),
      );
    }
  }

  @override
  void dispose() {
    _codexPoll?.cancel();
    super.dispose();
  }
}

extension _FirstAgentPermissionRepositoryOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

bool isOutdatedAgentAccess(Object error) =>
    error is ApiFailure && error.code == 'agent_permission_invalid';
