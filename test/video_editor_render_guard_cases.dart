part of 'video_editor_projects_view_model_test.dart';

EditorProject _cutTimeline() =>
    sliceEditorProject(project: _timeline(), at: MediaTime.seconds(4));

EditorProject _browserTimeline(Duration duration) =>
    _timeline(duration: duration).copyWith(
      output: const MediaOutputSettings(
        container: MediaContainer.webm,
        videoCodec: MediaVideoCodec.vp9,
        audioCodec: MediaAudioCodec.opus,
        videoBitrate: 100000,
        audioBitrate: 64000,
      ),
    );

EditorProject _captionTimeline(int captionCount) {
  var project = _browserTimeline(const Duration(seconds: 60));
  for (var index = 0; index < captionCount; index++) {
    project = addEditorCaption(
      project: project,
      playhead: MediaTime.seconds(index * 3),
      laneId: 'caption-lane-$index',
      clipId: 'caption-clip-$index',
      text: 'Caption $index',
      subtitle: true,
    );
  }
  return project;
}

EditorProject _videoOccurrenceTimeline(int occurrenceCount) {
  final source = _media('shared-video').source;
  return _browserTimeline(const Duration(seconds: 30)).copyWith(
    lanes: [
      EditorLane(
        id: 'sequential-video-lane',
        label: 'Sequential video',
        kind: EditorLaneKind.video,
        clips: [
          for (var index = 0; index < occurrenceCount; index++)
            EditorVideoClip(
              id: 'video-occurrence-$index',
              timelineStart: MediaTime.seconds(index),
              duration: MediaTime.seconds(1),
              source: source,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(1),
              ),
              sourceDuration: MediaTime.seconds(9),
            ),
        ],
      ),
      EditorLane(
        id: 'available-caption-lane',
        label: 'Captions',
        kind: EditorLaneKind.captions,
        clips: const [],
      ),
    ],
  );
}

VideoEditorRenderReadinessService _oneLayerReadiness() =>
    VideoEditorRenderReadinessService(
      compiler: const EditorCompositionCompiler.forTarget(
        EditorRenderTarget(mediaLimits: MediaLimits(maxLayerCount: 1)),
      ),
    );

void videoEditorRenderGuardTests() {
  group('structural render guard', () {
    test('scratch save rejects before creating a remote project', () async {
      final projects = _FakeProjects();
      final gateway = _FakeGateway();
      final model = _model(
        projects,
        gateway,
        renderReadiness: _oneLayerReadiness(),
      )..adoptTimeline(_cutTimeline(), dirty: true);

      expect(
        model.requireStructurallyFeasible(VideoEditorRenderIntent.save),
        isFalse,
      );
      expect(await model.createProject(name: 'Too many layers'), isNull);
      expect(projects.creates, 0);
      expect(gateway.uploads, 0);
      expect(model.failure, contains('segments'));
    });

    test('existing save rejects before media publication', () async {
      final projects = _FakeProjects();
      final gateway = _FakeGateway();
      final model = _model(
        projects,
        gateway,
        renderReadiness: _oneLayerReadiness(),
      );
      await model.createProject();
      model.adoptTimeline(_cutTimeline(), dirty: true);

      expect(await model.save(media: [_media('media-1')]), isFalse);
      expect(gateway.uploads, 0);
      expect(projects.saves, 0);
    });

    test('workspace render rejects before dispatch', () async {
      final dispatcher = _FakeDispatcher();
      final model = _model(
        _FakeProjects(),
        _FakeGateway(),
        dispatcher: dispatcher,
        renderReadiness: _oneLayerReadiness(),
      )..adoptTimeline(_cutTimeline(), dirty: true);
      await model.load();

      expect(await model.renderOnWorkspace(), isNull);
      expect(dispatcher.dispatches, 0);
      expect(model.failure, contains('segments'));
    });

    test('local render rejects before its engine factory runs', () {
      var engineCreations = 0;
      final model = _model(
        _FakeProjects(),
        _FakeGateway(),
        renderReadiness: _oneLayerReadiness(),
      )..adoptTimeline(_cutTimeline(), dirty: true);

      final engine = model.afterLocalRenderAdmission(() {
        engineCreations++;
        return Object();
      });

      expect(engine, isNull);
      expect(engineCreations, 0);
      expect(model.failure, contains('segments'));
    });

    test('repairing the timeline clears its structural blocker', () {
      final model = _model(
        _FakeProjects(),
        _FakeGateway(),
        renderReadiness: _oneLayerReadiness(),
      )..adoptTimeline(_cutTimeline(), dirty: true);

      expect(model.renderFeasibility?.isStructurallyFeasible, isFalse);
      expect(model.failure, isNotNull);

      model.applyTimeline(_timeline());

      expect(model.renderFeasibility?.isStructurallyFeasible, isTrue);
      expect(model.failure, isNull);
    });

    test('an infeasible addition is rejected without changing edit state', () {
      final original = _timeline();
      final model = _model(
        _FakeProjects(),
        _FakeGateway(),
        renderReadiness: _oneLayerReadiness(),
      )..adoptTimeline(original);
      final feasibility = model.renderFeasibility;

      final accepted = model.applyStructurallyFeasibleAddition(_cutTimeline());

      expect(accepted, isFalse);
      expect(model.timeline, same(original));
      expect(model.renderFeasibility, same(feasibility));
      expect(model.isDirty, isFalse);
      expect(model.canUndo, isFalse);
      expect(model.canRedo, isFalse);
      expect(model.unsavedChanges, isEmpty);
      expect(model.failure, contains('segments'));
    });

    test('a feasible addition is recorded normally', () {
      final model = _model(
        _FakeProjects(),
        _FakeGateway(),
        renderReadiness: _oneLayerReadiness(),
      );

      final accepted = model.applyStructurallyFeasibleAddition(_timeline());

      expect(accepted, isTrue);
      expect(model.timeline, isNotNull);
      expect(model.isDirty, isTrue);
      expect(model.unsavedChanges, ['Started a timeline']);
      expect(model.failure, isNull);
    });

    test('addition admission accepts the target edge and rejects above it', () {
      final model = _model(
        _FakeProjects(),
        _FakeGateway(),
        renderReadiness: VideoEditorRenderReadinessService(
          compiler: EditorCompositionCompiler.forTarget(
            videoEditorRenderTargetFor(browser: true),
          ),
        ),
      );
      final exact = _browserTimeline(const Duration(minutes: 2));
      final over = _browserTimeline(
        const Duration(minutes: 2, microseconds: 1),
      );

      expect(model.applyStructurallyFeasibleAddition(exact), isTrue);
      final exactFeasibility = model.renderFeasibility;
      expect(model.applyStructurallyFeasibleAddition(over), isFalse);

      expect(model.timeline, same(exact));
      expect(model.renderFeasibility, same(exactFeasibility));
      expect(model.unsavedChanges, ['Started a timeline']);
      expect(model.canUndo, isFalse);
      expect(model.failure, contains('too large'));
    });

    for (final browser in [true, false]) {
      test(
        'caption addition is atomic at the ${browser ? 'browser' : 'native'} input edge',
        () {
          final before = _captionTimeline(14);
          final exact = addEditorCaption(
            project: before,
            playhead: MediaTime.seconds(42),
            laneId: 'unused-exact-caption-lane',
            clipId: 'caption-clip-14',
            text: 'Exact edge',
            subtitle: true,
          );
          final over = addEditorCaption(
            project: exact,
            playhead: MediaTime.seconds(45),
            laneId: 'unused-over-caption-lane',
            clipId: 'caption-clip-15',
            text: 'One over',
            subtitle: true,
          );
          final model = _model(
            _FakeProjects(),
            _FakeGateway(),
            renderReadiness: VideoEditorRenderReadinessService(
              compiler: EditorCompositionCompiler.forTarget(
                videoEditorRenderTargetFor(browser: browser),
              ),
            ),
          )..adoptTimeline(before);

          final compiler = EditorCompositionCompiler.forTarget(
            videoEditorRenderTargetFor(browser: browser),
          );
          final exactReport = compiler.preflight(exact);
          final overReport = compiler.preflight(over);
          expect(exactReport.footprint!.totalInputCount, 16);
          expect(exactReport.issues, isEmpty);
          expect(overReport.footprint!.totalInputCount, 17);
          expect(overReport.issues, hasLength(1));
          expect(
            overReport.issues.single.code,
            EditorRenderIssueCode.inputLimitExceeded,
          );
          expect(overReport.issues.single.actual, 17);
          expect(overReport.issues.single.maximum, 16);
          expect(model.applyStructurallyFeasibleAddition(exact), isTrue);
          final exactFeasibility = model.renderFeasibility;
          expect(model.applyStructurallyFeasibleAddition(over), isFalse);

          expect(model.timeline, same(exact));
          expect(model.renderFeasibility, same(exactFeasibility));
          expect(model.isDirty, isTrue);
          expect(model.canUndo, isTrue);
          expect(model.canRedo, isFalse);
          expect(model.unsavedChanges, ['Added a caption']);
          expect(model.failure, contains('imported items and captions'));
        },
      );

      test(
        'caption addition is atomic at the ${browser ? 'browser' : 'native'} layer edge',
        () {
          final before = _videoOccurrenceTimeline(23);
          final exact = addEditorCaption(
            project: before,
            playhead: MediaTime.seconds(24),
            laneId: 'unused-exact-layer-lane',
            clipId: 'exact-layer-caption',
            text: 'Exact layer edge',
            subtitle: true,
          );
          final over = addEditorCaption(
            project: exact,
            playhead: MediaTime.seconds(27),
            laneId: 'unused-over-layer-lane',
            clipId: 'over-layer-caption',
            text: 'One layer over',
            subtitle: true,
          );
          final compiler = EditorCompositionCompiler.forTarget(
            videoEditorRenderTargetFor(browser: browser),
          );
          final exactFootprint = compiler.preflight(exact).footprint!;
          final exactReport = compiler.preflight(exact);
          final overReport = compiler.preflight(over);
          final overFootprint = overReport.footprint!;
          final model = _model(
            _FakeProjects(),
            _FakeGateway(),
            renderReadiness: VideoEditorRenderReadinessService(
              compiler: compiler,
            ),
          )..adoptTimeline(before);

          expect(exactFootprint.emittedLayerCount, 24);
          expect(exactReport.issues, isEmpty);
          expect(overFootprint.emittedLayerCount, 25);
          expect(overFootprint.totalInputCount, 3);
          expect(overReport.issues, hasLength(1));
          expect(
            overReport.issues.single.code,
            EditorRenderIssueCode.emittedLayerLimitExceeded,
          );
          expect(overReport.issues.single.actual, 25);
          expect(overReport.issues.single.maximum, 24);
          expect(model.applyStructurallyFeasibleAddition(exact), isTrue);
          final exactFeasibility = model.renderFeasibility;
          expect(model.applyStructurallyFeasibleAddition(over), isFalse);

          expect(model.timeline, same(exact));
          expect(model.renderFeasibility, same(exactFeasibility));
          expect(model.unsavedChanges, ['Added a caption']);
          expect(model.canUndo, isTrue);
          expect(model.failure, contains('clip and caption segments'));
        },
      );
    }

    for (final browser in [true, false]) {
      for (final boundary in ['input', 'layer']) {
        test(
          'caption request preserves output at the ${browser ? 'browser' : 'native'} $boundary rejection',
          () async {
            final exact = boundary == 'input'
                ? _captionTimeline(15)
                : addEditorCaption(
                    project: _videoOccurrenceTimeline(23),
                    playhead: MediaTime.seconds(24),
                    laneId: 'unused-exact-flow-lane',
                    clipId: 'exact-flow-caption',
                    text: 'Exact flow edge',
                    subtitle: true,
                  );
            final playhead = boundary == 'input'
                ? MediaTime.seconds(45)
                : MediaTime.seconds(27);
            final clipId = '$boundary-over-flow-caption';
            final model = _model(
              _FakeProjects(),
              _FakeGateway(),
              renderReadiness: VideoEditorRenderReadinessService(
                compiler: EditorCompositionCompiler.forTarget(
                  videoEditorRenderTargetFor(browser: browser),
                ),
              ),
            )..adoptTimeline(exact);
            final feasibility = model.renderFeasibility;
            final outputSentinel = Object();
            Object outputArtifact = outputSentinel;
            var acceptedEffects = 0;

            final accepted = await runEditorAdditionRequest<String>(
              request: () async => 'Rejected $boundary caption',
              currentProject: () => model.timeline,
              unavailable: () => false,
              buildCandidate: (project, text) => addEditorCaption(
                project: project,
                playhead: playhead,
                laneId: 'unused-$boundary-over-flow-lane',
                clipId: clipId,
                text: text,
                subtitle: true,
              ),
              admit: model.applyStructurallyFeasibleAddition,
              onAccepted: () {
                acceptedEffects++;
                outputArtifact = Object();
              },
            );

            expect(accepted, isFalse);
            expect(model.timeline, same(exact));
            expect(model.renderFeasibility, same(feasibility));
            expect(model.isDirty, isFalse);
            expect(model.canUndo, isFalse);
            expect(model.canRedo, isFalse);
            expect(model.unsavedChanges, isEmpty);
            expect(model.timeline!.clipById(clipId), isNull);
            expect(outputArtifact, same(outputSentinel));
            expect(acceptedEffects, 0);
            expect(model.failure, isNotNull);
          },
        );
      }
    }

    test(
      'repairing structural feasibility preserves another failure',
      () async {
        final dispatcher = _FakeDispatcher(failure: StateError('offline'));
        final model = _model(
          _FakeProjects(),
          _FakeGateway(),
          dispatcher: dispatcher,
          renderReadiness: _oneLayerReadiness(),
        )..adoptTimeline(_timeline());
        await model.load();
        await model.renderOnWorkspace();
        final unrelated = model.failure;

        model.applyTimeline(_cutTimeline());
        expect(model.renderFeasibility?.isStructurallyFeasible, isFalse);

        model.applyTimeline(_timeline());

        expect(model.renderFeasibility?.isStructurallyFeasible, isTrue);
        expect(model.failure, unrelated);
      },
    );
  });
}
