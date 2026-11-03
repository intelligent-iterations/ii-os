import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import '../models/video_project.dart';
import 'editor_media_source.dart';

/// Awaits one editor-addition request, then rebuilds from the current project.
///
/// A modal can outlive the project that opened it. A different project aborts
/// the request; when the same project changed, the getter is read again so its
/// latest timeline is extended instead of overwritten from stale state.
/// [onAccepted] runs only after [admit] accepts the candidate, keeping output
/// invalidation and other accepted-only effects behind the same boundary.
Future<bool> runEditorAdditionRequest<T extends Object>({
  required Future<T?> Function() request,
  required EditorProject? Function() currentProject,
  required bool Function() unavailable,
  required EditorProject Function(EditorProject project, T request)
  buildCandidate,
  required bool Function(EditorProject candidate) admit,
  required void Function() onAccepted,
}) async {
  if (unavailable()) return false;
  final initialProject = currentProject();
  if (initialProject == null) return false;
  final value = await request();
  if (value == null || unavailable()) return false;
  final project = currentProject();
  if (project == null || project.id != initialProject.id) return false;
  final candidate = buildCandidate(project, value);
  if (!admit(candidate)) return false;
  onAccepted();
  return true;
}

/// Adds prepared local media as fresh concurrent lanes at [timelineStart].
///
/// Existing video remains below the new visual, and existing audio mixes with
/// the new audio. This is not target-lane insertion or overwrite. The
/// requested start is the shared sync origin. Each decoded stream keeps
/// its own source range and relative timeline offset from that origin.
EditorProject addLocalMediaToNewLanes({
  required String projectId,
  required EditorProject? project,
  required LocalEditorMedia media,
  required String videoLaneId,
  required String audioLaneId,
  required String videoClipId,
  required String audioClipId,
  String? linkGroupId,
  MediaTime timelineStart = MediaTime.zero,
  int videoBitrate = 4 * 1000 * 1000,
  bool? browserOutput,
}) {
  if (!media.hasVideo && !media.hasAudio) {
    throw const FormatException('The media has no usable video or audio.');
  }
  if (media.hasVideo && media.hasAudio && linkGroupId == null) {
    throw const EditorValidationException(
      'Paired video and audio require an edit link group.',
    );
  }
  if (project == null && timelineStart != MediaTime.zero) {
    throw const EditorValidationException(
      'The first media in a project must start at timeline zero.',
    );
  }
  final useBrowserOutput = browserOutput ?? kIsWeb;
  final sourceDuration = MediaTime.microseconds(media.duration.inMicroseconds);
  if (project != null && media.contentType.startsWith('image/')) {
    if (timelineStart > project.duration) {
      throw const EditorValidationException(
        'New media cannot start past the project end.',
      );
    }
    return addEditorImageOverlay(
      project: project,
      laneId: videoLaneId,
      clipId: videoClipId,
      source: media.source,
      timelineStart: timelineStart,
      duration: sourceDuration,
      laneLabel: media.filename,
    );
  }

  final canvas = editorCanvasFor(media);
  final base =
      project ??
      EditorProject(
        id: projectId,
        width: canvas.width,
        height: canvas.height,
        framesPerSecond: 30,
        duration: sourceDuration,
        lanes: const [],
        output: MediaOutputSettings(
          container: useBrowserOutput
              ? MediaContainer.webm
              : MediaContainer.mp4,
          videoCodec: useBrowserOutput
              ? MediaVideoCodec.vp9
              : MediaVideoCodec.mpeg4,
          audioCodec: useBrowserOutput
              ? MediaAudioCodec.opus
              : MediaAudioCodec.aac,
          videoBitrate: videoBitrate,
          audioBitrate: 128 * 1000,
        ),
      );
  final video = media.hasVideo
      ? _streamPlacement(
          laneId: videoLaneId,
          laneLabel: media.filename,
          clipId: videoClipId,
          timing: media.videoTiming!,
          syncOrigin: media.syncOrigin,
        )
      : null;
  final audio = media.hasAudio
      ? _streamPlacement(
          laneId: audioLaneId,
          laneLabel: '${media.filename} audio',
          clipId: audioClipId,
          timing: media.audioTiming!,
          syncOrigin: media.syncOrigin,
        )
      : null;
  return addEditorSourceOnNewLanes(
    project: base,
    source: media.source,
    timelineStart: timelineStart,
    video: video,
    audio: audio,
    linkGroupId: media.hasVideo && media.hasAudio ? linkGroupId : null,
  );
}

EditorNewLanePlacement _streamPlacement({
  required String laneId,
  required String laneLabel,
  required String clipId,
  required VideoProjectStreamTiming timing,
  required Duration syncOrigin,
}) => EditorNewLanePlacement(
  laneId: laneId,
  laneLabel: laneLabel,
  clipId: clipId,
  sourceRange: MediaRange(
    start: MediaTime.zero,
    duration: MediaTime.microseconds(timing.duration.inMicroseconds),
  ),
  sourceDuration: MediaTime.microseconds(timing.duration.inMicroseconds),
  timelineOffset: MediaTime.microseconds(
    (timing.presentationStart - syncOrigin).inMicroseconds,
  ),
);

EditorProject withEditorVideoBitrate(EditorProject project, int bitrate) {
  final next = project.copyWith(
    output: MediaOutputSettings(
      container: project.output.container,
      videoCodec: project.output.videoCodec,
      audioCodec: project.output.audioCodec,
      videoBitrate: bitrate,
      audioBitrate: project.output.audioBitrate,
    ),
  );
  validateEditorProject(next);
  return next;
}

EditorProject addEditorCaption({
  required EditorProject project,
  required MediaTime playhead,
  required String laneId,
  required String clipId,
  required String text,
  required bool subtitle,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Caption text cannot be empty.');
  }
  final start = playhead >= project.duration
      ? MediaTime.microseconds(project.duration.microseconds - 1)
      : playhead;
  final remaining = project.duration.microseconds - start.microseconds;
  final duration = MediaTime.microseconds(
    math.min(const Duration(seconds: 3).inMicroseconds, remaining),
  );
  final captionScale = math.max(4 / 42, math.min(1.0, project.height / 720));
  final caption = EditorCaptionClip(
    id: clipId,
    timelineStart: start,
    duration: duration,
    text: trimmed,
    destination: subtitle
        ? const MediaRect(x: 0.08, y: 0.78, width: 0.84, height: 0.16)
        : const MediaRect(x: 0.1, y: 0.1, width: 0.8, height: 0.24),
    style: subtitle
        ? EditorCaptionStyle(
            fontSize: 42 * captionScale,
            horizontalPadding: 24 * captionScale,
            verticalPadding: 12 * captionScale,
            cornerRadius: 12 * captionScale,
            maxLines: 3,
          )
        : EditorCaptionStyle(
            fontSize: 56 * captionScale,
            backgroundColor: 0x66000000,
            horizontalPadding: 24 * captionScale,
            verticalPadding: 12 * captionScale,
            cornerRadius: 12 * captionScale,
            maxLines: 2,
          ),
  );
  return placeEditorCaption(
    project: project,
    caption: caption,
    newLaneId: laneId,
    newLaneLabel: subtitle ? 'Subtitle' : 'Text overlay',
  );
}

({int width, int height}) editorCanvasFor(LocalEditorMedia media) {
  final sourceWidth = media.width ?? 1280;
  final sourceHeight = media.height ?? 720;
  final scale = math.min(1.0, 1280 / math.max(sourceWidth, sourceHeight));
  int even(int value) => math.max(2, value.isEven ? value : value - 1);
  return (
    width: even((sourceWidth * scale).round()),
    height: even((sourceHeight * scale).round()),
  );
}

EditorVideoClip? activeVideoClip(EditorProject project, MediaTime playhead) {
  EditorVideoClip? active;
  for (final clip in activeVideoClips(project, playhead)) {
    active = clip;
  }
  return active;
}

Iterable<EditorVideoClip> activeVideoClips(
  EditorProject project,
  MediaTime playhead,
) sync* {
  for (final lane in project.lanes) {
    if (lane.hidden || lane.kind != EditorLaneKind.video) continue;
    for (final clip in lane.clips.whereType<EditorVideoClip>()) {
      if (clip.contains(playhead)) yield clip;
    }
  }
}

Iterable<EditorCaptionClip> activeCaptionClips(
  EditorProject project,
  MediaTime playhead,
) sync* {
  for (final lane in project.lanes) {
    if (lane.hidden || lane.kind != EditorLaneKind.captions) continue;
    yield* lane.clips.whereType<EditorCaptionClip>().where(
      (clip) => clip.contains(playhead),
    );
  }
}
