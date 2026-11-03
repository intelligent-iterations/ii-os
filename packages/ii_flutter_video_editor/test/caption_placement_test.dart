import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  group('placeEditorCaption', () {
    test('reuses the topmost caption lane at both half-open boundaries', () {
      final original = testProject();
      final audioAfterCaption = original.copyWith(
        lanes: [original.lanes[0], original.lanes[2], original.lanes[1]],
      );

      final after = placeEditorCaption(
        project: audioAfterCaption,
        caption: _caption('after', 5, 2),
        newLaneId: 'unused-after-lane',
        newLaneLabel: 'Subtitle',
      );
      final before = placeEditorCaption(
        project: after,
        caption: _caption('before', 0, 2),
        newLaneId: 'unused-before-lane',
        newLaneLabel: 'Text overlay',
      );

      expect(before.lanes, hasLength(original.lanes.length));
      expect(before.lanes.map((lane) => lane.id), [
        'video-lane',
        'caption-lane',
        'audio-lane',
      ]);
      expect(before.laneById('caption-lane')!.clips.map((clip) => clip.id), [
        'before',
        'caption-clip',
        'after',
      ]);
      expect(before.laneById('caption-lane')!.label, 'Captions');
      expect(before.lanes[0], same(original.lanes[0]));
      expect(before.lanes[2], same(original.lanes[1]));
      expect(() => validateEditorProject(before), returnsNormally);
    });

    test('one microsecond of overlap creates a fresh topmost lane', () {
      final original = testProject();

      final result = placeEditorCaption(
        project: original,
        caption: EditorCaptionClip(
          id: 'overlap',
          timelineStart: MediaTime.microseconds(4999999),
          duration: MediaTime.seconds(1),
          text: 'Overlap',
        ),
        newLaneId: 'fresh-caption-lane',
        newLaneLabel: 'Subtitle',
      );

      expect(result.lanes.last.id, 'fresh-caption-lane');
      expect(result.laneById('caption-lane'), same(original.lanes.last));
    });

    test('one microsecond of overlap at the leading edge also appends', () {
      final original = testProject();

      final result = placeEditorCaption(
        project: original,
        caption: EditorCaptionClip(
          id: 'leading-overlap',
          timelineStart: MediaTime.seconds(1),
          duration: MediaTime.microseconds(1000001),
          text: 'Leading overlap',
        ),
        newLaneId: 'leading-overlap-lane',
        newLaneLabel: 'Captions',
      );

      expect(result.lanes.last.id, 'leading-overlap-lane');
      expect(result.laneById('caption-lane'), same(original.lanes.last));
    });

    test('does not reuse a caption lane below a later visual lane', () {
      final original = testProject();
      final laterVisual = EditorLane(
        id: 'later-video-lane',
        label: 'Later video',
        kind: EditorLaneKind.video,
        clips: [
          EditorVideoClip(
            id: 'later-video-clip',
            timelineStart: MediaTime.zero,
            duration: MediaTime.seconds(1),
            source: testSource('later-video-source', 'mp4'),
            sourceRange: MediaRange(
              start: MediaTime.zero,
              duration: MediaTime.seconds(1),
            ),
          ),
        ],
      );
      final layered = original.copyWith(
        lanes: [...original.lanes, laterVisual],
      );

      final result = placeEditorCaption(
        project: layered,
        caption: _caption('must-stay-above-video', 5, 1),
        newLaneId: 'top-caption-lane',
        newLaneLabel: 'Subtitle',
      );

      expect(result.lanes.last.id, 'top-caption-lane');
      expect(result.laneById('caption-lane'), same(original.lanes.last));
    });

    test('does not mutate hidden or locked topmost caption lanes', () {
      for (final flags in [
        (hidden: true, locked: false),
        (hidden: false, locked: true),
      ]) {
        final original = testProject();
        final protectedLane = original.lanes.last.copyWith(
          hidden: flags.hidden,
          locked: flags.locked,
        );
        final protected = original.copyWith(
          lanes: [...original.lanes.take(2), protectedLane],
        );

        final result = placeEditorCaption(
          project: protected,
          caption: _caption('protected-${flags.hidden}-${flags.locked}', 5, 1),
          newLaneId: 'fresh-${flags.hidden}-${flags.locked}',
          newLaneLabel: 'Captions',
        );

        expect(result.lanes.last.id, 'fresh-${flags.hidden}-${flags.locked}');
        expect(result.laneById('caption-lane'), same(protectedLane));
      }
    });

    test('does not pack downward when the top caption lane overlaps', () {
      final original = testProject();
      final lowerFree = EditorLane(
        id: 'lower-caption-lane',
        label: 'Free lower captions',
        kind: EditorLaneKind.captions,
        clips: [_caption('lower-caption', 7, 1)],
      );
      final layered = original.copyWith(
        lanes: [
          original.lanes[0],
          lowerFree,
          original.lanes[1],
          original.lanes[2],
        ],
      );

      final result = placeEditorCaption(
        project: layered,
        caption: _caption('overlap-top-only', 3, 1),
        newLaneId: 'new-top-caption',
        newLaneLabel: 'Captions',
      );

      expect(result.lanes.last.id, 'new-top-caption');
      expect(result.laneById('lower-caption-lane'), same(lowerFree));
      expect(result.laneById('caption-lane'), same(original.lanes[2]));
    });

    test('keeps current input and layer accounting when a lane is reused', () {
      final original = testProject();
      final before = preflightEditorRender(original).footprint!;

      final placed = placeEditorCaption(
        project: original,
        caption: _caption('second-caption', 5, 1),
        newLaneId: 'unused-second-caption-lane',
        newLaneLabel: 'Captions',
      );
      final after = preflightEditorRender(placed).footprint!;

      expect(placed.lanes, hasLength(original.lanes.length));
      expect(after.captionInputCount, before.captionInputCount + 1);
      expect(after.totalInputCount, before.totalInputCount + 1);
      expect(after.emittedLayerCount, before.emittedLayerCount + 1);
    });

    test('rejects grouped or duplicate caption occurrences', () {
      final original = testProject();
      expect(
        () => placeEditorCaption(
          project: original,
          caption: EditorCaptionClip(
            id: 'grouped-caption',
            linkGroupId: 'unexpected-caption-group',
            timelineStart: MediaTime.seconds(5),
            duration: MediaTime.seconds(1),
            text: 'Grouped',
          ),
          newLaneId: 'unused-grouped-lane',
          newLaneLabel: 'Captions',
        ),
        throwsA(isA<EditorValidationException>()),
      );
      expect(
        () => placeEditorCaption(
          project: original,
          caption: _caption('caption-clip', 5, 1),
          newLaneId: 'unused-duplicate-lane',
          newLaneLabel: 'Captions',
        ),
        throwsA(isA<EditorValidationException>()),
      );
      expect(
        () => placeEditorCaption(
          project: original,
          caption: _caption('video-source', 4, 1),
          newLaneId: 'video-source',
          newLaneLabel: 'Captions',
        ),
        throwsA(isA<EditorValidationException>()),
      );
      expect(original.laneById('caption-lane')!.clips, hasLength(1));
    });

    test('reuses at the lane ceiling but rejects a required new lane', () {
      final original = testProject();
      final fillers = [
        for (var index = 0; index < 21; index++)
          EditorLane(
            id: 'audio-filler-$index',
            label: 'Audio filler $index',
            kind: EditorLaneKind.audio,
            clips: const [],
          ),
      ];
      final atLimit = original.copyWith(
        lanes: [...original.lanes.take(2), ...fillers, original.lanes.last],
      );

      final reused = placeEditorCaption(
        project: atLimit,
        caption: _caption('at-limit-adjacent', 5, 1),
        newLaneId: 'unused-at-limit',
        newLaneLabel: 'Captions',
      );
      expect(reused.lanes, hasLength(24));
      expect(reused.lanes.last.id, 'caption-lane');

      expect(
        () => placeEditorCaption(
          project: atLimit,
          caption: _caption('at-limit-overlap', 4, 1),
          newLaneId: 'over-limit-lane',
          newLaneLabel: 'Captions',
        ),
        throwsA(isA<EditorValidationException>()),
      );
      expect(atLimit.lanes, hasLength(24));
      expect(atLimit.clipById('at-limit-overlap'), isNull);
    });
  });
}

EditorCaptionClip _caption(String id, int startSeconds, int durationSeconds) =>
    EditorCaptionClip(
      id: id,
      timelineStart: MediaTime.seconds(startSeconds),
      duration: MediaTime.seconds(durationSeconds),
      text: id,
    );
