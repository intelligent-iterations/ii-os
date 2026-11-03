import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  test('ripple rejects a locked follower without mutating the project', () {
    final project = _withLockedCaption(
      start: MediaTime.seconds(4),
      duration: MediaTime.seconds(1),
    );
    final lane = project.laneById('caption-lane')!;
    final clip = lane.clips.single;

    expect(
      () => removeEditorSpan(
        project: project,
        from: MediaTime.seconds(2),
        to: MediaTime.seconds(4),
      ),
      throwsA(
        isA<EditorValidationException>().having(
          (error) => error.message,
          'message',
          'A locked lane would change when this span is removed. '
              'Unlock it or choose a span after its last clip.',
        ),
      ),
    );
    expect(project.laneById('caption-lane'), same(lane));
    expect(project.clipById('caption-clip'), same(clip));
    expect(clip.timelineStart, MediaTime.seconds(4));
  });

  test('ripple keeps an unaffected locked lane identical', () {
    final project = _withLockedCaption(
      start: MediaTime.seconds(1),
      duration: MediaTime.seconds(1),
    );
    final lane = project.laneById('caption-lane')!;
    final clip = lane.clips.single;

    final shortened = removeEditorSpan(
      project: project,
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
    );

    expect(shortened.laneById('caption-lane'), same(lane));
    expect(shortened.clipById('caption-clip'), same(clip));
  });

  test('non-ripple keeps a locked clip at the exact end boundary', () {
    final project = _withLockedCaption(
      start: MediaTime.seconds(4),
      duration: MediaTime.seconds(1),
    );
    final lane = project.laneById('caption-lane')!;
    final clip = lane.clips.single;

    final shortened = removeEditorSpan(
      project: project,
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
      ripple: false,
    );

    expect(shortened.laneById('caption-lane'), same(lane));
    expect(shortened.clipById('caption-clip'), same(clip));
  });

  test('non-ripple rejects a locked linked follower at the end boundary', () {
    final original = testProject(linkPrimaryMedia: true);
    final audioLane = original.laneById('audio-lane')!;
    final audio = audioLane.clips.single as EditorAudioClip;
    final lockedAudioLane = EditorLane(
      id: audioLane.id,
      label: audioLane.label,
      kind: audioLane.kind,
      locked: true,
      hidden: audioLane.hidden,
      muted: audioLane.muted,
      clips: [
        EditorAudioClip(
          id: audio.id,
          linkGroupId: audio.linkGroupId,
          timelineStart: MediaTime.seconds(4),
          duration: MediaTime.seconds(4),
          source: audio.source,
          sourceRange: MediaRange(
            start: audio.sourceRange.start,
            duration: MediaTime.seconds(4),
          ),
          sourceDuration: audio.sourceDuration,
          volume: audio.volume,
        ),
      ],
    );
    final project = original.copyWith(
      lanes: [original.lanes.first, lockedAudioLane, original.lanes.last],
    );

    expect(
      () => removeEditorSpan(
        project: project,
        from: MediaTime.seconds(2),
        to: MediaTime.seconds(4),
        ripple: false,
      ),
      throwsA(isA<EditorValidationException>()),
    );
    expect(project.laneById(audioLane.id), same(lockedAudioLane));
    expect(project.clipById(audio.id), same(lockedAudioLane.clips.single));
  });

  test('ripple rejects one microsecond beyond the safe boundary', () {
    final project = _withLockedCaption(
      start: MediaTime.seconds(1),
      duration: MediaTime.microseconds(1000001),
    );

    expect(
      () => removeEditorSpan(
        project: project,
        from: MediaTime.seconds(2),
        to: MediaTime.seconds(4),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('locked-span admission matches the exact interval predicate', () {
    final from = MediaTime.seconds(2);
    final to = MediaTime.seconds(4);
    for (final ripple in [true, false]) {
      for (var startSeconds = 0; startSeconds <= 5; startSeconds++) {
        for (var endSeconds = startSeconds + 1; endSeconds <= 6; endSeconds++) {
          final start = MediaTime.seconds(startSeconds);
          final end = MediaTime.seconds(endSeconds);
          final project = _withLockedCaption(
            start: start,
            duration: end - start,
          );
          final lane = project.laneById('caption-lane')!;
          final shouldReject = ripple ? end > from : start < to && end > from;

          if (shouldReject) {
            expect(
              () => removeEditorSpan(
                project: project,
                from: from,
                to: to,
                ripple: ripple,
              ),
              throwsA(isA<EditorValidationException>()),
              reason: 'ripple=$ripple range=[$startSeconds,$endSeconds)',
            );
          } else {
            final result = removeEditorSpan(
              project: project,
              from: from,
              to: to,
              ripple: ripple,
            );
            expect(result.laneById(lane.id), same(lane));
            expect(() => validateEditorProject(result), returnsNormally);
          }
        }
      }
    }
  });

  test('keeps an empty locked lane identical', () {
    final original = testProject();
    final empty = EditorLane(
      id: 'empty-locked-lane',
      label: 'Protected',
      kind: EditorLaneKind.video,
      locked: true,
      clips: const [],
    );
    final project = original.copyWith(lanes: [...original.lanes, empty]);

    final shortened = removeEditorSpan(
      project: project,
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
    );

    expect(shortened.laneById(empty.id), same(empty));
  });

  test('linked tails keep one new editing group', () {
    final shortened = removeEditorSpan(
      project: testProject(linkPrimaryMedia: true),
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
    );

    final video = shortened.laneById('video-lane')!.clips;
    final audio = shortened.laneById('audio-lane')!.clips;
    expect(video, hasLength(2));
    expect(audio, hasLength(2));
    expect(video.first.linkGroupId, 'primary-media');
    expect(audio.first.linkGroupId, 'primary-media');
    expect(video.last.linkGroupId, isNot('primary-media'));
    expect(audio.last.linkGroupId, video.last.linkGroupId);
  });

  test('non-ripple gap keeps a disjoint linked group intact', () {
    final original = testProject(linkPrimaryMedia: true);
    final videoLane = original.laneById('video-lane')!;
    final audioLane = original.laneById('audio-lane')!;
    final video = videoLane.clips.single;
    final audio = audioLane.clips.single;
    final shortVideo = rebuildEditorClip(video, duration: MediaTime.seconds(1));
    final lateAudio = rebuildEditorClip(
      audio,
      timelineStart: MediaTime.seconds(4),
      duration: MediaTime.seconds(1),
    );
    final project = original.copyWith(
      lanes: [
        videoLane.copyWith(clips: [shortVideo]),
        audioLane.copyWith(clips: [lateAudio]),
        original.lanes.last,
      ],
    );

    final unchanged = removeEditorSpan(
      project: project,
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(3),
      ripple: false,
    );

    expect(unchanged.clipById(video.id), same(shortVideo));
    expect(unchanged.clipById(audio.id), same(lateAudio));
    expect(unchanged.clipById(video.id)!.linkGroupId, 'primary-media');
    expect(unchanged.clipById(audio.id)!.linkGroupId, 'primary-media');
  });

  test('a shifted linked follower joins the same tail partition', () {
    final original = testProject(linkPrimaryMedia: true);
    final audioLane = original.laneById('audio-lane')!;
    final audio = audioLane.clips.single as EditorAudioClip;
    final project = original.copyWith(
      lanes: [
        original.lanes.first,
        audioLane.copyWith(
          clips: [
            EditorAudioClip(
              id: audio.id,
              linkGroupId: audio.linkGroupId,
              timelineStart: MediaTime.seconds(4),
              duration: MediaTime.seconds(4),
              source: audio.source,
              sourceRange: MediaRange(
                start: audio.sourceRange.start,
                duration: MediaTime.seconds(4),
              ),
              sourceDuration: audio.sourceDuration,
              volume: audio.volume,
            ),
          ],
        ),
        original.lanes.last,
      ],
    );

    final shortened = removeEditorSpan(
      project: project,
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
    );
    final videoTail = shortened.laneById('video-lane')!.clips.last;
    final audioFollower = shortened.laneById('audio-lane')!.clips.single;

    expect(audioFollower.timelineStart, MediaTime.seconds(2));
    expect(audioFollower.linkGroupId, videoTail.linkGroupId);
    expect(audioFollower.linkGroupId, isNot('primary-media'));
  });

  test('linked tail identifiers avoid existing project namespaces', () {
    final original = testProject(linkPrimaryMedia: true);
    final captionLane = original.laneById('caption-lane')!;
    final caption = captionLane.clips.single as EditorCaptionClip;
    final project = original.copyWith(
      lanes: [
        ...original.lanes.take(2),
        captionLane.copyWith(
          clips: [
            EditorCaptionClip(
              id: 'video-clip.x2000000',
              linkGroupId: 'primary-media.x2000000',
              timelineStart: caption.timelineStart,
              duration: caption.duration,
              text: caption.text,
              destination: caption.destination,
              style: caption.style,
            ),
          ],
        ),
      ],
    );

    final shortened = removeEditorSpan(
      project: project,
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
    );
    final video = shortened.laneById('video-lane')!.clips;
    final audio = shortened.laneById('audio-lane')!.clips;

    expect(video.last.id, 'video-clip.x2000000-2');
    expect(video.last.linkGroupId, 'primary-media.x2000000-2');
    expect(audio.last.linkGroupId, video.last.linkGroupId);
    expect(() => validateEditorProject(shortened), returnsNormally);
  });

  test('span edits never open media sources', () {
    var reads = 0;
    final source = MediaSource(
      id: 'counted-source',
      byteLength: 1,
      fileExtension: 'mp4',
      openRead: () {
        reads++;
        return Stream.value(const [0]);
      },
    );
    final accepted = testProject(videoSource: source);
    final rejected = _withLockedCaption(
      start: MediaTime.seconds(4),
      duration: MediaTime.seconds(1),
    );

    removeEditorSpan(
      project: accepted,
      from: MediaTime.seconds(2),
      to: MediaTime.seconds(4),
    );
    expect(
      () => removeEditorSpan(
        project: rejected,
        from: MediaTime.seconds(2),
        to: MediaTime.seconds(4),
      ),
      throwsA(isA<EditorValidationException>()),
    );
    expect(reads, 0);
  });
}

EditorProject _withLockedCaption({
  required MediaTime start,
  required MediaTime duration,
}) {
  final project = testProject();
  final lane = project.laneById('caption-lane')!;
  final caption = lane.clips.single as EditorCaptionClip;
  return project.copyWith(
    lanes: [
      for (final candidate in project.lanes)
        candidate.id == lane.id
            ? EditorLane(
                id: lane.id,
                label: lane.label,
                kind: lane.kind,
                locked: true,
                hidden: lane.hidden,
                muted: lane.muted,
                clips: [
                  EditorCaptionClip(
                    id: caption.id,
                    linkGroupId: caption.linkGroupId,
                    timelineStart: start,
                    duration: duration,
                    text: caption.text,
                    destination: caption.destination,
                    style: caption.style,
                  ),
                ],
              )
            : candidate,
    ],
  );
}
