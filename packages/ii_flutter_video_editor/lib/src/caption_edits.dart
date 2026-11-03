import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';

/// Places an ungrouped caption without changing established visual stacking.
///
/// The existing topmost visual lane is reused only when it is a visible,
/// unlocked caption lane whose half-open clip ranges do not overlap [caption].
/// Audio lanes above that caption lane do not affect visual order.
/// A lower caption lane is never reused past a later video or caption lane
/// because packing into it could put the new caption below another visual.
/// When reuse is unsafe, a fresh topmost caption lane is appended with
/// [newLaneId] and [newLaneLabel]. The project duration is never extended.
EditorProject placeEditorCaption({
  required EditorProject project,
  required EditorCaptionClip caption,
  required String newLaneId,
  required String newLaneLabel,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  if (caption.linkGroupId != null) {
    throw const EditorValidationException(
      'A newly placed caption must not belong to an edit group.',
    );
  }

  EditorLane? topVisualLane;
  for (final lane in project.lanes.reversed) {
    if (lane.kind == EditorLaneKind.video ||
        lane.kind == EditorLaneKind.captions) {
      topVisualLane = lane;
      break;
    }
  }
  final reusable =
      topVisualLane != null &&
      topVisualLane.kind == EditorLaneKind.captions &&
      !topVisualLane.hidden &&
      !topVisualLane.locked &&
      topVisualLane.clips.every(
        (existing) =>
            caption.timelineEnd <= existing.timelineStart ||
            caption.timelineStart >= existing.timelineEnd,
      );

  final existingIds = <String>{
    for (final lane in project.lanes) lane.id,
    for (final clip in project.clips) clip.id,
    for (final clip in project.clips) ?clip.linkGroupId,
    for (final clip in project.clips.whereType<EditorVideoClip>())
      clip.source.id,
    for (final clip in project.clips.whereType<EditorAudioClip>())
      clip.source.id,
  };
  final proposedIds = <String>[caption.id, if (!reusable) newLaneId];
  if (proposedIds.toSet().length != proposedIds.length ||
      proposedIds.any(existingIds.contains)) {
    throw const EditorValidationException(
      'New caption and fallback-lane identifiers must be fresh and distinct.',
    );
  }

  final lanes = <EditorLane>[];
  if (reusable) {
    for (final lane in project.lanes) {
      if (lane.id != topVisualLane.id) {
        lanes.add(lane);
        continue;
      }
      final clips = <EditorClip>[...lane.clips, caption]
        ..sort(
          (left, right) => left.timelineStart.microseconds.compareTo(
            right.timelineStart.microseconds,
          ),
        );
      lanes.add(lane.copyWith(clips: clips));
    }
  } else {
    lanes.addAll(project.lanes);
    lanes.add(
      EditorLane(
        id: newLaneId,
        label: newLaneLabel,
        kind: EditorLaneKind.captions,
        clips: [caption],
      ),
    );
  }

  final next = project.copyWith(lanes: lanes);
  validateEditorProject(next, limits: limits);
  return next;
}
