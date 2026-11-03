import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/interactive_session_repository.dart';

final class InteractiveSessionsViewModel extends BaseViewModel {
  InteractiveSessionsViewModel({
    required this._sessions,
    required this.workspaceId,
  });

  final InteractiveSessionRepository _sessions;
  final String workspaceId;
  List<InteractiveSessionModel> sessions = const [];
  List<InteractiveRunnerPoolOption> runnerPools = const [];
  String? errorMessage;

  bool get showLoadingSurface => isBusy && sessions.isEmpty;

  Future<void> start() => load();

  Future<void> load() async {
    if (isBusy) return;
    setBusy(true);
    try {
      final page = await _sessions.list(workspaceId);
      sessions = page.sessions;
      runnerPools = page.runnerPools;
      errorMessage = null;
    } on Object catch (error) {
      errorMessage = _sessionMessage(
        error,
        'Terminal sessions could not be loaded. Try again.',
      );
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  Future<InteractiveSessionModel?> create(String runnerResourceId) async {
    if (isBusy) return null;
    setBusy(true);
    try {
      final created = await _sessions.create(
        workspaceId,
        runnerResourceId: runnerResourceId,
      );
      sessions = [created.session, ...sessions];
      errorMessage = null;
      return created.session;
    } on Object catch (error) {
      errorMessage = _sessionMessage(
        error,
        'The terminal session could not be created. Try again.',
      );
      return null;
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }
}

String _sessionMessage(Object error, String fallback) =>
    error is InteractiveSessionFailure ? error.message : fallback;
