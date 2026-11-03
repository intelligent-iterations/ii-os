part of 'video_editor_projects_view_model_test.dart';

void videoEditorRenderTests() {
  test('a workspace with no machine does not offer to render on one', () {
    expect(
      _model(_FakeProjects(), _FakeGateway()).canRenderOnWorkspace,
      isFalse,
    );
  });

  test('a connected runner makes the workspace export option appear', () async {
    final model = _model(
      _FakeProjects(),
      _FakeGateway(),
      dispatcher: _FakeDispatcher(),
    );

    expect(model.canRenderOnWorkspace, isFalse);
    await model.load();
    expect(model.canRenderOnWorkspace, isTrue);
  });

  test(
    'a confirmed incompatible runner keeps workspace export hidden',
    () async {
      final model = _model(
        _FakeProjects(
          renderCapability: const EditorRenderCapability(
            EditorRenderCapabilityStatus.unavailable,
          ),
        ),
        _FakeGateway(),
        dispatcher: _FakeDispatcher(),
      );

      await model.load();
      expect(model.canRenderOnWorkspace, isFalse);
    },
  );

  test('a timeline is handed over with where its media lives', () async {
    final dispatcher = _FakeDispatcher();
    final model = _model(
      _FakeProjects(),
      _FakeGateway(),
      dispatcher: dispatcher,
    )..applyTimeline(_timeline());
    await model.load();

    const origin = WorkspaceSourceAssetOrigin('asset-1');
    expect(
      await model.renderOnWorkspace(origins: const {'media-1': origin}),
      'job-1',
    );
    expect(dispatcher.dispatches, 1);
    expect(dispatcher.sawOrigins, const {'media-1': origin});
    expect(model.renderJobId, 'job-1');
    expect(model.canRenderOnWorkspace, isTrue);
  });

  test('an empty timeline says what to do first', () async {
    final dispatcher = _FakeDispatcher();
    final model = _model(
      _FakeProjects(),
      _FakeGateway(),
      dispatcher: dispatcher,
    );
    await model.load();

    expect(await model.renderOnWorkspace(), isNull);
    expect(dispatcher.dispatches, 0);
    expect(model.failure, contains('Add some media'));
  });

  test('an edit too large to carry says so and offers the way round', () async {
    final model = _model(
      _FakeProjects(),
      _FakeGateway(),
      dispatcher: _FakeDispatcher(failure: const EditorRenderTooLarge()),
    )..applyTimeline(_timeline());
    await model.load();

    expect(await model.renderOnWorkspace(), isNull);
    expect(model.failure, contains('Render it here'));
  });

  test(
    'a dispatch that fails does not leave a stack trace on screen',
    () async {
      final model = _model(
        _FakeProjects(),
        _FakeGateway(),
        dispatcher: _FakeDispatcher(failure: StateError('boom')),
      )..applyTimeline(_timeline());
      await model.load();

      expect(await model.renderOnWorkspace(), isNull);
      expect(
        model.failure,
        'This edit could not be sent to a workspace machine.',
      );
      expect(model.failure, isNot(contains('boom')));
    },
  );

  test('a render started here is written onto the project', () async {
    final projects = _FakeProjects();
    final model = _model(
      projects,
      _FakeGateway(),
      dispatcher: _FakeDispatcher(),
    );
    await model.createProject();
    model.applyTimeline(_timeline());
    await model.load();

    expect(await model.renderOnWorkspace(), 'job-1');
    expect(projects.savedRenderJobId, 'job-1');
    expect(model.renderJobId, 'job-1');
  });

  test('a project reopened while it renders still knows about it', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()..restorable = [_media('media-1')];
    projects.readable = VideoProject(
      summary: VideoProjectSummary(
        id: 'project-1',
        name: 'Trailer',
        duration: const Duration(seconds: 8),
        clipCount: 1,
        mediaCount: 1,
        revision: 4,
        updatedAt: DateTime(2026, 8, 23),
        updatedBy: 'user-1',
        renderJobId: 'job-7',
      ),
      timeline: encodeEditorTimeline(_timeline()),
      media: [
        VideoProjectMediaRecord(
          id: 'media-1',
          filename: 'media-1.mp4',
          contentType: 'video/mp4',
          byteLength: 64,
          duration: const Duration(seconds: 9),
          hasVideo: true,
          hasAudio: false,
          origin: const WorkspaceSourceAssetOrigin('asset-1'),
        ),
      ],
      history: const [],
    );
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, gateway, renderWatcher: watcher);

    await model.openProject('project-1');
    expect(model.renderJobId, 'job-7');
    expect(watcher.watchedJobId, 'job-7');
  });

  test(
    'a completed workspace render clears its persisted loading state',
    () async {
      final projects = _FakeProjects();
      final watcher = _FakeRenderWatcher();
      final model = _model(
        projects,
        _FakeGateway(),
        dispatcher: _FakeDispatcher(),
        renderWatcher: watcher,
      );
      await model.createProject();
      model.applyTimeline(_timeline());
      await model.load();
      await model.renderOnWorkspace();

      watcher.finish(EditorRenderTerminalStatus.completed);
      await pumpEventQueue();

      expect(model.renderJobId, isNull);
      expect(projects.savedRenderJobId, isNull);
      expect(model.failure, isNull);
    },
  );

  test(
    'a failed workspace render replaces loading with a useful error',
    () async {
      final projects = _FakeProjects();
      final watcher = _FakeRenderWatcher();
      final model = _model(
        projects,
        _FakeGateway(),
        dispatcher: _FakeDispatcher(),
        renderWatcher: watcher,
      );
      await model.createProject();
      model.applyTimeline(_timeline());
      await model.load();
      await model.renderOnWorkspace();

      watcher.finish(EditorRenderTerminalStatus.failed);
      await pumpEventQueue();

      expect(model.renderJobId, isNull);
      expect(
        model.failure,
        'The workspace machine could not finish this video.',
      );
    },
  );

  test('a terminal render clear is serialized after a normal save', () async {
    final projects = _FakeProjects()
      ..preserveStoredRenderJob = true
      ..storedRenderJobId = 'job-a';
    final gateway = _FakeGateway()..restorable = [_media('media-1')];
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, gateway, renderWatcher: watcher);
    projects.readable = _storedProject(
      projects,
      id: 'project-a',
      timeline: encodeEditorTimeline(_timeline()),
      media: [_mediaRecord('media-1')],
      renderJobId: 'job-a',
    );
    await model.openProject('project-a');
    final saveRelease = Completer<void>();
    projects.saveDelay = saveRelease;
    final saving = model.save(media: [_media('media-1')]);
    await pumpEventQueue();

    watcher.finish(EditorRenderTerminalStatus.completed);
    expect(model.renderJobId, isNull);
    saveRelease.complete();

    expect(await saving, isTrue);
    await pumpEventQueue();
    expect(model.renderJobId, isNull);
    expect(projects.storedRenderJobId, isNull);
    expect(projects.savedRevisions, [0, 1]);
    expect(projects.savedClearRenderJobs, [false, true]);
    expect(projects.maxActiveSaves, 1);
  });

  test('a render nobody is waiting for any more is cleared', () async {
    final projects = _FakeProjects();
    final model = _model(
      projects,
      _FakeGateway(),
      dispatcher: _FakeDispatcher(),
    );
    await model.createProject();
    model.applyTimeline(_timeline());
    await model.load();
    await model.renderOnWorkspace();

    await model.clearRenderJob();
    expect(projects.savedRenderJobId, isNull);
    expect(model.renderJobId, isNull);
  });

  test('deleting the open project stops late render persistence', () async {
    final projects = _FakeProjects();
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, _FakeGateway(), renderWatcher: watcher);
    projects.readable = _storedProject(
      projects,
      id: 'project-a',
      renderJobId: 'job-a',
    );
    await model.openProject('project-a');
    final deleteRelease = Completer<void>();
    projects.deleteCompleter = deleteRelease;

    final deleting = model.deleteProject('project-a');
    await pumpEventQueue();
    expect(watcher.watchedJobId, isNull);

    watcher.finish(EditorRenderTerminalStatus.completed);
    deleteRelease.complete();

    expect(await deleting, isTrue);
    await pumpEventQueue();
    expect(projects.saves, 0);
    expect(model.current, isNull);
    expect(model.renderJobId, isNull);
  });

  test('a failed open-project delete re-arms its render watcher', () async {
    final projects = _FakeProjects();
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, _FakeGateway(), renderWatcher: watcher);
    projects.readable = _storedProject(
      projects,
      id: 'project-a',
      renderJobId: 'job-a',
    );
    await model.openProject('project-a');
    final deleteRelease = Completer<void>();
    projects.deleteCompleter = deleteRelease;

    final deleting = model.deleteProject('project-a');
    await pumpEventQueue();
    deleteRelease.completeError(StateError('offline'));

    expect(await deleting, isFalse);
    expect(model.current?.id, 'project-a');
    expect(model.renderJobId, 'job-a');
    expect(watcher.watchedJobId, 'job-a');
  });
}
