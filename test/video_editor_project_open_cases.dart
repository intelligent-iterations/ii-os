part of 'video_editor_projects_view_model_test.dart';

final class _FakeRenderWatcher implements EditorRenderStatusWatcher {
  String? watchedJobId;
  int watches = 0;
  int stops = 0;
  void Function(EditorRenderTerminalStatus status)? _onTerminal;

  @override
  void watch({
    required String workspaceId,
    required String jobId,
    required void Function(EditorRenderTerminalStatus status) onTerminal,
  }) {
    watches++;
    watchedJobId = jobId;
    _onTerminal = onTerminal;
  }

  void finish(EditorRenderTerminalStatus status) => _onTerminal?.call(status);

  @override
  void stop() {
    stops++;
    watchedJobId = null;
    _onTerminal = null;
  }

  @override
  void dispose() => stop();
}

void videoEditorProjectOpenTests() {
  test(
    'invalid schema is rejected before media effects and preserves A',
    () async {
      final projects = _FakeProjects();
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
      final openedA = await model.openProject('project-a');
      expect(openedA, isA<VideoProjectOpened>());
      final timelineA = model.timeline;
      model.applyTimeline(_timeline(duration: const Duration(seconds: 7)));
      model.undo();
      final pending = model.unsavedChanges;
      final restoresBefore = gateway.restoreCalls;

      projects.readable = _storedProject(
        projects,
        id: 'project-b',
        timeline: const {'version': 99},
        media: [_mediaRecord('media-b')],
      );
      final rejected = await model.openProject('project-b');

      expect(
        rejected,
        isA<VideoProjectOpenRejected>().having(
          (result) => result.reason,
          'reason',
          VideoProjectOpenRejection.timelineNewerBuildRequired,
        ),
      );
      expect(gateway.restoreCalls, restoresBefore);
      expect(model.current?.id, 'project-a');
      expect(model.timeline, same(timelineA));
      expect(model.renderJobId, 'job-a');
      expect(watcher.watchedJobId, 'job-a');
      expect(model.isDirty, isTrue);
      expect(model.canRedo, isTrue);
      expect(model.unsavedChanges, pending);
    },
  );

  test(
    'presentation replaces on acceptance and preserves on rejection',
    () async {
      final projects = _FakeProjects();
      final gateway = _FakeGateway()..restorable = [_media('media-1')];
      final model = _model(projects, gateway);
      projects.readable = _storedProject(
        projects,
        id: 'project-a',
        timeline: encodeEditorTimeline(_timeline()),
        media: [_mediaRecord('media-1')],
      );
      final opened = await model.openProject('project-a');
      final presentation = VideoProjectOpenPresentation()
        ..media['stale'] = _media('stale')
        ..mediaOrigins['stale'] = const WorkspaceSourceAssetOrigin(
          'asset-stale',
        );
      var timelineResets = 0;
      expect(
        presentation.apply(
          opened,
          refresh: (update) => update(),
          afterTimelineReplaced: () => timelineResets++,
        ),
        isTrue,
      );
      expect(presentation.media.keys, ['media-1']);
      expect(presentation.mediaOrigins.keys, ['media-1']);
      expect(timelineResets, 1);

      gateway.restoreFailure = const VideoProjectMediaMissing('missing.mp4');
      projects.readable = _storedProject(
        projects,
        id: 'project-b',
        timeline: encodeEditorTimeline(_timeline()),
        media: [_mediaRecord('media-b')],
      );
      final rejected = await model.openProject('project-b');
      expect(
        presentation.apply(
          rejected,
          refresh: (update) => update(),
          afterTimelineReplaced: () => timelineResets++,
        ),
        isFalse,
      );
      expect(model.current?.id, 'project-a');
      expect(presentation.media.keys, ['media-1']);
      expect(presentation.mediaOrigins.keys, ['media-1']);
      expect(timelineResets, 1);

      expect(
        await model.save(media: presentation.media.values.toList()),
        isTrue,
      );
      expect(projects.savedMedia?.map((item) => item.id), ['media-1']);
    },
  );

  test('blank success is distinct and commits only after the read', () async {
    final projects = _FakeProjects();
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, _FakeGateway(), renderWatcher: watcher);
    await model.createProject(name: 'A');
    model.adoptTimeline(_timeline());
    projects.readable = _storedProject(projects, id: 'blank');

    final result = await model.openProject('blank');

    expect(result, isA<VideoProjectOpened>());
    final opened = result as VideoProjectOpened;
    expect(opened.timeline, isNull);
    expect(opened.media, isEmpty);
    expect(model.current?.id, 'blank');
    expect(model.timeline, isNull);
    expect(watcher.stops, 1);
  });

  test('accepted blank presentation clears media and resets the editor', () {
    final projects = _FakeProjects();
    final presentation = VideoProjectOpenPresentation()
      ..media['media-1'] = _media('media-1')
      ..mediaOrigins['media-1'] = const WorkspaceSourceAssetOrigin('asset-1');
    var timelineResets = 0;
    final blank = VideoProjectOpened(
      project: _storedProject(projects, id: 'blank'),
      timeline: null,
      media: const [],
    );

    expect(
      presentation.apply(
        blank,
        refresh: (update) => update(),
        afterTimelineReplaced: () => timelineResets++,
      ),
      isTrue,
    );
    expect(presentation.media, isEmpty);
    expect(presentation.mediaOrigins, isEmpty);
    expect(timelineResets, 1);
  });

  test('opening is single flight and blocks edits and saves', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway();
    final model = _model(projects, gateway);
    await model.createProject(name: 'A');
    model.adoptTimeline(_timeline());
    final timelineA = model.timeline;
    projects.readCompleter = Completer<VideoProject>();

    final first = model.openProject('project-b');
    await pumpEventQueue();
    expect(model.isOpening, isTrue);
    final second = await model.openProject('project-c');
    expect(
      second,
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.alreadyOpening,
      ),
    );
    model.applyTimeline(_timeline(duration: const Duration(seconds: 7)));
    expect(model.timeline, same(timelineA));
    expect(await model.save(media: [_media('media-1')]), isFalse);
    expect(gateway.uploads, 0);

    projects.readCompleter!.complete(_storedProject(projects, id: 'project-b'));
    expect(await first, isA<VideoProjectOpened>());
    expect(model.current?.id, 'project-b');
    expect(projects.reads, 1);
  });

  test('an in-flight save keeps another project from opening', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()..restorable = [_media('media-1')];
    final model = _model(projects, gateway);
    projects.readable = _storedProject(
      projects,
      id: 'project-a',
      timeline: encodeEditorTimeline(_timeline()),
      media: [_mediaRecord('media-1')],
    );
    await model.openProject('project-a');
    final timelineA = model.timeline;
    gateway.publishDelay = Completer<void>();
    final saving = model.save(media: [_media('media-1')]);
    await pumpEventQueue();

    projects.readable = _storedProject(projects, id: 'project-b');
    final rejected = await model.openProject('project-b');
    expect(
      rejected,
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.anotherOperation,
      ),
    );
    gateway.publishDelay!.complete();
    expect(await saving, isTrue);
    expect(model.current?.id, 'project-a');
    expect(model.timeline, same(timelineA));
  });

  test('an in-flight create keeps another project from opening', () async {
    final projects = _FakeProjects()
      ..createCompleter = Completer<VideoProject>();
    final model = _model(projects, _FakeGateway())..adoptTimeline(_timeline());
    final creating = model.createProject(name: 'A');
    await pumpEventQueue();

    expect(
      await model.openProject('project-b'),
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.anotherOperation,
      ),
    );
    projects.createCompleter!.complete(
      _storedProject(projects, id: 'project-a'),
    );
    expect((await creating)?.id, 'project-a');
    expect(model.current?.id, 'project-a');
  });

  test('successful switch stops A and watches B exactly at commit', () async {
    final projects = _FakeProjects();
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, _FakeGateway(), renderWatcher: watcher);
    projects.readable = _storedProject(
      projects,
      id: 'project-a',
      renderJobId: 'job-a',
    );
    await model.openProject('project-a');
    expect(watcher.watchedJobId, 'job-a');
    final stopsBefore = watcher.stops;

    projects.readable = _storedProject(
      projects,
      id: 'project-b',
      renderJobId: 'job-b',
    );
    final result = await model.openProject('project-b');

    expect(result, isA<VideoProjectOpened>());
    expect(watcher.stops, stopsBefore + 1);
    expect(watcher.watchedJobId, 'job-b');
  });

  test('a render failure from A cannot leak into accepted B', () async {
    final projects = _FakeProjects();
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, _FakeGateway(), renderWatcher: watcher);
    projects.readable = _storedProject(
      projects,
      id: 'project-a',
      renderJobId: 'job-a',
    );
    await model.openProject('project-a');
    projects.readCompleter = Completer<VideoProject>();
    final openingB = model.openProject('project-b');
    await pumpEventQueue();

    watcher.finish(EditorRenderTerminalStatus.failed);
    expect(model.failure, contains('could not finish'));
    projects.readCompleter!.complete(_storedProject(projects, id: 'project-b'));

    expect(await openingB, isA<VideoProjectOpened>());
    expect(model.current?.id, 'project-b');
    expect(model.failure, isNull);
  });

  test('close is a no-op while another project is opening', () async {
    final projects = _FakeProjects();
    final model = _model(projects, _FakeGateway());
    await model.createProject(name: 'A');
    model.adoptTimeline(_timeline());
    final projectA = model.current;
    final timelineA = model.timeline;
    projects.readCompleter = Completer<VideoProject>();
    final openingB = model.openProject('project-b');
    await pumpEventQueue();

    expect(model.closeProject(), isFalse);
    expect(model.current, same(projectA));
    expect(model.timeline, same(timelineA));
    projects.readCompleter!.completeError(StateError('offline'));
    expect(await openingB, isA<VideoProjectOpenRejected>());
    expect(model.current, same(projectA));
    expect(model.timeline, same(timelineA));
  });

  test('delete is rejected while another project is opening', () async {
    final projects = _FakeProjects();
    final model = _model(projects, _FakeGateway());
    await model.createProject(name: 'A');
    model.adoptTimeline(_timeline());
    final projectA = model.current;
    final timelineA = model.timeline;
    projects.readCompleter = Completer<VideoProject>();
    final openingB = model.openProject('project-b');
    await pumpEventQueue();

    expect(await model.deleteProject('project-1'), isFalse);
    expect(projects.deletes, 0);
    projects.readCompleter!.completeError(StateError('offline'));
    expect(await openingB, isA<VideoProjectOpenRejected>());
    expect(model.current, same(projectA));
    expect(model.timeline, same(timelineA));
  });

  test('opening waits until render persistence has settled', () async {
    final projects = _FakeProjects();
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
    watcher.finish(EditorRenderTerminalStatus.completed);
    await pumpEventQueue();

    projects.readable = _storedProject(projects, id: 'project-b');
    expect(
      await model.openProject('project-b'),
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.anotherOperation,
      ),
    );
    saveRelease.complete();
    await pumpEventQueue();
    expect(await model.openProject('project-b'), isA<VideoProjectOpened>());

    expect(model.current?.id, 'project-b');
    expect(model.timeline, isNull);
  });
}
