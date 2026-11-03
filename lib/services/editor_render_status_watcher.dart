import 'dart:async';

import '../repositories/editor_render_repository.dart';
import 'polling_cost_policy.dart';

enum EditorRenderTerminalStatus { completed, failed, cancelled, timedOut }

abstract interface class EditorRenderStatusWatcher {
  void watch({
    required String workspaceId,
    required String jobId,
    required void Function(EditorRenderTerminalStatus status) onTerminal,
  });

  void stop();

  void dispose();
}

/// Watches one explicitly user-started render until ii-os records its result.
///
/// The loop is bounded to the workflow's 90-minute timeout plus five minutes
/// for its terminal callback. Starting another watch or disposing this object
/// invalidates the current loop before it can update the caller.
final class PollingEditorRenderStatusWatcher
    implements EditorRenderStatusWatcher {
  PollingEditorRenderStatusWatcher(
    this._renders, {
    Future<void> Function(Duration duration)? delay,
    DateTime Function()? clock,
    this.timeout = const Duration(minutes: 95),
  }) : _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final EditorRenderStatusRepository _renders;
  final Future<void> Function(Duration duration) _delay;
  final DateTime Function() _clock;
  final Duration timeout;

  int _generation = 0;
  bool _disposed = false;

  @override
  void watch({
    required String workspaceId,
    required String jobId,
    required void Function(EditorRenderTerminalStatus status) onTerminal,
  }) {
    if (_disposed || workspaceId.isEmpty || jobId.isEmpty) return;
    final generation = ++_generation;
    unawaited(
      _run(
        workspaceId: workspaceId,
        jobId: jobId,
        generation: generation,
        onTerminal: onTerminal,
      ),
    );
  }

  Future<void> _run({
    required String workspaceId,
    required String jobId,
    required int generation,
    required void Function(EditorRenderTerminalStatus status) onTerminal,
  }) async {
    final deadline = _clock().add(timeout);
    while (_isCurrent(generation)) {
      EditorRenderJobStatus? status;
      try {
        status = await _renders.status(workspaceId: workspaceId, jobId: jobId);
      } on Object {
        // A transient request failure must not abandon an active render.
      }
      if (!_isCurrent(generation)) return;
      final terminal = switch (status) {
        EditorRenderJobStatus.completed => EditorRenderTerminalStatus.completed,
        EditorRenderJobStatus.failed => EditorRenderTerminalStatus.failed,
        EditorRenderJobStatus.cancelled => EditorRenderTerminalStatus.cancelled,
        EditorRenderJobStatus.active || null => null,
      };
      if (terminal != null) {
        _generation++;
        onTerminal(terminal);
        return;
      }
      if (!_clock().isBefore(deadline)) {
        _generation++;
        onTerminal(EditorRenderTerminalStatus.timedOut);
        return;
      }
      await _delay(IiOsPollingCostPolicy.activeOperation);
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void stop() {
    _generation++;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
  }
}
