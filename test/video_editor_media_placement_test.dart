import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_timeline_codec.dart';
import 'package:ii_os/models/video_project.dart';
import 'package:ii_os/services/editor_media_import_batch.dart';
import 'package:ii_os/services/editor_media_source.dart';
import 'package:ii_os/services/video_editor_ffmpeg.dart';
import 'package:ii_os/services/video_editor_project.dart';

void main() {
  test('preserves project settings and every existing lane identity', () {
    final original = _place(project: null, media: _media(id: 'base'));
    final adjusted = EditorProject(
      id: 'custom-project',
      width: 960,
      height: 540,
      framesPerSecond: 24,
      duration: original.duration,
      lanes: original.lanes,
      output: const MediaOutputSettings(
        container: MediaContainer.webm,
        videoCodec: MediaVideoCodec.vp9,
        audioCodec: MediaAudioCodec.opus,
        videoBitrate: 900000,
        audioBitrate: 96000,
      ),
      backgroundColor: '123456',
    );
    final placed = _place(
      project: adjusted,
      media: _media(id: 'layer', width: 1280, height: 720),
      timelineStart: MediaTime.seconds(2),
    );

    expect(placed.id, adjusted.id);
    expect(placed.output, same(adjusted.output));
    expect(placed.backgroundColor, adjusted.backgroundColor);
    expect(placed.width, adjusted.width);
    expect(placed.height, adjusted.height);
    for (var index = 0; index < adjusted.lanes.length; index++) {
      expect(placed.lanes[index], same(adjusted.lanes[index]));
    }
    expect(placed.clipById('layer-video-clip')!.linkGroupId, 'layer-pair');
    expect(placed.clipById('layer-audio-clip')!.linkGroupId, 'layer-pair');
    expect(placed.clipById('layer-video-clip')!.linkGroupId, isNot('layer'));
  });

  test('leaves single streams ungrouped and rejects unusable media', () {
    final video = _place(
      project: null,
      media: _media(id: 'video-only', hasAudio: false),
    );
    final audio = _place(
      project: null,
      media: _media(id: 'audio-only', hasVideo: false),
    );

    expect(video.lanes.single.kind, EditorLaneKind.video);
    expect(video.clips.single.linkGroupId, isNull);
    expect(audio.lanes.single.kind, EditorLaneKind.audio);
    expect(audio.clips.single.linkGroupId, isNull);
    expect(
      () => _place(
        project: video,
        media: _media(id: 'empty', hasVideo: false, hasAudio: false),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(video.lanes, hasLength(1));
  });

  test('accepts the project end and rejects starts beyond controlled time', () {
    final base = _place(project: null, media: _media(id: 'base'));
    final appended = _place(
      project: base,
      media: _media(id: 'ending', duration: const Duration(seconds: 2)),
      timelineStart: base.duration,
    );

    expect(appended.duration, MediaTime.seconds(7));
    expect(
      appended.clipById('ending-video-clip')!.timelineStart,
      base.duration,
    );
    expect(
      () => _place(
        project: base,
        media: _media(id: 'gap'),
        timelineStart: MediaTime.microseconds(base.duration.microseconds + 1),
      ),
      throwsA(isA<EditorValidationException>()),
    );
    expect(
      () => _place(
        project: null,
        media: _media(id: 'initial-gap'),
        timelineStart: MediaTime.microseconds(1),
      ),
      throwsA(isA<EditorValidationException>()),
    );
  });

  test('target readiness sees the expanded requested-playhead duration', () {
    final compiler = EditorCompositionCompiler.forTarget(
      videoEditorRenderTargetFor(browser: true),
    );
    final exact = _place(
      project: _blankProject(const Duration(seconds: 119)),
      media: _media(
        id: 'exact',
        duration: const Duration(seconds: 1),
        hasAudio: false,
      ),
      timelineStart: MediaTime.seconds(119),
    );
    final over = _place(
      project: _blankProject(const Duration(seconds: 120)),
      media: _media(
        id: 'over',
        duration: const Duration(seconds: 1),
        hasAudio: false,
      ),
      timelineStart: MediaTime.seconds(120),
    );

    expect(exact.duration, MediaTime.seconds(120));
    expect(compiler.preflight(exact).isStructurallyFeasible, isTrue);
    expect(over.duration, MediaTime.seconds(121));
    expect(
      compiler.preflight(over).issues.first.code,
      EditorRenderIssueCode.invalidProject,
    );
  });

  test('storage round-trip retains nonzero edit-linked placement', () {
    final media = _media(id: 'stored', duration: const Duration(seconds: 2));
    final placed = _place(
      project: _blankProject(const Duration(seconds: 5)),
      media: media,
      timelineStart: MediaTime.seconds(4),
    );
    final encoded = encodeEditorTimeline(placed);
    final restored = decodeEditorTimeline(
      encoded,
      sources: {media.id: media.source},
    );

    expect(editorTimelineMediaIds(encoded), [media.id]);
    expect(restored.duration, MediaTime.seconds(6));
    expect(
      restored.clipById('stored-video-clip')!.timelineStart,
      MediaTime.seconds(4),
    );
    expect(
      restored.clipById('stored-audio-clip')!.timelineStart,
      MediaTime.seconds(4),
    );
    expect(restored.clipById('stored-video-clip')!.linkGroupId, 'stored-pair');
    expect(restored.clipById('stored-audio-clip')!.linkGroupId, 'stored-pair');
    expect(
      identical(
        (restored.clipById('stored-video-clip')! as EditorVideoClip).source,
        (restored.clipById('stored-audio-clip')! as EditorAudioClip).source,
      ),
      isTrue,
    );
    expect(encodeEditorTimeline(restored), encoded);
  });

  test('preserves decoded stream skew through placement and v1 round-trip', () {
    const videoTiming = VideoProjectStreamTiming(
      presentationStart: Duration.zero,
      duration: Duration(seconds: 2),
    );
    const audioTiming = VideoProjectStreamTiming(
      presentationStart: Duration(milliseconds: 175),
      duration: Duration(milliseconds: 1825),
    );
    final media = _media(
      id: 'offset',
      duration: const Duration(seconds: 2),
      videoTiming: videoTiming,
      audioTiming: audioTiming,
    );
    final placed = _place(
      project: _blankProject(const Duration(seconds: 5)),
      media: media,
      timelineStart: MediaTime.seconds(4),
    );
    final video = placed.clipById('offset-video-clip')! as EditorVideoClip;
    final audio = placed.clipById('offset-audio-clip')! as EditorAudioClip;

    expect(video.timelineStart, MediaTime.seconds(4));
    expect(video.sourceRange.start, MediaTime.zero);
    expect(video.duration, MediaTime.seconds(2));
    expect(video.sourceDuration, MediaTime.seconds(2));
    expect(audio.timelineStart, MediaTime.milliseconds(4175));
    expect(audio.sourceRange.start, MediaTime.zero);
    expect(audio.duration, MediaTime.milliseconds(1825));
    expect(audio.sourceDuration, MediaTime.milliseconds(1825));
    expect(placed.duration, MediaTime.seconds(6));

    final encoded = encodeEditorTimeline(placed);
    final restored = decodeEditorTimeline(
      encoded,
      sources: {media.id: media.source},
    );
    expect(encodeEditorTimeline(restored), encoded);
    expect(
      restored.clipById('offset-audio-clip')!.timelineStart,
      MediaTime.milliseconds(4175),
    );
    expect(
      (restored.clipById('offset-audio-clip')! as EditorAudioClip)
          .sourceRange
          .start,
      MediaTime.zero,
    );
  });

  test('a batch keeps its captured playhead and stops at rejection', () async {
    var livePlayhead = MediaTime.seconds(3);
    var captures = 0;
    final attempted = <String>[];
    final starts = <MediaTime>[];

    final accepted = await runEditorMediaImportBatch(
      choices: const ['first', 'rejected', 'unreached'],
      captureTimelineStart: () {
        captures++;
        return livePlayhead;
      },
      importChoice: (choice, timelineStart) async {
        attempted.add(choice);
        starts.add(timelineStart);
        livePlayhead = MediaTime.seconds(9);
        return choice != 'rejected';
      },
    );

    expect(accepted, isFalse);
    expect(captures, 1);
    expect(attempted, ['first', 'rejected']);
    expect(starts, [MediaTime.seconds(3), MediaTime.seconds(3)]);
    expect(livePlayhead, MediaTime.seconds(9));
  });
}

EditorProject _place({
  required EditorProject? project,
  required LocalEditorMedia media,
  MediaTime timelineStart = MediaTime.zero,
}) => addLocalMediaToNewLanes(
  projectId: 'placement-project',
  project: project,
  media: media,
  videoLaneId: '${media.id}-video-lane',
  audioLaneId: '${media.id}-audio-lane',
  videoClipId: '${media.id}-video-clip',
  audioClipId: '${media.id}-audio-clip',
  linkGroupId: '${media.id}-pair',
  timelineStart: timelineStart,
  videoBitrate: 100000,
  browserOutput: true,
);

EditorProject _blankProject(Duration duration) => EditorProject(
  id: 'blank-project-${duration.inSeconds}',
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.microseconds(duration.inMicroseconds),
  lanes: const [],
  output: const MediaOutputSettings(
    container: MediaContainer.webm,
    videoCodec: MediaVideoCodec.vp9,
    audioCodec: MediaAudioCodec.opus,
    videoBitrate: 100000,
    audioBitrate: 64000,
  ),
);

LocalEditorMedia _media({
  required String id,
  Duration duration = const Duration(seconds: 5),
  bool hasVideo = true,
  bool hasAudio = true,
  int width = 640,
  int height = 360,
  VideoProjectStreamTiming? videoTiming,
  VideoProjectStreamTiming? audioTiming,
}) => LocalEditorMedia(
  id: id,
  filename: '$id.mp4',
  path: '/tmp/$id.mp4',
  bytes: Uint8List.fromList([0, 0, 0, 24, ...'ftypisom'.codeUnits]),
  contentType: hasVideo ? 'video/mp4' : 'audio/mp4',
  duration: duration,
  hasVideo: hasVideo,
  hasAudio: hasAudio,
  videoTiming: videoTiming,
  audioTiming: audioTiming,
  width: hasVideo ? width : null,
  height: hasVideo ? height : null,
);
