import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'render_feasibility_support.dart';
import 'support.dart';

void main() {
  group('render feasibility compiler parity', () {
    test('rejects structural blockers before preparation', () async {
      var rasterCalls = 0;
      var sourceReads = 0;
      final source = MediaSource(
        id: 'shared-source',
        byteLength: 1,
        fileExtension: 'mp4',
        openRead: () {
          sourceReads++;
          throw StateError('must not read');
        },
      );
      final compiler = EditorCompositionCompiler(
        captionRasterizer: CallbackCaptionRasterizer((request, cancellation) {
          rasterCalls++;
          throw StateError('must not rasterize');
        }),
      );
      final project = feasibilityProject([
        feasibilityVideoLane('videos', source, count: 24),
        feasibilityCaptionLane('caption', count: 1),
      ]);

      final report = compiler.preflight(project);
      expect(
        report.issues.map((issue) => issue.code),
        contains(EditorRenderIssueCode.emittedLayerLimitExceeded),
      );
      await expectLater(
        compiler.compile(project),
        throwsA(isA<EditorValidationException>()),
      );
      expect(rasterCalls, 0);
      expect(sourceReads, 0);
    });

    test('intersects provider byte limits', () {
      final source = MediaSource(
        id: 'provider-sized-source',
        byteLength: 5,
        fileExtension: 'mp4',
        openRead: () => throw StateError('must not read'),
      );
      final result = const EditorCompositionCompiler().preflight(
        feasibilityProject([feasibilityVideoLane('video', source)]),
        safety: const FfmpegSafetyPolicy(
          maxInputBytes: 4,
          maxTotalInputBytes: 4,
          maxOutputBytes: 1,
          maxTotalOutputBytes: 1,
          maxWorkspaceBytes: 5,
        ),
      );

      expect(
        result.issues.map((issue) => issue.code),
        containsAll({
          EditorRenderIssueCode.sourceByteLengthExceeded,
          EditorRenderIssueCode.declaredInputBytesExceeded,
        }),
      );
    });

    test('rejects estimated output overflow before source reads', () async {
      var sourceReads = 0;
      final source = MediaSource(
        id: 'unread-output-source',
        byteLength: 1,
        fileExtension: 'mp4',
        openRead: () {
          sourceReads++;
          throw StateError('must not read');
        },
      );
      final project =
          feasibilityProject([feasibilityVideoLane('video', source)]).copyWith(
            duration: MediaTime.seconds(8),
            output: const MediaOutputSettings(
              videoBitrate: 7000,
              audioBitrate: 1000,
            ),
          );
      const limits = MediaLimits(
        maxOutputBytes: 9000,
        maxEstimatedOutputBytes: 7999,
      );
      final compiler = const EditorCompositionCompiler();

      expect(
        compiler
            .preflight(project, mediaLimits: limits)
            .issues
            .map((issue) => issue.code),
        contains(EditorRenderIssueCode.estimatedOutputBytesExceeded),
      );
      await expectLater(
        compiler.compile(project, mediaLimits: limits),
        throwsA(isA<EditorValidationException>()),
      );
      expect(sourceReads, 0);
    });

    test('rejects reserved caption overflow before preparation', () async {
      var rasterCalls = 0;
      var sourceReads = 0;
      final source = MediaSource(
        id: 'reserved-caption-source',
        byteLength: 9,
        fileExtension: 'mp4',
        openRead: () {
          sourceReads++;
          throw StateError('must not read');
        },
      );
      const target = EditorRenderTarget(
        editorLimits: EditorLimits(
          maxCaptionRasterBytes: 4,
          maxCaptionTotalRasterBytes: 4,
        ),
        mediaLimits: MediaLimits(
          maxInputBytes: 12,
          maxDeclaredMediaBytes: 10,
          maxSourceBytes: 12,
        ),
      );
      final compiler = EditorCompositionCompiler.forTarget(
        target,
        captionRasterizer: CallbackCaptionRasterizer((request, cancellation) {
          rasterCalls++;
          throw StateError('must not rasterize');
        }),
      );
      final project = feasibilityProject([
        feasibilityVideoLane('video', source),
        feasibilityCaptionLane('caption', count: 1),
      ]);

      expect(
        compiler.preflight(project).issues.single.code,
        EditorRenderIssueCode.preparedInputBytesExceeded,
      );
      await expectLater(
        compiler.compile(project),
        throwsA(isA<EditorValidationException>()),
      );
      expect(rasterCalls, 0);
      expect(sourceReads, 0);
    });

    test('one target intersects total output for preflight and job', () async {
      const target = EditorRenderTarget(
        mediaLimits: MediaLimits(
          maxInputBytes: 1,
          maxSourceBytes: 1,
          maxOutputBytes: 100,
          maxEstimatedOutputBytes: 92,
          maxVideoBitrate: 100,
          maxAudioBitrate: 100,
        ),
        safety: FfmpegSafetyPolicy(
          maxInputBytes: 1,
          maxTotalInputBytes: 1,
          maxOutputBytes: 100,
          maxTotalOutputBytes: 80,
          maxWorkspaceBytes: 81,
        ),
      );
      const compiler = EditorCompositionCompiler.forTarget(target);
      EditorProject project(int videoBitrate) =>
          feasibilityProject([]).copyWith(
            duration: MediaTime.seconds(8),
            output: MediaOutputSettings(
              videoBitrate: videoBitrate,
              audioBitrate: 1,
            ),
          );

      final exact = compiler.preflight(project(79));
      final over = compiler.preflight(project(80));
      expect(exact.isStructurallyFeasible, isTrue);
      expect(
        over.issues.map((issue) => issue.code),
        contains(EditorRenderIssueCode.estimatedOutputBytesExceeded),
      );

      final plan = await compiler.compile(project(79));
      expect(plan.job.outputs.single.maxBytes, 80);
      expect(
        () => compiler.preflight(project(79), mediaLimits: const MediaLimits()),
        throwsArgumentError,
      );
    });

    test('incoherent target workspace bounds are configuration errors', () {
      const target = EditorRenderTarget(
        mediaLimits: MediaLimits(
          maxInputBytes: 4,
          maxSourceBytes: 4,
          maxOutputBytes: 2,
        ),
        safety: FfmpegSafetyPolicy(
          maxInputBytes: 4,
          maxTotalInputBytes: 4,
          maxOutputBytes: 2,
          maxTotalOutputBytes: 2,
          maxWorkspaceBytes: 5,
        ),
      );

      expect(target.validate, throwsArgumentError);
    });

    test('invalid provider policies are configuration errors', () {
      final empty = feasibilityProject([]);
      final media = feasibilityProject([
        feasibilityVideoLane('video', testSource('source', 'mp4')),
      ]);
      const invalid = FfmpegSafetyPolicy(maxInputBytes: 0);

      expect(
        () =>
            const EditorCompositionCompiler().preflight(empty, safety: invalid),
        throwsA(isA<FfmpegException>()),
      );
      expect(
        () =>
            const EditorCompositionCompiler().preflight(media, safety: invalid),
        throwsA(isA<FfmpegException>()),
      );
    });

    test('accepts every supported source role and extension', () {
      for (final extension in const [
        'mp4',
        'mov',
        'm4v',
        'webm',
        'mkv',
        'avi',
        'mpg',
        'mpeg',
        'png',
        'jpg',
        'jpeg',
        'webp',
      ]) {
        final source = testSource('video-$extension', extension);
        final result = preflightEditorRender(
          feasibilityProject([
            feasibilityVideoLane('video-$extension', source),
          ]),
        );
        expect(result.isStructurallyFeasible, isTrue, reason: '.$extension');
      }
      for (final extension in const [
        'mp4',
        'mov',
        'm4v',
        'm4a',
        'webm',
        'mkv',
        'mp3',
        'aac',
        'wav',
        'ogg',
        'opus',
        'flac',
      ]) {
        final source = testSource('audio-$extension', extension);
        final result = preflightEditorRender(
          feasibilityProject([
            feasibilityAudioLane('audio-$extension', source),
          ]),
        );
        expect(result.isStructurallyFeasible, isTrue, reason: '.$extension');
      }
    });

    test('exact layer and input maxima fit managed job bounds', () async {
      final sources = [
        for (var index = 0; index < 16; index++)
          testSource('maximum-source-$index', 'mp4'),
      ];
      final project = feasibilityProject([
        for (var index = 0; index < 24; index++)
          feasibilityVideoLane(
            'maximum-$index',
            sources[index % sources.length],
          ),
      ]);

      final report = preflightEditorRender(project);
      expect(report.isStructurallyFeasible, isTrue);
      expect(report.footprint!.emittedLayerCount, 24);
      expect(report.footprint!.totalInputCount, 16);

      final plan = await const EditorCompositionCompiler().compile(project);
      expect(plan.layers, hasLength(24));
      expect(plan.job.inputs, hasLength(16));
      expect(
        () => const FfmpegSafetyPolicy().validate(plan.job),
        returnsNormally,
      );
    });

    test('visual concurrency includes outgoing transition holds', () {
      final source = testSource('transition-source', 'mp4');
      final project = feasibilityProject([
        EditorLane(
          id: 'transition-lane',
          label: 'Transition',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'leaving-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(1),
              source: source,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(1),
              ),
            ),
            EditorVideoClip(
              id: 'arriving-clip',
              timelineStart: MediaTime.seconds(1),
              duration: MediaTime.seconds(1),
              source: source,
              sourceRange: MediaRange(
                start: MediaTime.seconds(1),
                duration: MediaTime.seconds(1),
              ),
              sourceDuration: MediaTime.seconds(2),
              transition: EditorTransition(
                kind: EditorTransitionKind.dissolve,
                duration: MediaTime.seconds(1),
              ),
            ),
          ],
        ),
      ]);

      final result = preflightEditorRender(project);
      expect(result.isStructurallyFeasible, isTrue);
      expect(result.footprint!.peakVisualConcurrency, 2);
    });

    testWidgets('prepared captions honor effective per-source limits', (
      tester,
    ) async {
      final captionLane = testProject().lanes.last;
      final caption = captionLane.clips.single as EditorCaptionClip;
      final raster = await tester.runAsync(
        () => const FlutterCaptionRasterizer().rasterize(
          EditorCaptionRasterRequest(
            clip: caption,
            canvasWidth: 640,
            canvasHeight: 360,
            limits: EditorLimits(),
          ),
          cancellation: EditorRenderCancellationToken(),
        ),
      );
      var rasterCalls = 0;
      final compiler = EditorCompositionCompiler(
        captionRasterizer: CallbackCaptionRasterizer((request, cancellation) {
          rasterCalls++;
          return Future.value(raster!);
        }),
      );

      final failure = await tester.runAsync(() async {
        try {
          await compiler.compile(
            feasibilityProject([captionLane]),
            safety: const FfmpegSafetyPolicy(maxInputBytes: 64),
          );
          return null;
        } on EditorValidationException catch (error) {
          return error;
        }
      });
      expect(failure, isA<EditorValidationException>());
      expect(rasterCalls, 1);
    });

    testWidgets('caption source IDs remain unique after collisions', (
      tester,
    ) async {
      final source = testSource('caption-0000-caption-clip', 'mp4');
      final project = testProject(videoSource: source);
      expect(preflightEditorRender(project).isStructurallyFeasible, isTrue);

      final plan = await tester.runAsync(
        () => const EditorCompositionCompiler().compile(project),
      );
      final sourceIds = plan!.composition.layers
          .map((layer) => layer.source.id)
          .toList();
      expect(sourceIds.toSet(), hasLength(sourceIds.length));
      expect(sourceIds, contains('caption-0000-caption-clip'));
      expect(sourceIds, contains('caption-0000-caption-clip-1'));
    });
  });
}
