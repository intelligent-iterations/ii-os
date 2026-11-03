import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  test('validates a multi-lane project', () {
    expect(() => validateEditorProject(testProject()), returnsNormally);
  });

  test('rejects overlap inside one lane', () {
    final project = testProject();
    final lane = project.lanes.first;
    final source = (lane.clips.first as EditorVideoClip).source;
    final overlapping = EditorVideoClip(
      id: 'overlap',
      timelineStart: MediaTime.seconds(4),
      duration: MediaTime.seconds(2),
      source: source,
      sourceRange: MediaRange(
        start: MediaTime.zero,
        duration: MediaTime.seconds(2),
      ),
    );
    final invalid = project.copyWith(
      lanes: [
        lane.copyWith(clips: [...lane.clips, overlapping]),
        ...project.lanes.skip(1),
      ],
    );

    expect(
      () => validateEditorProject(invalid),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('rejects a clip in the wrong lane kind', () {
    final project = testProject();
    final invalidLane = EditorLane(
      id: 'wrong-lane',
      label: 'Wrong',
      kind: EditorLaneKind.audio,
      clips: [project.lanes.first.clips.first],
    );

    expect(
      () => validateEditorProject(project.copyWith(lanes: [invalidLane])),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('rejects caption control characters', () {
    final project = testProject();
    final captionLane = project.lanes.last;
    final caption = captionLane.clips.single as EditorCaptionClip;
    final invalid = EditorCaptionClip(
      id: caption.id,
      timelineStart: caption.timelineStart,
      duration: caption.duration,
      text: 'bad\u0000caption',
    );

    expect(
      () => validateEditorProject(
        project.copyWith(
          lanes: [
            ...project.lanes.take(2),
            captionLane.copyWith(clips: [invalid]),
          ],
        ),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('rejects UI-hostile project duration and canvas bounds', () {
    final project = testProject();
    expect(
      () => validateEditorProject(
        EditorProject(
          id: project.id,
          width: 8192,
          height: 8192,
          framesPerSecond: project.framesPerSecond,
          duration: project.duration,
          lanes: project.lanes,
        ),
      ),
      throwsA(isA<EditorValidationException>()),
    );
    expect(
      () => validateEditorProject(
        project.copyWith(duration: MediaTime.seconds(60 * 60)),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('caller limits cannot exceed package hard safety ceilings', () {
    for (final limits in [
      const EditorLimits(maxLanes: 25),
      const EditorLimits(maxClips: 257),
      const EditorLimits(maxCaptionCharacters: 4001),
      const EditorLimits(maxCaptionRasterBytes: 16 * 1024 * 1024 + 1),
      const EditorLimits(maxCaptionPixels: 16 * 1024 * 1024 + 1),
      const EditorLimits(maxCaptionTotalRasterBytes: 64 * 1024 * 1024 + 1),
      const EditorLimits(maxCaptionTotalPixels: 64 * 1024 * 1024 + 1),
    ]) {
      expect(limits.validateSelf, throwsA(isA<EditorValidationException>()));
    }
    for (final limits in [
      const MediaLimits(maxLayerCount: 25),
      const MediaLimits(maxInputBytes: 512 * 1024 * 1024 + 1),
      const MediaLimits(maxInputBytes: 8, maxDeclaredMediaBytes: 9),
      const MediaLimits(maxOutputBytes: 512 * 1024 * 1024 + 1),
      const MediaLimits(maxVideoBitrate: 100 * 1000 * 1000 + 1),
      const MediaLimits(maxAudioBitrate: 1000 * 1000 + 1),
    ]) {
      expect(limits.validateSelf, throwsArgumentError);
    }
  });

  test('split preserves exact source and timeline coverage', () {
    final project = testProject();
    final result = splitEditorClip(
      project: project,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      at: MediaTime.seconds(3),
    );
    final clips = result.project.lanes.first.clips.cast<EditorVideoClip>();

    expect(clips, hasLength(2));
    expect(clips[0].id, 'video-clip');
    expect(clips[0].duration, MediaTime.seconds(3));
    expect(clips[0].sourceRange.start, MediaTime.seconds(1));
    expect(clips[1].timelineStart, MediaTime.seconds(3));
    expect(clips[1].duration, MediaTime.seconds(5));
    expect(clips[1].sourceRange.start, MediaTime.seconds(4));
    expect(clips[1].sourceRange.end, MediaTime.seconds(9));
    expect(result.selection.clipId, clips[1].id);
    expect(() => validateEditorProject(result.project), returnsNormally);
  });

  test('split refuses a locked lane and an edge position', () {
    expect(
      () => splitEditorClip(
        project: testProject(lockedVideo: true),
        selection: const EditorSelection(
          laneId: 'video-lane',
          clipId: 'video-clip',
        ),
        at: MediaTime.seconds(3),
      ),
      throwsA(isA<EditorValidationException>()),
    );
    expect(
      () => splitEditorClip(
        project: testProject(),
        selection: const EditorSelection(
          laneId: 'video-lane',
          clipId: 'video-clip',
        ),
        at: MediaTime.zero,
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('remove clip leaves a gap and removes linked media together', () {
    final project = testProject(linkPrimaryMedia: true);
    final removed = removeEditorClip(
      project: project,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
    );

    expect(removed.clipById('video-clip'), isNull);
    expect(removed.clipById('audio-clip'), isNull);
    expect(removed.clipById('caption-clip'), isNotNull);
    expect(removed.duration, project.duration);
    expect(() => validateEditorProject(removed), returnsNormally);
  });

  test('remove clip refuses a locked member of linked media', () {
    final project = testProject(lockedVideo: true, linkPrimaryMedia: true);
    const selection = EditorSelection(
      laneId: 'audio-lane',
      clipId: 'audio-clip',
    );

    expect(canRemoveEditorClip(project, selection), isFalse);
    expect(
      () => removeEditorClip(project: project, selection: selection),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('moving a clip is frame exact and expands the project duration', () {
    final moved = moveEditorClip(
      project: testProject(),
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      targetLaneId: 'video-lane',
      timelineStart: MediaTime.seconds(4),
    );

    final clip = moved.lanes.first.clips.single as EditorVideoClip;
    expect(clip.timelineStart, MediaTime.seconds(4));
    expect(clip.sourceRange.start, MediaTime.seconds(1));
    expect(clip.duration, MediaTime.seconds(8));
    expect(moved.duration, MediaTime.seconds(12));
    expect(() => validateEditorProject(moved), returnsNormally);
  });

  test('linked audio and video move and trim as one edit', () {
    final project = testProject(linkPrimaryMedia: true);
    final selection = const EditorSelection(
      laneId: 'video-lane',
      clipId: 'video-clip',
    );
    final moved = moveEditorClip(
      project: project,
      selection: selection,
      targetLaneId: 'video-lane',
      timelineStart: MediaTime.seconds(1),
    );
    expect(moved.lanes[0].clips.single.timelineStart, MediaTime.seconds(1));
    expect(moved.lanes[1].clips.single.timelineStart, MediaTime.seconds(1));

    final trimmed = trimEditorClip(
      project: moved,
      selection: selection,
      edge: EditorTrimEdge.start,
      edgeTime: MediaTime.seconds(2),
    );
    final video = trimmed.lanes[0].clips.single as EditorVideoClip;
    final audio = trimmed.lanes[1].clips.single as EditorAudioClip;
    expect(video.timelineStart, MediaTime.seconds(2));
    expect(audio.timelineStart, MediaTime.seconds(2));
    expect(video.duration, MediaTime.seconds(7));
    expect(audio.duration, MediaTime.seconds(7));
    expect(video.sourceRange.start, MediaTime.seconds(2));
    expect(audio.sourceRange.start, MediaTime.seconds(1));
    expect(() => validateEditorProject(trimmed), returnsNormally);
  });

  test('split keeps linked audio and video halves synchronized', () {
    final result = splitEditorClip(
      project: testProject(linkPrimaryMedia: true),
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      at: MediaTime.seconds(3),
    );

    final videos = result.project.lanes[0].clips;
    final audio = result.project.lanes[1].clips;
    expect(videos, hasLength(2));
    expect(audio, hasLength(2));
    expect(videos[0].linkGroupId, 'primary-media');
    expect(audio[0].linkGroupId, 'primary-media');
    expect(videos[1].linkGroupId, isNot('primary-media'));
    expect(audio[1].linkGroupId, videos[1].linkGroupId);
    expect(audio[1].timelineStart, videos[1].timelineStart);
  });

  test('split refuses an off-cut locked member of linked media', () {
    final project = _offsetLinkedProject(lockedAudio: true);
    final lockedAudio = project.laneById('audio-lane')!.clips.single;

    expect(
      canSplitEditorSelection(
        project,
        const EditorSelection(laneId: 'video-lane', clipId: 'video-clip'),
        MediaTime.seconds(2),
      ),
      isFalse,
    );

    expect(
      () => splitEditorClip(
        project: project,
        selection: const EditorSelection(
          laneId: 'video-lane',
          clipId: 'video-clip',
        ),
        at: MediaTime.seconds(2),
      ),
      throwsA(
        isA<EditorValidationException>().having(
          (error) => error.message,
          'message',
          'Selected media includes a locked lane.',
        ),
      ),
    );
    expect(project.laneById('audio-lane')!.clips.single, same(lockedAudio));
  });

  test('split assigns an off-cut linked follower to the right partition', () {
    final result = splitEditorClip(
      project: _offsetLinkedProject(),
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      at: MediaTime.seconds(2),
    );

    final videos = result.project.laneById('video-lane')!.clips;
    final audio = result.project.laneById('audio-lane')!.clips.single;
    expect(videos.first.linkGroupId, 'primary-media');
    expect(videos.last.linkGroupId, isNot('primary-media'));
    expect(audio.linkGroupId, videos.last.linkGroupId);
    expect(audio.timelineStart, MediaTime.seconds(3));
  });

  test('split partitions linked members on exact cut boundaries', () {
    const selection = EditorSelection(
      laneId: 'video-lane',
      clipId: 'video-clip',
    );
    final startsAtCut = splitEditorClip(
      project: _offsetLinkedProject(),
      selection: selection,
      at: MediaTime.seconds(3),
    ).project;
    final rightVideo = startsAtCut.laneById('video-lane')!.clips.last;
    expect(
      startsAtCut.clipById('audio-clip')!.linkGroupId,
      rightVideo.linkGroupId,
    );

    final endsAtCut = splitEditorClip(
      project: _offsetLinkedProject(
        audioStart: MediaTime.zero,
        audioDuration: MediaTime.seconds(2),
      ),
      selection: selection,
      at: MediaTime.seconds(2),
    ).project;
    expect(endsAtCut.clipById('audio-clip')!.linkGroupId, 'primary-media');
    expect(
      endsAtCut.laneById('video-lane')!.clips.last.linkGroupId,
      isNot('primary-media'),
    );
  });

  test('split preserves an unrelated locked lane by identity', () {
    final project = testProject(lockedVideo: true);
    final lockedLane = project.laneById('video-lane')!;

    final result = splitEditorClip(
      project: project,
      selection: const EditorSelection(
        laneId: 'audio-lane',
        clipId: 'audio-clip',
      ),
      at: MediaTime.seconds(2),
    );

    expect(result.project.laneById(lockedLane.id), same(lockedLane));
  });

  test('move resolution snaps both clip edges and avoids overlap', () {
    final project = testProject();
    final selection = const EditorSelection(
      laneId: 'caption-lane',
      clipId: 'caption-clip',
    );
    final snapped = resolveEditorClipMove(
      project: project,
      selection: selection,
      targetLaneId: 'caption-lane',
      proposedTimelineStart: MediaTime.milliseconds(2920),
      playhead: MediaTime.seconds(3),
      snapThreshold: MediaTime.milliseconds(150),
    );

    expect(snapped.timelineStart, MediaTime.seconds(3));
    expect(snapped.snapGuide, MediaTime.seconds(3));
  });

  test('trim resolution respects one-frame minimum and source bounds', () {
    final project = testProject();
    final selection = const EditorSelection(
      laneId: 'video-lane',
      clipId: 'video-clip',
    );
    final start = resolveEditorClipTrim(
      project: project,
      selection: selection,
      edge: EditorTrimEdge.start,
      proposedEdgeTime: MediaTime.seconds(20),
      playhead: MediaTime.seconds(3),
      snapThreshold: MediaTime.zero,
    );

    expect(start.edgeTime, lessThan(MediaTime.seconds(8)));
    final trimmed = trimEditorClip(
      project: project,
      selection: selection,
      edge: EditorTrimEdge.start,
      edgeTime: start.edgeTime,
    );
    expect(
      trimmed.lanes.first.clips.single.duration.microseconds,
      greaterThanOrEqualTo(33333),
    );
  });

  test('active clips respect hidden lanes and exclusive ends', () {
    final active = activeEditorClips(
      testProject(hiddenCaptions: true),
      MediaTime.seconds(2),
    );
    expect(active.map((clip) => clip.id), ['video-clip', 'audio-clip']);
    expect(activeEditorClips(testProject(), MediaTime.seconds(8)), isEmpty);
  });
}

EditorProject _offsetLinkedProject({
  bool lockedAudio = false,
  MediaTime? audioStart,
  MediaTime? audioDuration,
}) {
  final original = testProject(linkPrimaryMedia: true);
  final audioLane = original.laneById('audio-lane')!;
  final audio = audioLane.clips.single as EditorAudioClip;
  return original.copyWith(
    lanes: [
      original.lanes.first,
      EditorLane(
        id: audioLane.id,
        label: audioLane.label,
        kind: audioLane.kind,
        locked: lockedAudio,
        hidden: audioLane.hidden,
        muted: audioLane.muted,
        clips: [
          EditorAudioClip(
            id: audio.id,
            linkGroupId: audio.linkGroupId,
            timelineStart: audioStart ?? MediaTime.seconds(3),
            duration: audioDuration ?? MediaTime.seconds(5),
            source: audio.source,
            sourceRange: MediaRange(
              start: audio.sourceRange.start,
              duration: audioDuration ?? MediaTime.seconds(5),
            ),
            sourceDuration: audio.sourceDuration,
            volume: audio.volume,
          ),
        ],
      ),
      original.lanes.last,
    ],
  );
}
