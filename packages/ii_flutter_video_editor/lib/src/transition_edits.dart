import 'dart:math' as math;

import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';

final RegExp _hexColor = RegExp(r'^[0-9A-Fa-f]{6}$');

/// The clip that ends exactly where [clip] begins, in the same lane.
EditorVideoClip? editorTransitionPredecessor(EditorLane lane, EditorClip clip) {
  for (final other in lane.clips) {
    if (other.id != clip.id &&
        other is EditorVideoClip &&
        other.timelineEnd == clip.timelineStart) {
      return other;
    }
  }
  return null;
}

/// The longest transition the cut in front of [selection] can hold. Zero means
/// this clip cannot carry one at all.
MediaTime maxEditorTransitionDuration(
  EditorProject project,
  EditorSelection? selection,
) {
  final found = _findVideoClip(project, selection);
  if (found == null) return MediaTime.zero;
  var limit = math.min(
    found.clip.duration.microseconds,
    editorMaxTransitionDuration.inMicroseconds,
  );
  final previous = editorTransitionPredecessor(found.lane, found.clip);
  if (previous != null) {
    limit = math.min(limit, previous.duration.microseconds);
  }
  return MediaTime.microseconds(limit);
}

/// Whether [selection] names a clip that a transition can be placed on.
bool canSetEditorClipTransition(
  EditorProject project,
  EditorSelection? selection,
) => maxEditorTransitionDuration(project, selection) > MediaTime.zero;

EditorProject setEditorClipTransition({
  required EditorProject project,
  required EditorSelection selection,
  required EditorTransition transition,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final found = _findVideoClip(project, selection);
  if (found == null) {
    throw const EditorValidationException(
      'Only a picture clip on an unlocked lane can carry a transition.',
    );
  }
  if (!_hexColor.hasMatch(transition.color)) {
    throw const EditorValidationException(
      'A transition colour must be six hex digits.',
    );
  }
  final frame = (Duration.microsecondsPerSecond / project.framesPerSecond)
      .ceil();
  final longest = maxEditorTransitionDuration(project, selection);
  if (transition.duration.microseconds < frame ||
      transition.duration > longest) {
    throw EditorValidationException(
      'A transition here must run between one frame and '
      '${longest.inSeconds.toStringAsFixed(2)} seconds.',
    );
  }
  return _withTransition(project, found, transition, limits);
}

EditorProject clearEditorClipTransition({
  required EditorProject project,
  required EditorSelection selection,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final found = _findVideoClip(project, selection);
  if (found == null) {
    throw const EditorValidationException(
      'That clip cannot carry a transition.',
    );
  }
  return _withTransition(project, found, null, limits);
}

EditorProject _withTransition(
  EditorProject project,
  ({EditorLane lane, EditorVideoClip clip}) found,
  EditorTransition? transition,
  EditorLimits limits,
) {
  final replacement = withEditorClipTransition(found.clip, transition);
  final next = project.copyWith(
    lanes: [
      for (final lane in project.lanes)
        if (lane.id != found.lane.id)
          lane
        else
          lane.copyWith(
            clips: [
              for (final clip in lane.clips)
                if (clip.id == found.clip.id) replacement else clip,
            ],
          ),
    ],
  );
  validateEditorProject(next, limits: limits);
  return next;
}

/// A copy of [clip] carrying [transition], or none when it is null.
EditorVideoClip withEditorClipTransition(
  EditorVideoClip clip,
  EditorTransition? transition,
) => EditorVideoClip(
  id: clip.id,
  linkGroupId: clip.linkGroupId,
  timelineStart: clip.timelineStart,
  duration: clip.duration,
  source: clip.source,
  sourceRange: clip.sourceRange,
  sourceDuration: clip.sourceDuration,
  destination: clip.destination,
  fit: clip.fit,
  opacity: clip.opacity,
  transition: transition,
);

({EditorLane lane, EditorVideoClip clip})? _findVideoClip(
  EditorProject project,
  EditorSelection? selection,
) {
  if (selection == null) return null;
  final lane = project.laneById(selection.laneId);
  if (lane == null || lane.locked) return null;
  for (final clip in lane.clips) {
    if (clip.id == selection.clipId) {
      return clip is EditorVideoClip ? (lane: lane, clip: clip) : null;
    }
  }
  return null;
}
