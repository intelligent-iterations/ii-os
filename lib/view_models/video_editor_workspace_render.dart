part of 'video_editor_projects_view_model.dart';

/// Handing an export to a workspace machine, and not losing track of it.
///
/// This is a part rather than its own class because it works on the same
/// state the rest of the view model owns: the open project, the timeline, and
/// what to tell the person when it does not work. A part file is still the
/// same library, so a test constructs one object and exercises all of it.
extension VideoEditorWorkspaceRender on VideoEditorProjectsViewModel {
  Future<T> _serializeProjectWrite<T>(Future<T> Function() operation) async {
    final previous = _projectWriteTail;
    final released = Completer<void>();
    _projectWriteTail = released.future;
    await previous;
    try {
      return await operation();
    } finally {
      released.complete();
    }
  }

  void _adoptRenderJob(String? jobId) {
    _replaceRenderJob(jobId);
    if (jobId == null || jobId.isEmpty) return;
    _watchRenderJob(jobId);
  }

  void _replaceRenderJob(String? jobId) {
    if (_renderJobId == jobId) return;
    _renderJobId = jobId;
    _renderJobGeneration++;
  }

  void _watchRenderJob(String jobId) {
    final projectId = _open?.id;
    _renderWatcher.watch(
      workspaceId: workspaceId,
      jobId: jobId,
      onTerminal: (status) => _renderFinished(projectId, jobId, status),
    );
  }

  void _renderFinished(
    String? projectId,
    String jobId,
    EditorRenderTerminalStatus status,
  ) {
    if (_open?.id != projectId || _renderJobId != jobId) return;
    _replaceRenderJob(null);
    _failure = switch (status) {
      EditorRenderTerminalStatus.completed => null,
      EditorRenderTerminalStatus.failed =>
        'The workspace machine could not finish this video.',
      EditorRenderTerminalStatus.cancelled =>
        'This workspace render was cancelled.',
      EditorRenderTerminalStatus.timedOut =>
        'The workspace render did not finish in the expected time.',
    };
    notifyListeners();
    unawaited(_persistFinishedRender());
  }

  Future<void> _persistFinishedRender() async {
    await _rememberRenderJob(null, notify: false);
  }

  /// Hands the open timeline to a workspace machine to render.
  ///
  /// The timeline is compiled here, exactly as it would be for an export on
  /// this device, and only the finished instruction travels. Returns the job
  /// id, or null with [failure] set.
  Future<String?> renderOnWorkspace({
    Map<String, VideoProjectMediaOrigin> origins = const {},
  }) async {
    if (_hasProjectOperation) return null;
    final dispatcher = _renderDispatcher;
    final timeline = _timeline;
    if (timeline == null) {
      _failure = 'Add some media before sending this edit to be rendered.';
      notifyListeners();
      return null;
    }
    if (!requireStructurallyFeasible(VideoEditorRenderIntent.workspaceRender)) {
      return null;
    }
    if (dispatcher == null || !_renderCapability.isAvailable) {
      _failure = 'No compatible workspace render machine is connected.';
      notifyListeners();
      return null;
    }
    _failure = null;
    setBusyForObject(VideoProjectBusy.dispatch, true);
    try {
      final jobId = await dispatcher.dispatch(
        workspaceId: workspaceId,
        expectedBucket: expectedBucket,
        timeline: timeline,
        origins: origins,
        ghostMode: ghostMode,
      );
      _replaceRenderJob(jobId.isEmpty ? null : jobId);
      await _rememberRenderJob(_renderJobId);
      if (_renderJobId case final activeJobId?) {
        _watchRenderJob(activeJobId);
      }
      return _renderJobId;
    } on EditorRenderTooLarge {
      _failure =
          'This edit is too large to hand to a workspace machine. Render it '
          'here, or shorten the timeline and try again.';
      return null;
    } on EditorRenderNotPortable catch (failure) {
      _failure = failure.message;
      return null;
    } on Object {
      _failure = 'This edit could not be sent to a workspace machine.';
      return null;
    } finally {
      setBusyForObject(VideoProjectBusy.dispatch, false);
    }
  }

  /// Writes the running render onto the open project, so closing the tab does
  /// not lose it. A timeline that belongs to no project keeps it in memory,
  /// which is the most that can be promised for something never saved.
  Future<void> _rememberRenderJob(String? jobId, {bool notify = true}) async {
    final projectId = _open?.id;
    if (projectId == null || _timeline == null) return;
    setBusyForObject(VideoProjectBusy.persistRender, true);
    try {
      await _serializeProjectWrite(() async {
        final project = _open;
        final timeline = _timeline;
        if (project?.id != projectId || timeline == null) return;
        final saved = await _projects.save(
          workspaceId: workspaceId,
          projectId: project!.id,
          timeline: jobId == null
              ? project.timeline
              : encodeEditorTimeline(timeline),
          media: project.media,
          change: jobId == null
              ? 'Finished rendering in the workspace'
              : 'Sent this edit to be rendered in the workspace',
          revision: project.revision,
          renderJobId: jobId,
          clearRenderJob: jobId == null,
        );
        if (_open?.id != projectId) return;
        _open = saved;
        _saved = [
          saved.summary,
          ..._saved.where((entry) => entry.id != saved.id),
        ];
        if (notify) notifyListeners();
      });
    } on Object {
      // The render is already running. Losing the note about it is worth
      // less than interrupting the person to say so.
    } finally {
      setBusyForObject(VideoProjectBusy.persistRender, false);
    }
  }

  /// Records that the workspace render is no longer running.
  Future<void> clearRenderJob() async {
    if (_hasProjectOperation) return;
    _renderWatcher.stop();
    _replaceRenderJob(null);
    await _rememberRenderJob(null);
    notifyListeners();
  }
}
