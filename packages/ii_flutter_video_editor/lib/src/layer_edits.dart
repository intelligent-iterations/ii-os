import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';

const _stillImageExtensions = <String>{'png', 'jpg', 'jpeg', 'webp'};

/// The identifiers and label for one clip placed in a newly created lane.
final class EditorNewLanePlacement {
  const EditorNewLanePlacement({
    required this.laneId,
    required this.laneLabel,
    required this.clipId,
    required this.sourceRange,
    required this.sourceDuration,
    this.timelineOffset = MediaTime.zero,
  });

  factory EditorNewLanePlacement.fullSource({
    required String laneId,
    required String laneLabel,
    required String clipId,
    required MediaTime sourceDuration,
    MediaTime timelineOffset = MediaTime.zero,
  }) {
    if (sourceDuration == MediaTime.zero) {
      throw const EditorValidationException(
        'A new-lane source duration must be positive.',
      );
    }
    return EditorNewLanePlacement(
      laneId: laneId,
      laneLabel: laneLabel,
      clipId: clipId,
      sourceRange: MediaRange(start: MediaTime.zero, duration: sourceDuration),
      sourceDuration: sourceDuration,
      timelineOffset: timelineOffset,
    );
  }

  final String laneId;
  final String laneLabel;
  final String clipId;
  final MediaRange sourceRange;
  final MediaTime sourceDuration;

  /// Delay from the requested placement point to this decoded stream.
  ///
  /// Paired streams can begin at different presentation timestamps. Keeping
  /// that delta on the timeline prevents independent timestamp resets during
  /// compilation from pulling late audio or video forward.
  final MediaTime timelineOffset;
}

/// Adds one source as new concurrent lanes at [timelineStart].
///
/// This operation always appends fresh lanes: video becomes the top-most
/// visual and audio mixes with existing audio. It does not insert, overwrite,
/// reuse, or resolve collisions in an existing lane. A paired source requires
/// a fresh edit-group identity that is distinct from its source identity;
/// single-stream placements deliberately remain ungrouped. Paired lanes may
/// carry independent source ranges, available durations, and decoded timeline
/// offsets. [timelineStart] is the shared sync origin; each clip begins at that
/// origin plus its placement's offset. The origin may be anywhere through the
/// current project end, but this operation does not create a new gap before
/// that origin.
EditorProject addEditorSourceOnNewLanes({
  required EditorProject project,
  required MediaSource source,
  required MediaTime timelineStart,
  EditorNewLanePlacement? video,
  EditorNewLanePlacement? audio,
  String? linkGroupId,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  if (video == null && audio == null) {
    throw const EditorValidationException(
      'A new-lane placement requires video or audio.',
    );
  }
  if (timelineStart > project.duration) {
    throw const EditorValidationException(
      'A new-lane placement cannot start past the project end.',
    );
  }
  final paired = video != null && audio != null;
  if (paired != (linkGroupId != null)) {
    throw const EditorValidationException(
      'Only paired video and audio require one fresh edit group.',
    );
  }
  _validateNewPlacementNamespace(
    project: project,
    sourceId: source.id,
    video: video,
    audio: audio,
    linkGroupId: linkGroupId,
  );

  final group = paired ? linkGroupId : null;
  final lanes = <EditorLane>[...project.lanes];
  var placementEnd = timelineStart;
  if (video != null) {
    final videoStart = timelineStart + video.timelineOffset;
    final videoEnd = videoStart + video.sourceRange.duration;
    if (videoEnd > placementEnd) placementEnd = videoEnd;
    lanes.add(
      EditorLane(
        id: video.laneId,
        label: video.laneLabel,
        kind: EditorLaneKind.video,
        clips: [
          EditorVideoClip(
            id: video.clipId,
            timelineStart: videoStart,
            duration: video.sourceRange.duration,
            source: source,
            sourceRange: video.sourceRange,
            sourceDuration: video.sourceDuration,
            linkGroupId: group,
          ),
        ],
      ),
    );
  }
  if (audio != null) {
    final audioStart = timelineStart + audio.timelineOffset;
    final audioEnd = audioStart + audio.sourceRange.duration;
    if (audioEnd > placementEnd) placementEnd = audioEnd;
    lanes.add(
      EditorLane(
        id: audio.laneId,
        label: audio.laneLabel,
        kind: EditorLaneKind.audio,
        clips: [
          EditorAudioClip(
            id: audio.clipId,
            timelineStart: audioStart,
            duration: audio.sourceRange.duration,
            source: source,
            sourceRange: audio.sourceRange,
            sourceDuration: audio.sourceDuration,
            linkGroupId: group,
          ),
        ],
      ),
    );
  }
  final next = project.copyWith(
    duration: placementEnd > project.duration ? placementEnd : project.duration,
    lanes: lanes,
  );
  validateEditorProject(next, limits: limits);
  return next;
}

void _validateNewPlacementNamespace({
  required EditorProject project,
  required String sourceId,
  required EditorNewLanePlacement? video,
  required EditorNewLanePlacement? audio,
  required String? linkGroupId,
}) {
  final existing = <String>{
    for (final lane in project.lanes) lane.id,
    for (final clip in project.clips) clip.id,
    for (final clip in project.clips) ?clip.linkGroupId,
    for (final clip in project.clips.whereType<EditorVideoClip>())
      clip.source.id,
    for (final clip in project.clips.whereType<EditorAudioClip>())
      clip.source.id,
  };
  final proposed = <String>[
    if (video != null) ...[video.laneId, video.clipId],
    if (audio != null) ...[audio.laneId, audio.clipId],
    ?linkGroupId,
  ];
  final unique = proposed.toSet();
  if (unique.length != proposed.length ||
      unique.contains(sourceId) ||
      unique.any(existing.contains)) {
    throw const EditorValidationException(
      'New lane, clip, and edit-group identifiers must be fresh and distinct.',
    );
  }
}

/// Whether [clip] is a still image carried by a visual editor clip.
bool isEditorImageClip(EditorClip clip) =>
    clip is EditorVideoClip &&
    _stillImageExtensions.contains(clip.source.fileExtension);

/// Adds a bounded still image in a new top-most visual lane.
EditorProject addEditorImageOverlay({
  required EditorProject project,
  required String laneId,
  required String clipId,
  required MediaSource source,
  required MediaTime timelineStart,
  required MediaTime duration,
  String laneLabel = 'Image overlay',
  MediaRect destination = const MediaRect(
    x: 0.6,
    y: 0.05,
    width: 0.35,
    height: 0.35,
  ),
  MediaFit fit = MediaFit.contain,
  double opacity = 1,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  if (!_stillImageExtensions.contains(source.fileExtension)) {
    throw EditorValidationException(
      'Image overlays require PNG, JPG, JPEG, or WebP bytes; received '
      '.${source.fileExtension}.',
    );
  }
  final clip = EditorVideoClip(
    id: clipId,
    timelineStart: timelineStart,
    duration: duration,
    source: source,
    sourceRange: MediaRange(start: MediaTime.zero, duration: duration),
    destination: destination,
    fit: fit,
    opacity: opacity,
  );
  final next = project.copyWith(
    duration: clip.timelineEnd > project.duration
        ? clip.timelineEnd
        : project.duration,
    lanes: [
      ...project.lanes,
      EditorLane(
        id: laneId,
        label: laneLabel,
        kind: EditorLaneKind.video,
        clips: [clip],
      ),
    ],
  );
  validateEditorProject(next, limits: limits);
  return next;
}

/// Changes a visual clip's normalized canvas position and size.
EditorProject setEditorVisualDestination({
  required EditorProject project,
  required EditorSelection selection,
  required MediaRect destination,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final lane = project.laneById(selection.laneId);
  if (lane == null) {
    throw EditorValidationException(
      'Selected lane does not exist: ${selection.laneId}.',
    );
  }
  if (lane.locked) {
    throw EditorValidationException('Lane ${lane.id} is locked.');
  }
  final selected = lane.clips.where((clip) => clip.id == selection.clipId);
  if (selected.isEmpty || selected.single is! EditorVideoClip) {
    throw const EditorValidationException(
      'Selection does not identify a visual clip.',
    );
  }
  final clip = selected.single as EditorVideoClip;
  final replacement = EditorVideoClip(
    id: clip.id,
    linkGroupId: clip.linkGroupId,
    timelineStart: clip.timelineStart,
    duration: clip.duration,
    source: clip.source,
    sourceRange: clip.sourceRange,
    sourceDuration: clip.sourceDuration,
    destination: destination,
    fit: clip.fit,
    opacity: clip.opacity,
    transition: clip.transition,
  );
  final next = project.copyWith(
    lanes: [
      for (final candidateLane in project.lanes)
        candidateLane.id == lane.id
            ? candidateLane.copyWith(
                clips: [
                  for (final candidate in candidateLane.clips)
                    candidate.id == clip.id ? replacement : candidate,
                ],
              )
            : candidateLane,
    ],
  );
  validateEditorProject(next, limits: limits);
  return next;
}

/// Updates lane-level editing and render switches.
EditorProject updateEditorLane({
  required EditorProject project,
  required String laneId,
  bool? locked,
  bool? hidden,
  bool? muted,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final laneIndex = project.lanes.indexWhere((lane) => lane.id == laneId);
  if (laneIndex < 0) {
    throw EditorValidationException('Lane does not exist: $laneId.');
  }
  final lane = project.lanes[laneIndex];
  if (muted != null && lane.kind != EditorLaneKind.audio) {
    throw EditorValidationException('Only audio lanes can be muted: $laneId.');
  }
  final replacement = lane.copyWith(
    locked: locked,
    hidden: hidden,
    muted: muted,
  );
  final next = project.copyWith(
    lanes: [
      for (var index = 0; index < project.lanes.length; index++)
        index == laneIndex ? replacement : project.lanes[index],
    ],
  );
  validateEditorProject(next, limits: limits);
  return next;
}

/// Moves a lane in the bottom-to-top visual/audio ordering.
EditorProject moveEditorLane({
  required EditorProject project,
  required String laneId,
  required int toIndex,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final fromIndex = project.lanes.indexWhere((lane) => lane.id == laneId);
  if (fromIndex < 0) {
    throw EditorValidationException('Lane does not exist: $laneId.');
  }
  if (toIndex < 0 || toIndex >= project.lanes.length) {
    throw EditorValidationException('Lane destination is out of bounds.');
  }
  if (fromIndex == toIndex) return project;
  final lanes = project.lanes.toList();
  final lane = lanes.removeAt(fromIndex);
  lanes.insert(toIndex, lane);
  final next = project.copyWith(lanes: lanes);
  validateEditorProject(next, limits: limits);
  return next;
}
