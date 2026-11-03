import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/repositories/editor_render_repository.dart';
import 'package:ii_os/services/editor_render_status_watcher.dart';
import 'package:ii_os/services/polling_cost_policy.dart';

final class _SequenceStatuses implements EditorRenderStatusRepository {
  _SequenceStatuses(this.responses);

  final List<Object> responses;
  int calls = 0;

  @override
  Future<EditorRenderJobStatus> status({
    required String workspaceId,
    required String jobId,
  }) async {
    final response = responses[calls++];
    if (response is Error) throw response;
    return response as EditorRenderJobStatus;
  }
}

final class _PendingStatus implements EditorRenderStatusRepository {
  final result = Completer<EditorRenderJobStatus>();

  @override
  Future<EditorRenderJobStatus> status({
    required String workspaceId,
    required String jobId,
  }) => result.future;
}

void main() {
  test('job statuses map onto the render terminal contract', () {
    expect(
      parseEditorRenderJobStatus(const {'status': 'completed'}),
      EditorRenderJobStatus.completed,
    );
    expect(
      parseEditorRenderJobStatus(const {'status': 'failed'}),
      EditorRenderJobStatus.failed,
    );
    expect(
      parseEditorRenderJobStatus(const {'status': 'cancelled'}),
      EditorRenderJobStatus.cancelled,
    );
    expect(
      parseEditorRenderJobStatus(const {'status': 'running'}),
      EditorRenderJobStatus.active,
    );
  });

  test('a transient read keeps the active render watcher alive', () async {
    final statuses = _SequenceStatuses([
      StateError('temporary'),
      EditorRenderJobStatus.completed,
    ]);
    final delays = <Duration>[];
    final terminal = Completer<EditorRenderTerminalStatus>();
    final watcher = PollingEditorRenderStatusWatcher(
      statuses,
      delay: (duration) async => delays.add(duration),
    );

    watcher.watch(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      onTerminal: terminal.complete,
    );

    expect(await terminal.future, EditorRenderTerminalStatus.completed);
    expect(statuses.calls, 2);
    expect(delays, [IiOsPollingCostPolicy.activeOperation]);
  });

  test('stopping a watcher invalidates its in-flight result', () async {
    final statuses = _PendingStatus();
    EditorRenderTerminalStatus? terminal;
    final watcher = PollingEditorRenderStatusWatcher(statuses);
    watcher.watch(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      onTerminal: (value) => terminal = value,
    );

    watcher.stop();
    statuses.result.complete(EditorRenderJobStatus.completed);
    await pumpEventQueue();

    expect(terminal, isNull);
  });

  test('a render beyond the workflow deadline becomes terminal', () async {
    final started = DateTime.utc(2026, 8, 24);
    final times = [started, started.add(const Duration(minutes: 95))];
    final terminal = Completer<EditorRenderTerminalStatus>();
    final watcher = PollingEditorRenderStatusWatcher(
      _SequenceStatuses([EditorRenderJobStatus.active]),
      clock: () => times.removeAt(0),
    );

    watcher.watch(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      onTerminal: terminal.complete,
    );

    expect(await terminal.future, EditorRenderTerminalStatus.timedOut);
  });
}
