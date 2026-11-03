part of 'video_editor_projects_view_model_test.dart';

void videoEditorProjectOpenValidationTests() {
  test(
    'all schema and semantic failures happen before media restore',
    () async {
      final valid = encodeEditorTimeline(_timeline());
      final unsafeMedia = encodeEditorTimeline(_timeline());
      final unsafeLanes = unsafeMedia['lanes']! as List<Object?>;
      final unsafeLane = unsafeLanes.first! as Map<String, Object?>;
      final unsafeClips = unsafeLane['clips']! as List<Object?>;
      final unsafeClip = unsafeClips.first! as Map<String, Object?>;
      unsafeClip['mediaId'] = '../bad';
      final cases = <({JsonMap timeline, VideoProjectOpenRejection reason})>[
        (
          timeline: const {'version': 1},
          reason: VideoProjectOpenRejection.timelineMalformed,
        ),
        (
          timeline: {...valid, 'unknown': 'future'},
          reason: VideoProjectOpenRejection.timelineMalformed,
        ),
        (
          timeline: {...valid, 'durationMicros': 0},
          reason: VideoProjectOpenRejection.timelineInvalid,
        ),
        (
          timeline: unsafeMedia,
          reason: VideoProjectOpenRejection.timelineInvalid,
        ),
        (
          timeline: const {'version': 0},
          reason: VideoProjectOpenRejection.timelineLegacyUnsupported,
        ),
        (
          timeline: const {'version': 99},
          reason: VideoProjectOpenRejection.timelineNewerBuildRequired,
        ),
      ];
      final projects = _FakeProjects();
      final gateway = _FakeGateway()..restoreFailure = StateError('media I/O');
      final model = _model(projects, gateway);

      for (var index = 0; index < cases.length; index++) {
        final testCase = cases[index];
        final mediaId = identical(testCase.timeline, unsafeMedia)
            ? '../bad'
            : 'media-1';
        projects.readable = _storedProject(
          projects,
          id: 'invalid-$index',
          timeline: testCase.timeline,
          media: [_mediaRecord(mediaId)],
        );

        expect(
          await model.openProject('invalid-$index'),
          isA<VideoProjectOpenRejected>().having(
            (result) => result.reason,
            'reason',
            testCase.reason,
          ),
        );
      }
      expect(gateway.restoreCalls, 0);
    },
  );

  test('semantic rejection preserves exact open project state', () async {
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
    model.applyTimeline(_timeline(duration: const Duration(seconds: 7)));
    model.undo();
    final timelineA = model.timeline;
    final pendingA = model.unsavedChanges;
    final restoresBefore = gateway.restoreCalls;
    final invalid = {...encodeEditorTimeline(_timeline()), 'durationMicros': 0};
    projects.readable = _storedProject(
      projects,
      id: 'project-b',
      timeline: invalid,
      media: [_mediaRecord('media-1')],
    );

    expect(
      await model.openProject('project-b'),
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.timelineInvalid,
      ),
    );
    expect(gateway.restoreCalls, restoresBefore);
    expect(model.current?.id, 'project-a');
    expect(model.timeline, same(timelineA));
    expect(model.unsavedChanges, pendingA);
    expect(model.isDirty, isTrue);
    expect(model.canRedo, isTrue);
    expect(model.renderJobId, 'job-a');
    expect(watcher.watchedJobId, 'job-a');
  });

  test('missing timeline media records reject before restore', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()..restoreFailure = StateError('media I/O');
    final model = _model(projects, gateway);
    projects.readable = _storedProject(
      projects,
      id: 'project-b',
      timeline: encodeEditorTimeline(_timeline()),
    );

    expect(
      await model.openProject('project-b'),
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.mediaUnavailable,
      ),
    );
    expect(gateway.restoreCalls, 0);
  });

  test(
    'a blank timeline with stored media is malformed without restore',
    () async {
      final projects = _FakeProjects();
      final gateway = _FakeGateway()..restoreFailure = StateError('media I/O');
      final model = _model(projects, gateway);
      projects.readable = _storedProject(
        projects,
        id: 'project-b',
        media: [_mediaRecord('media-1')],
      );

      expect(
        await model.openProject('project-b'),
        isA<VideoProjectOpenRejected>().having(
          (result) => result.reason,
          'reason',
          VideoProjectOpenRejection.timelineMalformed,
        ),
      );
      expect(gateway.restoreCalls, 0);
    },
  );

  test('generic restore failures are media failures', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()..restoreFailure = StateError('offline');
    final model = _model(projects, gateway);
    projects.readable = _storedProject(
      projects,
      id: 'project-b',
      timeline: encodeEditorTimeline(_timeline()),
      media: [_mediaRecord('media-1')],
    );

    expect(
      await model.openProject('project-b'),
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.mediaUnavailable,
      ),
    );
    expect(gateway.restoreCalls, 1);
  });

  test('render mutations are rejected while a project is opening', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()..restorable = [_media('media-1')];
    final watcher = _FakeRenderWatcher();
    final dispatcher = _FakeDispatcher();
    final model = _model(
      projects,
      gateway,
      renderWatcher: watcher,
      dispatcher: dispatcher,
    );
    projects.readable = _storedProject(
      projects,
      id: 'project-a',
      timeline: encodeEditorTimeline(_timeline()),
      media: [_mediaRecord('media-1')],
      renderJobId: 'job-a',
    );
    await model.openProject('project-a');
    await model.load();
    projects.readCompleter = Completer<VideoProject>();
    final openingB = model.openProject('project-b');
    await pumpEventQueue();

    expect(await model.renderOnWorkspace(), isNull);
    await model.clearRenderJob();
    expect(dispatcher.dispatches, 0);
    expect(model.renderJobId, 'job-a');
    expect(watcher.watchedJobId, 'job-a');
    projects.readCompleter!.completeError(StateError('offline'));
    expect(await openingB, isA<VideoProjectOpenRejected>());
  });

  test('a rejected close cannot clear presentation-owned media', () {
    final presentation = VideoProjectOpenPresentation()
      ..media['media-1'] = _media('media-1')
      ..mediaOrigins['media-1'] = const WorkspaceSourceAssetOrigin('asset-1');
    var resets = 0;

    expect(
      presentation.clearIf(
        false,
        refresh: (update) => update(),
        afterTimelineReplaced: () => resets++,
      ),
      isFalse,
    );
    expect(presentation.media.keys, ['media-1']);
    expect(presentation.mediaOrigins.keys, ['media-1']);
    expect(resets, 0);

    expect(
      presentation.clearIf(
        true,
        refresh: (update) => update(),
        afterTimelineReplaced: () => resets++,
      ),
      isTrue,
    );
    expect(presentation.media, isEmpty);
    expect(presentation.mediaOrigins, isEmpty);
    expect(resets, 1);
  });

  test('same-project reopen rejects a stale render revision', () async {
    final projects = _FakeProjects();
    final gateway = _FakeGateway()..restorable = [_media('media-1')];
    final watcher = _FakeRenderWatcher();
    final model = _model(projects, gateway, renderWatcher: watcher);
    final projectA = _storedProject(
      projects,
      id: 'project-a',
      timeline: encodeEditorTimeline(_timeline()),
      media: [_mediaRecord('media-1')],
      renderJobId: 'job-a',
    );
    projects.readable = projectA;
    await model.openProject('project-a');
    final restoreRelease = Completer<void>();
    gateway.restoreDelay = restoreRelease;
    final reopening = model.openProject('project-a');
    await pumpEventQueue();

    watcher.finish(EditorRenderTerminalStatus.completed);
    await pumpEventQueue();
    expect(model.current?.revision, 1);
    expect(model.renderJobId, isNull);
    restoreRelease.complete();

    expect(
      await reopening,
      isA<VideoProjectOpenRejected>().having(
        (result) => result.reason,
        'reason',
        VideoProjectOpenRejection.anotherOperation,
      ),
    );
    expect(model.current?.revision, 1);
    expect(model.renderJobId, isNull);
    expect(await model.save(media: [_media('media-1')]), isTrue);
    expect(projects.savedRevisions, [0, 1]);
  });
}
