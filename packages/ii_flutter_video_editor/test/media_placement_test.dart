import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  test('places one source in linked new lanes at the requested time', () {
    var sourceReads = 0;
    final source = MediaSource(
      id: 'insert-source',
      byteLength: 4,
      fileExtension: 'mp4',
      openRead: () {
        sourceReads++;
        return Stream.value(const [1, 2, 3, 4]);
      },
    );
    final project = testProject(lockedVideo: true);

    final placed = addEditorSourceOnNewLanes(
      project: project,
      source: source,
      timelineStart: project.duration,
      video: EditorNewLanePlacement.fullSource(
        laneId: 'insert-video-lane',
        laneLabel: 'Insert video',
        clipId: 'insert-video-clip',
        sourceDuration: MediaTime.seconds(3),
      ),
      audio: EditorNewLanePlacement.fullSource(
        laneId: 'insert-audio-lane',
        laneLabel: 'Insert audio',
        clipId: 'insert-audio-clip',
        sourceDuration: MediaTime.seconds(3),
      ),
      linkGroupId: 'insert-pair',
    );

    expect(placed.duration, MediaTime.seconds(13));
    expect(placed.output, same(project.output));
    expect(placed.backgroundColor, project.backgroundColor);
    for (var index = 0; index < project.lanes.length; index++) {
      expect(placed.lanes[index], same(project.lanes[index]));
    }
    final video = placed.clipById('insert-video-clip')! as EditorVideoClip;
    final audio = placed.clipById('insert-audio-clip')! as EditorAudioClip;
    expect(video.timelineStart, project.duration);
    expect(audio.timelineStart, project.duration);
    expect(video.timelineEnd, MediaTime.seconds(13));
    expect(audio.timelineEnd, video.timelineEnd);
    expect(video.linkGroupId, 'insert-pair');
    expect(audio.linkGroupId, video.linkGroupId);
    expect(identical(video.source, audio.source), isTrue);
    expect(placed.lanes.map((lane) => lane.id).toList().sublist(3), [
      'insert-video-lane',
      'insert-audio-lane',
    ]);
    expect(sourceReads, 0);
  });

  test('keeps independent source ranges and decoded sync offsets', () {
    final videoRange = MediaRange(
      start: MediaTime.seconds(1),
      duration: MediaTime.seconds(2),
    );
    final audioRange = MediaRange(
      start: MediaTime.zero,
      duration: MediaTime.seconds(3),
    );
    final placed = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: testSource('ranged-source', 'mp4'),
      timelineStart: MediaTime.seconds(10),
      video: EditorNewLanePlacement(
        laneId: 'ranged-video-lane',
        laneLabel: 'Ranged video',
        clipId: 'ranged-video-clip',
        sourceRange: videoRange,
        sourceDuration: MediaTime.seconds(5),
        timelineOffset: MediaTime.milliseconds(200),
      ),
      audio: EditorNewLanePlacement(
        laneId: 'ranged-audio-lane',
        laneLabel: 'Ranged audio',
        clipId: 'ranged-audio-clip',
        sourceRange: audioRange,
        sourceDuration: MediaTime.seconds(3),
      ),
      linkGroupId: 'ranged-pair',
    );

    final video = placed.clipById('ranged-video-clip')! as EditorVideoClip;
    final audio = placed.clipById('ranged-audio-clip')! as EditorAudioClip;
    expect(video.sourceRange, same(videoRange));
    expect(audio.sourceRange, same(audioRange));
    expect(video.timelineStart, MediaTime.seconds(10.2));
    expect(audio.timelineStart, MediaTime.seconds(10));
    expect(video.timelineEnd, MediaTime.seconds(12.2));
    expect(audio.timelineEnd, MediaTime.seconds(13));
    expect(placed.duration, MediaTime.seconds(13));
  });

  test('linked moves and cuts preserve a decoded stream offset', () {
    final placed = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: testSource('offset-edit-source', 'mp4'),
      timelineStart: MediaTime.seconds(10),
      video: EditorNewLanePlacement(
        laneId: 'offset-video-lane',
        laneLabel: 'Offset video',
        clipId: 'offset-video-clip',
        sourceRange: MediaRange(
          start: MediaTime.zero,
          duration: MediaTime.seconds(2),
        ),
        sourceDuration: MediaTime.seconds(2),
        timelineOffset: MediaTime.milliseconds(200),
      ),
      audio: EditorNewLanePlacement.fullSource(
        laneId: 'offset-audio-lane',
        laneLabel: 'Offset audio',
        clipId: 'offset-audio-clip',
        sourceDuration: MediaTime.seconds(3),
      ),
      linkGroupId: 'offset-edit-pair',
    );

    final moved = moveEditorClip(
      project: placed,
      selection: const EditorSelection(
        laneId: 'offset-video-lane',
        clipId: 'offset-video-clip',
      ),
      targetLaneId: 'offset-video-lane',
      timelineStart: MediaTime.seconds(11.2),
    );
    expect(
      moved.clipById('offset-video-clip')!.timelineStart,
      MediaTime.seconds(11.2),
    );
    expect(
      moved.clipById('offset-audio-clip')!.timelineStart,
      MediaTime.seconds(11),
    );

    final split = splitEditorClip(
      project: moved,
      selection: const EditorSelection(
        laneId: 'offset-video-lane',
        clipId: 'offset-video-clip',
      ),
      at: MediaTime.seconds(12),
    ).project;
    final video = split.laneById('offset-video-lane')!.clips;
    final audio = split.laneById('offset-audio-lane')!.clips;
    expect(video.map((clip) => clip.timelineStart), [
      MediaTime.seconds(11.2),
      MediaTime.seconds(12),
    ]);
    expect(audio.map((clip) => clip.timelineStart), [
      MediaTime.seconds(11),
      MediaTime.seconds(12),
    ]);
    expect(
      (video.last as EditorVideoClip).sourceRange.start,
      MediaTime.milliseconds(800),
    );
    expect(
      (audio.last as EditorAudioClip).sourceRange.start,
      MediaTime.seconds(1),
    );
  });

  test('reuses a source without joining separate occurrence groups', () {
    final source = testSource('reused-source', 'mp4');
    final first = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: source,
      timelineStart: MediaTime.seconds(1),
      video: EditorNewLanePlacement.fullSource(
        laneId: 'first-video-lane',
        laneLabel: 'First',
        clipId: 'first-video-clip',
        sourceDuration: MediaTime.seconds(2),
      ),
      audio: EditorNewLanePlacement.fullSource(
        laneId: 'first-audio-lane',
        laneLabel: 'First audio',
        clipId: 'first-audio-clip',
        sourceDuration: MediaTime.seconds(2),
      ),
      linkGroupId: 'first-pair',
    );
    final second = addEditorSourceOnNewLanes(
      project: first,
      source: source,
      timelineStart: MediaTime.seconds(4),
      video: EditorNewLanePlacement.fullSource(
        laneId: 'second-video-lane',
        laneLabel: 'Second',
        clipId: 'second-video-clip',
        sourceDuration: MediaTime.seconds(2),
      ),
      audio: EditorNewLanePlacement.fullSource(
        laneId: 'second-audio-lane',
        laneLabel: 'Second audio',
        clipId: 'second-audio-clip',
        sourceDuration: MediaTime.seconds(2),
      ),
      linkGroupId: 'second-pair',
    );

    expect(first.duration, MediaTime.seconds(10));
    expect(second.duration, MediaTime.seconds(10));
    expect(second.clipById('first-video-clip')!.linkGroupId, 'first-pair');
    expect(second.clipById('second-video-clip')!.linkGroupId, 'second-pair');
  });

  test('single-stream placements have no edit group', () {
    final video = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: testSource('video-only-source', 'mp4'),
      timelineStart: MediaTime.seconds(2),
      video: EditorNewLanePlacement.fullSource(
        laneId: 'video-only-lane',
        laneLabel: 'Video only',
        clipId: 'video-only-clip',
        sourceDuration: MediaTime.seconds(2),
      ),
    );
    final audio = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: testSource('audio-only-source', 'm4a'),
      timelineStart: MediaTime.seconds(2),
      audio: EditorNewLanePlacement.fullSource(
        laneId: 'audio-only-lane',
        laneLabel: 'Audio only',
        clipId: 'audio-only-clip',
        sourceDuration: MediaTime.seconds(2),
      ),
    );

    expect(video.clips.single.linkGroupId, isNull);
    expect(audio.clips.single.linkGroupId, isNull);
    expect(video.clips.single.timelineStart, MediaTime.seconds(2));
    expect(audio.clips.single.timelineStart, MediaTime.seconds(2));
  });

  test('requires one fresh group only for paired streams', () {
    final project = _emptyProject();
    final source = testSource('shape-source', 'mp4');
    final video = EditorNewLanePlacement.fullSource(
      laneId: 'shape-video-lane',
      laneLabel: 'Shape',
      clipId: 'shape-video-clip',
      sourceDuration: MediaTime.seconds(1),
    );
    final audio = EditorNewLanePlacement.fullSource(
      laneId: 'shape-audio-lane',
      laneLabel: 'Shape audio',
      clipId: 'shape-audio-clip',
      sourceDuration: MediaTime.seconds(1),
    );

    EditorProject place({
      EditorNewLanePlacement? videoPlacement,
      EditorNewLanePlacement? audioPlacement,
      String? group,
    }) => addEditorSourceOnNewLanes(
      project: project,
      source: source,
      timelineStart: MediaTime.zero,
      video: videoPlacement,
      audio: audioPlacement,
      linkGroupId: group,
    );

    expect(() => place(), throwsA(isA<EditorValidationException>()));
    expect(
      () => place(videoPlacement: video, group: 'singleton-group'),
      throwsA(isA<EditorValidationException>()),
    );
    expect(
      () => place(videoPlacement: video, audioPlacement: audio),
      throwsA(isA<EditorValidationException>()),
    );
    expect(
      () =>
          place(videoPlacement: video, audioPlacement: audio, group: source.id),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('rejects gaps and identifier collisions without touching the input', () {
    final project = testProject(linkPrimaryMedia: true);
    final lanes = project.lanes;
    final source = testSource('new-source', 'mp4');

    expect(
      () => addEditorSourceOnNewLanes(
        project: project,
        source: source,
        timelineStart: MediaTime.microseconds(
          project.duration.microseconds + 1,
        ),
        video: EditorNewLanePlacement.fullSource(
          laneId: 'new-video-lane',
          laneLabel: 'New',
          clipId: 'new-video-clip',
          sourceDuration: MediaTime.seconds(1),
        ),
      ),
      throwsA(isA<EditorValidationException>()),
    );
    expect(
      () => addEditorSourceOnNewLanes(
        project: project,
        source: source,
        timelineStart: MediaTime.seconds(1),
        video: EditorNewLanePlacement.fullSource(
          laneId: 'new-video-lane',
          laneLabel: 'New',
          clipId: 'new-video-clip',
          sourceDuration: MediaTime.seconds(1),
        ),
        audio: EditorNewLanePlacement.fullSource(
          laneId: 'new-audio-lane',
          laneLabel: 'New audio',
          clipId: 'new-audio-clip',
          sourceDuration: MediaTime.seconds(1),
        ),
        linkGroupId: 'primary-media',
      ),
      throwsA(isA<EditorValidationException>()),
    );
    expect(project.lanes, same(lanes));
  });

  test('applies caller limits at the exact new-lane boundary', () {
    final exact = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: testSource('bounded-source', 'mp4'),
      timelineStart: MediaTime.zero,
      video: EditorNewLanePlacement.fullSource(
        laneId: 'bounded-video-lane',
        laneLabel: 'Bounded',
        clipId: 'bounded-video-clip',
        sourceDuration: MediaTime.seconds(1),
      ),
      audio: EditorNewLanePlacement.fullSource(
        laneId: 'bounded-audio-lane',
        laneLabel: 'Bounded audio',
        clipId: 'bounded-audio-clip',
        sourceDuration: MediaTime.seconds(1),
      ),
      linkGroupId: 'bounded-pair',
      limits: const EditorLimits(maxLanes: 2),
    );
    expect(exact.lanes, hasLength(2));

    expect(
      () => addEditorSourceOnNewLanes(
        project: _emptyProject(),
        source: testSource('over-source', 'mp4'),
        timelineStart: MediaTime.zero,
        video: EditorNewLanePlacement.fullSource(
          laneId: 'over-video-lane',
          laneLabel: 'Over',
          clipId: 'over-video-clip',
          sourceDuration: MediaTime.seconds(1),
        ),
        audio: EditorNewLanePlacement.fullSource(
          laneId: 'over-audio-lane',
          laneLabel: 'Over audio',
          clipId: 'over-audio-clip',
          sourceDuration: MediaTime.seconds(1),
        ),
        linkGroupId: 'over-pair',
        limits: const EditorLimits(maxLanes: 1),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('accepts exact duration limit and rejects one microsecond over', () {
    final exactDuration = MediaTime.seconds(20);
    EditorProject place(MediaTime duration) => addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: testSource('duration-source', 'mp4'),
      timelineStart: MediaTime.seconds(10),
      video: EditorNewLanePlacement.fullSource(
        laneId: 'duration-video-lane',
        laneLabel: 'Duration',
        clipId: 'duration-video-clip',
        sourceDuration: duration,
      ),
      limits: const EditorLimits(maxDuration: Duration(seconds: 30)),
    );

    expect(place(exactDuration).duration, MediaTime.seconds(30));
    expect(
      () => place(MediaTime.microseconds(exactDuration.microseconds + 1)),
      throwsA(isA<EditorValidationException>()),
    );
    expect(
      () => EditorNewLanePlacement.fullSource(
        laneId: 'zero-lane',
        laneLabel: 'Zero',
        clipId: 'zero-clip',
        sourceDuration: MediaTime.zero,
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('compiler keeps linked decoded offsets and one source input', () async {
    final source = testSource('compiled-source', 'mp4');
    final project = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: source,
      timelineStart: MediaTime.seconds(3),
      video: EditorNewLanePlacement.fullSource(
        laneId: 'compiled-video-lane',
        laneLabel: 'Compiled',
        clipId: 'compiled-video-clip',
        sourceDuration: MediaTime.seconds(2),
      ),
      audio: EditorNewLanePlacement(
        laneId: 'compiled-audio-lane',
        laneLabel: 'Compiled audio',
        clipId: 'compiled-audio-clip',
        sourceRange: MediaRange(
          start: MediaTime.zero,
          duration: MediaTime.milliseconds(1825),
        ),
        sourceDuration: MediaTime.milliseconds(1825),
        timelineOffset: MediaTime.milliseconds(175),
      ),
      linkGroupId: 'compiled-pair',
    );

    final preflight = const EditorCompositionCompiler().preflight(project);
    final plan = await const EditorCompositionCompiler().compile(project);
    expect(preflight.footprint!.emittedLayerCount, 2);
    expect(preflight.footprint!.mediaInputCount, 1);
    expect(plan.layers, hasLength(2));
    expect(plan.layers[0].timelineStart, MediaTime.seconds(3));
    expect(plan.layers[1].timelineStart, MediaTime.seconds(3.175));
    expect(plan.layers[1].sourceRange.start, MediaTime.zero);
    expect(
      plan.job.arguments.join(' '),
      allOf(
        contains(
          'setpts=PTS-STARTPTS,'
          'trim=start=0.000000:duration=2.000000',
        ),
        contains(
          'asetpts=PTS-STARTPTS,'
          'atrim=start=0.000000:duration=1.825000,'
          'asetpts=PTS-STARTPTS,'
          'adelay=delays=3175.000:all=1',
        ),
        isNot(contains('asetpts=PTS-STARTPTS+3.175000/TB')),
      ),
    );
    expect(plan.job.inputs, hasLength(1));
  });
}

EditorProject _emptyProject() => EditorProject(
  id: 'empty-project',
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.seconds(10),
  lanes: const [],
);
