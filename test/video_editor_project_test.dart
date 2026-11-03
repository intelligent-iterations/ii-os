import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_timeline_codec.dart';
import 'package:ii_os/services/editor_media_source.dart';
import 'package:ii_os/services/video_editor_project.dart';

void main() {
  test('shares one local byte source across video and audio lanes', () {
    final media = _media();
    final project = _addLocalMedia(
      projectId: 'project-1',
      project: null,
      media: media,
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
      browserOutput: false,
    );

    expect(project.width, 1280);
    expect(project.height, 720);
    expect(project.duration, MediaTime.seconds(5));
    expect(project.output.videoCodec, MediaVideoCodec.mpeg4);
    final video = project.lanes[0].clips.single as EditorVideoClip;
    final audio = project.lanes[1].clips.single as EditorAudioClip;
    expect(identical(video.source, audio.source), isTrue);
    expect(identical(video.source, media.source), isTrue);
    expect(video.linkGroupId, 'link-video-clip');
    expect(audio.linkGroupId, video.linkGroupId);
    expect(video.sourceDuration, project.duration);
    expect(audio.sourceDuration, project.duration);
    expect(() => validateEditorProject(project), returnsNormally);
  });

  test('places edit-linked video and audio at the requested playhead', () {
    final base = _addLocalMedia(
      projectId: 'project-playhead',
      project: null,
      media: _media(id: 'base'),
      videoLaneId: 'base-video-lane',
      audioLaneId: 'base-audio-lane',
      videoClipId: 'base-video-clip',
      audioClipId: 'base-audio-clip',
    );
    final result = _addLocalMedia(
      projectId: 'project-playhead',
      project: base,
      media: _media(id: 'inserted'),
      videoLaneId: 'inserted-video-lane',
      audioLaneId: 'inserted-audio-lane',
      videoClipId: 'inserted-video-clip',
      audioClipId: 'inserted-audio-clip',
      timelineStart: MediaTime.seconds(3),
    );

    final video = result.clipById('inserted-video-clip')!;
    final audio = result.clipById('inserted-audio-clip')!;
    expect(video.timelineStart, MediaTime.seconds(3));
    expect(audio.timelineStart, MediaTime.seconds(3));
    expect(video.timelineEnd, MediaTime.seconds(8));
    expect(audio.timelineEnd, MediaTime.seconds(8));
    expect(video.linkGroupId, 'link-inserted-video-clip');
    expect(audio.linkGroupId, video.linkGroupId);
    expect(result.duration, MediaTime.seconds(8));
    expect(
      activeVideoClips(
        result,
        MediaTime.microseconds(MediaTime.seconds(3).microseconds - 1),
      ).map((clip) => clip.id),
      isNot(contains('inserted-video-clip')),
    );
    expect(
      activeVideoClips(result, MediaTime.seconds(3)).map((clip) => clip.id),
      contains('inserted-video-clip'),
    );
    expect(() => validateEditorProject(result), returnsNormally);
  });

  test('uses browser-playable WebM output without losing bitrate edits', () {
    final project = _addLocalMedia(
      projectId: 'project-browser',
      project: null,
      media: _media(),
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
      browserOutput: true,
    );

    expect(project.output.container, MediaContainer.webm);
    expect(project.output.videoCodec, MediaVideoCodec.vp9);
    expect(project.output.audioCodec, MediaAudioCodec.opus);
    final adjusted = withEditorVideoBitrate(project, 2 * 1000 * 1000);
    expect(adjusted.output.container, MediaContainer.webm);
    expect(adjusted.output.videoCodec, MediaVideoCodec.vp9);
    expect(adjusted.output.audioCodec, MediaAudioCodec.opus);
    expect(() => validateEditorProject(adjusted), returnsNormally);
  });

  test('adds separately styled text and subtitle caption lanes', () {
    final base = _addLocalMedia(
      projectId: 'project-1',
      project: null,
      media: _media(),
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
    );
    final text = addEditorCaption(
      project: base,
      playhead: MediaTime.seconds(1),
      laneId: 'text-lane',
      clipId: 'text-clip',
      text: 'Title',
      subtitle: false,
    );
    final result = addEditorCaption(
      project: text,
      playhead: MediaTime.seconds(2),
      laneId: 'subtitle-lane',
      clipId: 'subtitle-clip',
      text: 'Spoken words',
      subtitle: true,
    );

    final title = result.lanes[2].clips.single as EditorCaptionClip;
    final subtitle = result.lanes[3].clips.single as EditorCaptionClip;
    expect(title.destination.y, lessThan(subtitle.destination.y));
    expect(title.style.fontSize, greaterThan(subtitle.style.fontSize));
    expect(activeCaptionClips(result, MediaTime.seconds(2.5)), hasLength(2));
    expect(() => validateEditorProject(result), returnsNormally);
  });

  test('reuses the top caption lane for adjacent styled cues', () {
    final base = _addLocalMedia(
      projectId: 'project-caption-reuse',
      project: null,
      media: _media(),
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
    );
    final first = addEditorCaption(
      project: base,
      playhead: MediaTime.zero,
      laneId: 'first-caption-lane',
      clipId: 'first-caption',
      text: 'Title',
      subtitle: false,
    );
    final result = addEditorCaption(
      project: first,
      playhead: MediaTime.seconds(3),
      laneId: 'unused-second-caption-lane',
      clipId: 'second-caption',
      text: 'Spoken words',
      subtitle: true,
    );

    expect(result.lanes, hasLength(3));
    final captions = result.lanes.last;
    expect(captions.id, 'first-caption-lane');
    expect(captions.label, 'Text overlay');
    expect(captions.clips.map((clip) => clip.id), [
      'first-caption',
      'second-caption',
    ]);
    expect(
      (captions.clips.first as EditorCaptionClip).style.fontSize,
      greaterThan((captions.clips.last as EditorCaptionClip).style.fontSize),
    );
  });

  test('reused styled caption cues survive canonical storage', () {
    final media = _media();
    final base = _addLocalMedia(
      projectId: 'project-caption-storage',
      project: null,
      media: media,
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
    );
    final first = addEditorCaption(
      project: base,
      playhead: MediaTime.zero,
      laneId: 'caption-lane',
      clipId: 'title-caption',
      text: 'Title',
      subtitle: false,
    );
    final placed = addEditorCaption(
      project: first,
      playhead: MediaTime.seconds(3),
      laneId: 'unused-subtitle-lane',
      clipId: 'subtitle-caption',
      text: 'Subtitle',
      subtitle: true,
    );
    final captionLane = placed.lanes.last.copyWith(hidden: true, locked: true);
    final project = placed.copyWith(
      lanes: [...placed.lanes.take(2), captionLane],
    );
    final encoded = encodeEditorTimeline(project);
    final restored = decodeEditorTimeline(
      encoded,
      sources: {media.source.id: media.source},
    );

    final restoredLane = restored.laneById('caption-lane')!;
    expect(restoredLane.hidden, isTrue);
    expect(restoredLane.locked, isTrue);
    expect(restoredLane.clips.map((clip) => clip.id), [
      'title-caption',
      'subtitle-caption',
    ]);
    final title = restoredLane.clips.first as EditorCaptionClip;
    final subtitle = restoredLane.clips.last as EditorCaptionClip;
    expect(title.style.fontSize, greaterThan(subtitle.style.fontSize));
    expect(title.destination.y, lessThan(subtitle.destination.y));
    expect(encodeEditorTimeline(restored), encoded);
  });

  test(
    'addition requests rebuild from the timeline current after awaiting',
    () async {
      final original = _captionBase('same-project');
      final replacement = _captionBase('same-project');
      var current = original;
      EditorProject? candidate;
      var acceptedEffects = 0;

      final accepted = await runEditorAdditionRequest<String>(
        request: () async {
          current = replacement;
          return 'Fresh request';
        },
        currentProject: () => current,
        unavailable: () => false,
        buildCandidate: (project, text) {
          expect(project, same(replacement));
          return addEditorCaption(
            project: project,
            playhead: MediaTime.zero,
            laneId: 'requested-caption-lane',
            clipId: 'requested-caption',
            text: text,
            subtitle: true,
          );
        },
        admit: (project) {
          candidate = project;
          return true;
        },
        onAccepted: () => acceptedEffects++,
      );

      expect(accepted, isTrue);
      expect(candidate!.id, 'same-project');
      expect(candidate!.clipById('requested-caption'), isNotNull);
      expect(acceptedEffects, 1);
    },
  );

  test(
    'addition requests abort when another project replaced the opener',
    () async {
      final original = _captionBase('original');
      final replacement = _captionBase('replacement');
      var current = original;
      var built = 0;
      var acceptedEffects = 0;

      final accepted = await runEditorAdditionRequest<String>(
        request: () async {
          current = replacement;
          return 'Wrong project';
        },
        currentProject: () => current,
        unavailable: () => false,
        buildCandidate: (project, text) {
          built++;
          return addEditorCaption(
            project: project,
            playhead: MediaTime.zero,
            laneId: 'wrong-project-caption-lane',
            clipId: 'wrong-project-caption',
            text: text,
            subtitle: true,
          );
        },
        admit: (_) => true,
        onAccepted: () => acceptedEffects++,
      );

      expect(accepted, isFalse);
      expect(built, 0);
      expect(acceptedEffects, 0);
      expect(replacement.clipById('wrong-project-caption'), isNull);
    },
  );

  test('rejected addition requests have no accepted effects', () async {
    final original = _captionBase('rejected');
    var acceptedEffects = 0;
    var built = 0;

    final accepted = await runEditorAdditionRequest<String>(
      request: () async => 'Rejected request',
      currentProject: () => original,
      unavailable: () => false,
      buildCandidate: (project, text) {
        built++;
        return addEditorCaption(
          project: project,
          playhead: MediaTime.zero,
          laneId: 'rejected-caption-lane',
          clipId: 'rejected-caption',
          text: text,
          subtitle: true,
        );
      },
      admit: (_) => false,
      onAccepted: () => acceptedEffects++,
    );

    expect(accepted, isFalse);
    expect(built, 1);
    expect(acceptedEffects, 0);
    expect(original.clipById('rejected-caption'), isNull);
  });

  test('returns every active visual in export lane order', () {
    final first = _media(id: 'first');
    final second = _media(id: 'second');
    final base = _addLocalMedia(
      projectId: 'project-layers',
      project: null,
      media: first,
      videoLaneId: 'first-video-lane',
      audioLaneId: 'first-audio-lane',
      videoClipId: 'first-video-clip',
      audioClipId: 'first-audio-clip',
    );
    final layered = _addLocalMedia(
      projectId: 'project-layers',
      project: base,
      media: second,
      videoLaneId: 'second-video-lane',
      audioLaneId: 'second-audio-lane',
      videoClipId: 'second-video-clip',
      audioClipId: 'second-audio-clip',
    );

    expect(
      activeVideoClips(layered, MediaTime.seconds(1)).map((clip) => clip.id),
      ['first-video-clip', 'second-video-clip'],
    );
    expect(
      activeVideoClip(layered, MediaTime.seconds(1))?.id,
      'second-video-clip',
    );
  });

  test('adds a still image as a bounded overlay above an existing video', () {
    final base = _addLocalMedia(
      projectId: 'project-image-overlay',
      project: null,
      media: _media(id: 'base-video'),
      videoLaneId: 'base-video-lane',
      audioLaneId: 'base-audio-lane',
      videoClipId: 'base-video-clip',
      audioClipId: 'base-audio-clip',
    );
    final layered = _addLocalMedia(
      projectId: 'project-image-overlay',
      project: base,
      media: _imageMedia(),
      videoLaneId: 'image-lane',
      audioLaneId: 'unused-audio-lane',
      videoClipId: 'image-clip',
      audioClipId: 'unused-audio-clip',
      timelineStart: MediaTime.seconds(2),
    );

    final image = layered.clipById('image-clip')! as EditorVideoClip;
    expect(image.destination.x, 0.6);
    expect(image.destination.y, 0.05);
    expect(image.destination.width, 0.35);
    expect(image.destination.height, 0.35);
    expect(image.timelineStart, MediaTime.seconds(2));
    expect(layered.lanes.last.id, 'image-lane');
    expect(() => validateEditorProject(layered), returnsNormally);
  });

  test('scales caption styling to a low-resolution canvas', () {
    final base = _addLocalMedia(
      projectId: 'project-low-resolution',
      project: null,
      media: _media(width: 160, height: 90),
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
    );
    final result = addEditorCaption(
      project: base,
      playhead: MediaTime.seconds(1),
      laneId: 'subtitle-lane',
      clipId: 'subtitle-clip',
      text: 'Spoken words',
      subtitle: true,
    );

    final caption = result.lanes[2].clips.single as EditorCaptionClip;
    final pixelWidth = (caption.destination.width * result.width).round();
    final pixelHeight = (caption.destination.height * result.height).round();
    expect(pixelWidth - caption.style.horizontalPadding * 2, greaterThan(0));
    expect(
      pixelHeight - caption.style.verticalPadding * 2,
      greaterThan(caption.style.fontSize),
    );
    expect(() => validateEditorProject(result), returnsNormally);
  });

  test('timeline edits leave render-budget decisions to preflight', () {
    final base = _addLocalMedia(
      projectId: 'project-1',
      project: null,
      media: _media(),
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
    );

    final adjusted = withEditorVideoBitrate(base, 100 * 1000 * 1000);

    expect(adjusted.output.videoBitrate, 100 * 1000 * 1000);
    expect(() => validateEditorProject(adjusted), returnsNormally);
  });
}

EditorProject _captionBase(String id) => EditorProject(
  id: id,
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.seconds(6),
  lanes: const [],
);

EditorProject _addLocalMedia({
  required String projectId,
  required EditorProject? project,
  required LocalEditorMedia media,
  required String videoLaneId,
  required String audioLaneId,
  required String videoClipId,
  required String audioClipId,
  MediaTime timelineStart = MediaTime.zero,
  int videoBitrate = 4 * 1000 * 1000,
  bool? browserOutput,
}) => addLocalMediaToNewLanes(
  projectId: projectId,
  project: project,
  media: media,
  videoLaneId: videoLaneId,
  audioLaneId: audioLaneId,
  videoClipId: videoClipId,
  audioClipId: audioClipId,
  linkGroupId: 'link-$videoClipId',
  timelineStart: timelineStart,
  videoBitrate: videoBitrate,
  browserOutput: browserOutput,
);

LocalEditorMedia _media({
  String id = 'media-1',
  int width = 1920,
  int height = 1080,
}) => LocalEditorMedia(
  id: id,
  filename: '$id.mp4',
  path: '/tmp/local.mp4',
  bytes: Uint8List.fromList([0, 0, 0, 24, ...'ftypisom'.codeUnits]),
  contentType: 'video/mp4',
  duration: const Duration(seconds: 5),
  hasVideo: true,
  hasAudio: true,
  width: width,
  height: height,
);

LocalEditorMedia _imageMedia() => LocalEditorMedia(
  id: 'image-media',
  filename: 'brand.png',
  path: '/tmp/brand.png',
  bytes: Uint8List.fromList([137, 80, 78, 71]),
  contentType: 'image/png',
  duration: const Duration(seconds: 5),
  hasVideo: true,
  hasAudio: false,
  width: 320,
  height: 180,
);
