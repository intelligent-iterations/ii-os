import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'render_feasibility_support.dart';
import 'support.dart';

void main() {
  group('render feasibility', () {
    test('reports exact footprint without preparing inputs', () {
      var sourceReads = 0;
      final source = MediaSource(
        id: 'counted-source',
        byteLength: 8,
        fileExtension: 'mp4',
        openRead: () {
          sourceReads++;
          throw StateError('preflight must not read media');
        },
      );

      final result = preflightEditorRender(
        testProject(videoSource: source, audioSource: source),
      );

      expect(result.isStructurallyFeasible, isTrue);
      expect(result.requiresPreparation, isTrue);
      expect(result.issues, isEmpty);
      expect(
        result.footprint,
        const EditorRenderFootprint(
          emittedLayerCount: 3,
          mediaInputCount: 1,
          captionInputCount: 1,
          declaredMediaBytes: 8,
          reservedCaptionBytes: 16 * 1024 * 1024,
          estimatedOutputBytes: 7740000,
          captionPixelCount: 36864,
          peakVisualConcurrency: 2,
          peakAudioConcurrency: 1,
        ),
      );
      expect(sourceReads, 0);
    });

    test('counts hidden and muted lanes exactly like compilation', () {
      final unsupported = testSource('unsupported', 'xyz');
      final project = feasibilityProject([
        feasibilityVideoLane('hidden-video', unsupported, hidden: true),
        feasibilityAudioLane('muted-audio', unsupported, muted: true),
        feasibilityCaptionLane('hidden-caption', count: 2, hidden: true),
      ]);

      final result = preflightEditorRender(project);

      expect(result.isStructurallyFeasible, isTrue);
      expect(
        result.footprint,
        const EditorRenderFootprint(
          emittedLayerCount: 0,
          mediaInputCount: 0,
          captionInputCount: 0,
          declaredMediaBytes: 0,
          reservedCaptionBytes: 0,
          estimatedOutputBytes: 46440000,
          captionPixelCount: 0,
          peakVisualConcurrency: 0,
          peakAudioConcurrency: 0,
        ),
      );
    });

    test('accepts 24 layers and rejects 25 sequential layers', () {
      final source = testSource('shared-layer-source', 'mp4');
      final exact = preflightEditorRender(
        feasibilityProject([feasibilityVideoLane('exact', source, count: 24)]),
      );
      final over = preflightEditorRender(
        feasibilityProject([feasibilityVideoLane('over', source, count: 25)]),
      );

      expect(exact.isStructurallyFeasible, isTrue);
      expect(exact.footprint!.emittedLayerCount, 24);
      expect(exact.footprint!.mediaInputCount, 1);
      expect(
        over.issues.singleWhere(
          (issue) =>
              issue.code == EditorRenderIssueCode.emittedLayerLimitExceeded,
        ),
        isA<EditorRenderIssue>()
            .having((issue) => issue.actual, 'actual', 25)
            .having((issue) => issue.maximum, 'maximum', 24),
      );
    });

    test('accepts 16 distinct inputs and rejects 17 without reads', () {
      var sourceReads = 0;
      MediaSource source(int index) => MediaSource(
        id: 'input-source-$index',
        byteLength: 1,
        fileExtension: 'mp4',
        openRead: () {
          sourceReads++;
          throw StateError('structural rejection must precede reads');
        },
      );
      EditorProject withCount(int count) => feasibilityProject([
        feasibilityVideoLane(
          'inputs',
          source(0),
          sources: [for (var index = 0; index < count; index++) source(index)],
        ),
      ]);

      expect(
        preflightEditorRender(withCount(16)).isStructurallyFeasible,
        isTrue,
      );
      final over = preflightEditorRender(withCount(17));
      expect(
        over.issues.singleWhere(
          (issue) => issue.code == EditorRenderIssueCode.inputLimitExceeded,
        ),
        isA<EditorRenderIssue>()
            .having((issue) => issue.actual, 'actual', 17)
            .having((issue) => issue.maximum, 'maximum', 16),
      );
      expect(sourceReads, 0);
    });

    test('accepts the exact estimated output budget and rejects one over', () {
      final project = feasibilityProject([]).copyWith(
        duration: MediaTime.seconds(8),
        output: const MediaOutputSettings(
          videoBitrate: 7000,
          audioBitrate: 1000,
        ),
      );
      final exact = preflightEditorRender(
        project,
        mediaLimits: const MediaLimits(
          maxOutputBytes: 9000,
          maxEstimatedOutputBytes: 8000,
        ),
      );
      final over = preflightEditorRender(
        project,
        mediaLimits: const MediaLimits(
          maxOutputBytes: 9000,
          maxEstimatedOutputBytes: 7999,
        ),
      );

      expect(exact.isStructurallyFeasible, isTrue);
      expect(exact.footprint!.estimatedOutputBytes, 8000);
      expect(
        over.issues.singleWhere(
          (issue) =>
              issue.code == EditorRenderIssueCode.estimatedOutputBytesExceeded,
        ),
        isA<EditorRenderIssue>()
            .having((issue) => issue.actual, 'actual', 8000)
            .having((issue) => issue.maximum, 'maximum', 7999),
      );
    });

    test('reserves caption bytes beyond the declared media allowance', () {
      MediaSource source(int bytes) => MediaSource(
        id: 'declared-media-$bytes',
        byteLength: bytes,
        fileExtension: 'mp4',
        openRead: () => throw StateError('preflight must not read media'),
      );
      EditorProject project(int bytes) => feasibilityProject([
        feasibilityVideoLane('video', source(bytes)),
        feasibilityCaptionLane('caption', count: 1),
      ]);
      const limits = EditorLimits(
        maxCaptionRasterBytes: 4,
        maxCaptionTotalRasterBytes: 4,
      );
      const media = MediaLimits(
        maxInputBytes: 12,
        maxDeclaredMediaBytes: 10,
        maxSourceBytes: 12,
      );

      final exact = preflightEditorRender(
        project(8),
        limits: limits,
        mediaLimits: media,
      );
      final over = preflightEditorRender(
        project(9),
        limits: limits,
        mediaLimits: media,
      );

      expect(exact.isStructurallyFeasible, isTrue);
      expect(exact.footprint!.declaredMediaBytes, 8);
      expect(exact.footprint!.reservedCaptionBytes, 4);
      expect(exact.footprint!.maximumPreparedInputBytes, 12);
      expect(
        over.issues.single,
        isA<EditorRenderIssue>()
            .having(
              (issue) => issue.code,
              'code',
              EditorRenderIssueCode.preparedInputBytesExceeded,
            )
            .having((issue) => issue.actual, 'actual', 13)
            .having((issue) => issue.maximum, 'maximum', 12),
      );
    });

    test('output estimate rounds only the final fractional byte', () {
      final base = feasibilityProject([]);
      EditorProject project(int microseconds) => base.copyWith(
        duration: MediaTime.microseconds(microseconds),
        output: const MediaOutputSettings(videoBitrate: 8, audioBitrate: 8),
      );

      expect(estimateEditorOutputBytes(project(1)), 1);
      expect(estimateEditorOutputBytes(project(500000)), 1);
      expect(estimateEditorOutputBytes(project(500001)), 2);
      expect(
        estimateEditorOutputBytes(
          base.copyWith(
            duration: MediaTime.seconds(7200),
            output: const MediaOutputSettings(
              videoBitrate: 100 * 1000 * 1000,
              audioBitrate: 1000 * 1000,
            ),
          ),
        ),
        90900000000,
      );
    });

    test('captions consume one emitted layer and input each', () {
      final exact = preflightEditorRender(
        feasibilityProject([feasibilityCaptionLane('captions', count: 16)]),
      );
      final over = preflightEditorRender(
        feasibilityProject([feasibilityCaptionLane('captions', count: 17)]),
      );

      expect(exact.isStructurallyFeasible, isTrue);
      expect(exact.footprint!.captionInputCount, 16);
      expect(exact.footprint!.emittedLayerCount, 16);
      expect(
        over.issues.map((issue) => issue.code),
        contains(EditorRenderIssueCode.inputLimitExceeded),
      );
    });

    test('reports byte, identity, and source-use blockers together', () {
      final tooLarge = MediaSource(
        id: 'large-source',
        byteLength: 5,
        fileExtension: 'mp4',
        openRead: () => throw StateError('must not read'),
      );
      final firstAlias = testSource('aliased-source', 'mp4');
      final secondAlias = testSource('aliased-source', 'mp4');
      final unsupported = testSource('unsupported-source', 'xyz');
      final result = preflightEditorRender(
        feasibilityProject([
          feasibilityVideoLane('large', tooLarge),
          feasibilityVideoLane('alias-a', firstAlias),
          feasibilityVideoLane('alias-b', secondAlias),
          feasibilityVideoLane('unsupported', unsupported),
        ]),
        mediaLimits: const MediaLimits(maxSourceBytes: 4, maxInputBytes: 8),
      );

      expect(
        result.issues.map((issue) => issue.code),
        containsAll({
          EditorRenderIssueCode.sourceByteLengthExceeded,
          EditorRenderIssueCode.declaredInputBytesExceeded,
          EditorRenderIssueCode.conflictingSourceIdentity,
          EditorRenderIssueCode.unsupportedSourceUse,
        }),
      );
    });

    test('reports caption pixel and output profile blockers', () {
      final result = preflightEditorRender(
        feasibilityProject(
          [feasibilityCaptionLane('caption', count: 2)],
          output: const MediaOutputSettings(
            container: MediaContainer.webm,
            videoCodec: MediaVideoCodec.h264,
            audioCodec: MediaAudioCodec.aac,
            videoBitrate: 101,
            audioBitrate: 11,
          ),
        ),
        limits: const EditorLimits(
          maxCaptionPixels: 30000,
          maxCaptionTotalPixels: 60000,
        ),
        mediaLimits: const MediaLimits(
          maxVideoBitrate: 100,
          maxAudioBitrate: 10,
        ),
      );

      expect(
        result.issues.map((issue) => issue.code),
        containsAll({
          EditorRenderIssueCode.captionPixelLimitExceeded,
          EditorRenderIssueCode.captionTotalPixelLimitExceeded,
          EditorRenderIssueCode.videoBitrateExceeded,
          EditorRenderIssueCode.audioBitrateExceeded,
          EditorRenderIssueCode.unsupportedOutputProfile,
        }),
      );
    });

    test('distinguishes invalid project and target configuration', () {
      final invalid = EditorProject(
        id: 'invalid-project',
        width: 641,
        height: 360,
        framesPerSecond: 30,
        duration: MediaTime.seconds(1),
        lanes: const [],
      );

      final result = preflightEditorRender(invalid);
      expect(result.footprint, isNull);
      expect(result.issues.single.code, EditorRenderIssueCode.invalidProject);
      expect(
        () => preflightEditorRender(
          feasibilityProject([]),
          limits: const EditorLimits(maxLanes: 25),
        ),
        throwsA(isA<EditorValidationException>()),
      );
      expect(
        () => preflightEditorRender(
          feasibilityProject([]),
          mediaLimits: const MediaLimits(maxInputCount: 17),
        ),
        throwsArgumentError,
      );
      expect(
        () => preflightEditorRender(
          feasibilityProject([]),
          mediaLimits: const MediaLimits(
            maxOutputBytes: 8,
            maxEstimatedOutputBytes: 9,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a destination whose rounded endpoint span is zero', () {
      final source = testSource('subpixel-source', 'mp4');
      final project = feasibilityProject([
        EditorLane(
          id: 'subpixel-lane',
          label: 'Subpixel',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'subpixel-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(1),
              source: source,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(1),
              ),
              destination: const MediaRect(
                x: 0.00078125,
                y: 0,
                width: 0.0009375,
                height: 1,
              ),
            ),
          ],
        ),
      ]);

      final result = preflightEditorRender(project);
      expect(result.footprint, isNull);
      expect(result.issues.single.code, EditorRenderIssueCode.invalidProject);
    });

    test('split accounting exposes occurrence and caption costs', () {
      final source = testSource('split-source', 'mp4');
      final videoBefore = feasibilityProject([
        feasibilityVideoLane('split', source, count: 24),
      ]);
      final videoAfter = splitEditorClip(
        project: videoBefore,
        selection: const EditorSelection(
          laneId: 'split-lane',
          clipId: 'split-clip-0',
        ),
        at: MediaTime.milliseconds(500),
      ).project;
      expect(preflightEditorRender(videoBefore).isStructurallyFeasible, isTrue);
      expect(
        preflightEditorRender(videoAfter).issues.map((issue) => issue.code),
        contains(EditorRenderIssueCode.emittedLayerLimitExceeded),
      );

      final captionBefore = feasibilityProject([
        feasibilityCaptionLane('caption-split', count: 1),
      ]);
      final before = preflightEditorRender(captionBefore).footprint!;
      final captionAfter = splitEditorClip(
        project: captionBefore,
        selection: const EditorSelection(
          laneId: 'caption-split-lane',
          clipId: 'caption-split-clip-0',
        ),
        at: MediaTime.milliseconds(500),
      ).project;
      final after = preflightEditorRender(captionAfter).footprint!;
      expect(after.emittedLayerCount, before.emittedLayerCount + 1);
      expect(after.totalInputCount, before.totalInputCount + 1);
      expect(after.captionPixelCount, before.captionPixelCount * 2);
    });

    test('splitting excluded lanes preserves the effective footprint', () {
      final source = testSource('excluded-split-source', 'mp4');
      final hidden = feasibilityProject([
        feasibilityVideoLane('hidden-split', source, hidden: true),
      ]);
      final hiddenAfter = splitEditorClip(
        project: hidden,
        selection: const EditorSelection(
          laneId: 'hidden-split-lane',
          clipId: 'hidden-split-clip-0',
        ),
        at: MediaTime.milliseconds(500),
      ).project;
      expect(
        preflightEditorRender(hiddenAfter).footprint,
        preflightEditorRender(hidden).footprint,
      );

      final muted = feasibilityProject([
        feasibilityAudioLane('muted-split', source, muted: true),
      ]);
      final mutedAfter = splitEditorClip(
        project: muted,
        selection: const EditorSelection(
          laneId: 'muted-split-lane',
          clipId: 'muted-split-clip',
        ),
        at: MediaTime.milliseconds(500),
      ).project;
      expect(
        preflightEditorRender(mutedAfter).footprint,
        preflightEditorRender(muted).footprint,
      );
    });
  });
}
