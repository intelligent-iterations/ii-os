import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

const _video = EditorSelection(laneId: 'video-lane', clipId: 'video-clip');
const _audio = EditorSelection(laneId: 'audio-lane', clipId: 'audio-clip');

EditorProject _twoVideoClips() =>
    sliceEditorProject(project: testProject(), at: MediaTime.seconds(4));

EditorVideoClip _clipAt(EditorProject project, String laneId, int index) =>
    project.laneById(laneId)!.clips[index] as EditorVideoClip;

void main() {
  group('slice', () {
    test('cuts every unlocked lane at one position', () {
      final sliced = sliceEditorProject(
        project: testProject(),
        at: MediaTime.seconds(4),
      );

      expect(sliced.laneById('video-lane')!.clips, hasLength(2));
      expect(sliced.laneById('audio-lane')!.clips, hasLength(2));
      expect(sliced.laneById('caption-lane')!.clips, hasLength(2));
      expect(_clipAt(sliced, 'video-lane', 0).duration, MediaTime.seconds(4));
      expect(
        _clipAt(sliced, 'video-lane', 1).timelineStart,
        MediaTime.seconds(4),
      );
      expect(
        _clipAt(sliced, 'video-lane', 1).sourceRange.start,
        MediaTime.seconds(5),
      );
    });

    test('leaves a locked lane whole', () {
      final sliced = sliceEditorProject(
        project: testProject(lockedVideo: true),
        at: MediaTime.seconds(4),
      );

      expect(sliced.laneById('video-lane')!.clips, hasLength(1));
      expect(sliced.laneById('audio-lane')!.clips, hasLength(2));
    });

    test('refuses a position with nothing under it', () {
      expect(
        () => sliceEditorProject(
          project: testProject(),
          at: MediaTime.seconds(9),
        ),
        throwsA(isA<EditorValidationException>()),
      );
      expect(
        canSliceEditorProject(testProject(), MediaTime.seconds(9)),
        isFalse,
      );
      expect(
        canSliceEditorProject(testProject(), MediaTime.seconds(4)),
        isTrue,
      );
    });

    test('slices linked media once, not twice', () {
      final sliced = sliceEditorProject(
        project: testProject(linkPrimaryMedia: true),
        at: MediaTime.seconds(4),
      );

      expect(sliced.laneById('video-lane')!.clips, hasLength(2));
      expect(sliced.laneById('audio-lane')!.clips, hasLength(2));
    });
  });

  group('remove span', () {
    test('closes the gap and shortens the project', () {
      final shortened = removeEditorSpan(
        project: testProject(),
        from: MediaTime.seconds(2),
        to: MediaTime.seconds(4),
      );

      expect(shortened.duration, MediaTime.seconds(8));
      final clips = shortened.laneById('video-lane')!.clips;
      expect(clips, hasLength(2));
      expect(clips[0].timelineStart, MediaTime.zero);
      expect(clips[0].duration, MediaTime.seconds(2));
      expect(clips[1].timelineStart, MediaTime.seconds(2));
      expect(clips[1].duration, MediaTime.seconds(4));
      expect(
        (clips[1] as EditorVideoClip).sourceRange.start,
        MediaTime.seconds(5),
      );
    });

    test('trims a clip that only starts inside the span', () {
      final shortened = removeEditorSpan(
        project: testProject(),
        from: MediaTime.seconds(2),
        to: MediaTime.seconds(4),
      );

      final caption =
          shortened.laneById('caption-lane')!.clips.single as EditorCaptionClip;
      expect(caption.timelineStart, MediaTime.seconds(2));
      expect(caption.duration, MediaTime.seconds(1));
    });

    test('leaves a gap when the ripple is off', () {
      final shortened = removeEditorSpan(
        project: testProject(),
        from: MediaTime.seconds(2),
        to: MediaTime.seconds(4),
        ripple: false,
      );

      expect(shortened.duration, MediaTime.seconds(10));
      final clips = shortened.laneById('video-lane')!.clips;
      expect(clips[1].timelineStart, MediaTime.seconds(4));
    });

    test('drops a clip that sits wholly inside the span', () {
      final shortened = removeEditorSpan(
        project: testProject(),
        from: MediaTime.seconds(1),
        to: MediaTime.seconds(6),
        ripple: false,
      );

      expect(shortened.laneById('caption-lane')!.clips, isEmpty);
    });

    test('refuses an empty or reversed span', () {
      for (final span in [
        (MediaTime.seconds(4), MediaTime.seconds(4)),
        (MediaTime.seconds(5), MediaTime.seconds(2)),
      ]) {
        expect(
          () => removeEditorSpan(
            project: testProject(),
            from: span.$1,
            to: span.$2,
          ),
          throwsA(isA<EditorValidationException>()),
        );
      }
    });

    test('refuses to remove everything', () {
      expect(
        () => removeEditorSpan(
          project: testProject(),
          from: MediaTime.zero,
          to: MediaTime.seconds(10),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    });

    test('refuses while a lane covering the span is locked', () {
      expect(
        () => removeEditorSpan(
          project: testProject(lockedVideo: true),
          from: MediaTime.seconds(2),
          to: MediaTime.seconds(4),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    });
  });

  group('detach audio', () {
    test('unlinks the picture from its sound', () {
      final detached = detachEditorClipAudio(
        project: testProject(linkPrimaryMedia: true),
        selection: _video,
      );

      expect(detached.clipById('video-clip')!.linkGroupId, isNull);
      expect(detached.clipById('audio-clip')!.linkGroupId, isNull);
    });

    test('lets the picture move without its sound', () {
      final detached = detachEditorClipAudio(
        project: testProject(linkPrimaryMedia: true),
        selection: _video,
      );
      final moved = moveEditorClip(
        project: detached,
        selection: _video,
        targetLaneId: 'video-lane',
        timelineStart: MediaTime.seconds(1),
      );

      expect(moved.clipById('video-clip')!.timelineStart, MediaTime.seconds(1));
      expect(moved.clipById('audio-clip')!.timelineStart, MediaTime.zero);
    });

    test('reads as available only while the two are still joined', () {
      final joined = testProject(linkPrimaryMedia: true);
      expect(canDetachEditorClipAudio(joined, _video), isTrue);
      expect(canDetachEditorClipAudio(joined, _audio), isTrue);
      expect(canDetachEditorClipAudio(testProject(), _video), isFalse);
      expect(canDetachEditorClipAudio(joined, null), isFalse);
    });

    test('refuses when nothing is joined', () {
      expect(
        () => detachEditorClipAudio(project: testProject(), selection: _video),
        throwsA(isA<EditorValidationException>()),
      );
    });

    test('refuses while either lane is locked', () {
      expect(
        () => detachEditorClipAudio(
          project: testProject(linkPrimaryMedia: true, lockedVideo: true),
          selection: _video,
        ),
        throwsA(isA<EditorValidationException>()),
      );
    });
  });

  group('transitions', () {
    test('joins two clips at a cut', () {
      final withTransition = setEditorClipTransition(
        project: _twoVideoClips(),
        selection: const EditorSelection(
          laneId: 'video-lane',
          clipId: 'video-clip.s4000000',
        ),
        transition: EditorTransition(
          kind: EditorTransitionKind.dissolve,
          duration: MediaTime.seconds(1),
        ),
      );

      final clip = _clipAt(withTransition, 'video-lane', 1);
      expect(clip.transition!.kind, EditorTransitionKind.dissolve);
      expect(clip.transition!.duration, MediaTime.seconds(1));
      expect(_clipAt(withTransition, 'video-lane', 0).transition, isNull);
    });

    test('opens a project that starts with one', () {
      final opened = setEditorClipTransition(
        project: testProject(),
        selection: _video,
        transition: EditorTransition(
          kind: EditorTransitionKind.dipToColor,
          duration: MediaTime.seconds(1),
          color: 'FFFFFF',
        ),
      );

      expect(opened.clipById('video-clip'), isA<EditorVideoClip>());
      expect(
        (opened.clipById('video-clip') as EditorVideoClip).transition!.color,
        'FFFFFF',
      );
    });

    test('refuses one longer than the clips it joins', () {
      expect(
        () => setEditorClipTransition(
          project: _twoVideoClips(),
          selection: const EditorSelection(
            laneId: 'video-lane',
            clipId: 'video-clip.s4000000',
          ),
          transition: EditorTransition(
            kind: EditorTransitionKind.dissolve,
            duration: MediaTime.seconds(6),
          ),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    });

    test('refuses one shorter than a frame', () {
      expect(
        () => setEditorClipTransition(
          project: testProject(),
          selection: _video,
          transition: EditorTransition(
            kind: EditorTransitionKind.dissolve,
            duration: MediaTime.microseconds(1000),
          ),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    });

    test('refuses one on a sound clip', () {
      expect(
        () => setEditorClipTransition(
          project: testProject(),
          selection: _audio,
          transition: EditorTransition(
            kind: EditorTransitionKind.dissolve,
            duration: MediaTime.seconds(1),
          ),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    });

    test('reports the longest one a cut can hold', () {
      final project = _twoVideoClips();
      expect(
        maxEditorTransitionDuration(
          project,
          const EditorSelection(
            laneId: 'video-lane',
            clipId: 'video-clip.s4000000',
          ),
        ),
        MediaTime.seconds(4),
      );
      expect(
        maxEditorTransitionDuration(project, _video),
        MediaTime.seconds(4),
      );
      expect(maxEditorTransitionDuration(project, _audio), MediaTime.zero);
    });

    test('caps the longest one at five seconds', () {
      expect(
        maxEditorTransitionDuration(testProject(), _video),
        MediaTime.seconds(5),
      );
    });

    test('stays with the earlier half when the clip is cut', () {
      final opened = setEditorClipTransition(
        project: testProject(),
        selection: _video,
        transition: EditorTransition(
          kind: EditorTransitionKind.dissolve,
          duration: MediaTime.seconds(1),
        ),
      );
      final sliced = sliceEditorProject(
        project: opened,
        at: MediaTime.seconds(4),
      );

      expect(_clipAt(sliced, 'video-lane', 0).transition, isNotNull);
      expect(_clipAt(sliced, 'video-lane', 1).transition, isNull);
    });

    test('clears one that is no longer wanted', () {
      final opened = setEditorClipTransition(
        project: testProject(),
        selection: _video,
        transition: EditorTransition(
          kind: EditorTransitionKind.dissolve,
          duration: MediaTime.seconds(1),
        ),
      );

      final cleared = clearEditorClipTransition(
        project: opened,
        selection: _video,
      );
      expect(
        (cleared.clipById('video-clip') as EditorVideoClip).transition,
        isNull,
      );
    });

    test('refuses a colour that is not six hex digits', () {
      expect(
        () => setEditorClipTransition(
          project: testProject(),
          selection: _video,
          transition: EditorTransition(
            kind: EditorTransitionKind.dipToColor,
            duration: MediaTime.seconds(1),
            color: 'red',
          ),
        ),
        throwsA(isA<EditorValidationException>()),
      );
    });
  });
}
