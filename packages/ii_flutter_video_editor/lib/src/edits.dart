import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';
import 'package:meta/meta.dart';

@immutable
final class EditorSplitResult {
  const EditorSplitResult({required this.project, required this.selection});

  final EditorProject project;
  final EditorSelection selection;
}

bool canSplitEditorClip(EditorClip clip, MediaTime at) =>
    at > clip.timelineStart && at < clip.timelineEnd;

/// Whether [selection] identifies a splittable editing unit.
///
/// A link group is one editing unit, so one locked member disables the split
/// even when that member does not intersect [at].
bool canSplitEditorSelection(
  EditorProject project,
  EditorSelection? selection,
  MediaTime at,
) {
  if (selection == null) return false;
  final lane = project.laneById(selection.laneId);
  if (lane == null || lane.locked) return false;
  final selected = lane.clips
      .where((clip) => clip.id == selection.clipId)
      .firstOrNull;
  if (selected == null || !canSplitEditorClip(selected, at)) return false;
  final group = selected.linkGroupId;
  return !project.lanes.any(
    (candidateLane) =>
        candidateLane.locked &&
        candidateLane.clips.any(
          (clip) =>
              clip.id == selected.id ||
              (group != null && clip.linkGroupId == group),
        ),
  );
}

List<EditorClip> activeEditorClips(
  EditorProject project,
  MediaTime at,
) => List<EditorClip>.unmodifiable(
  project.lanes
      .where(
        (lane) =>
            !lane.hidden && !(lane.kind == EditorLaneKind.audio && lane.muted),
      )
      .expand((lane) => lane.clips)
      .where((clip) => clip.contains(at)),
);

/// Whether [selection] identifies an unlocked clip group that can be removed.
///
/// Linked clips are one editing unit until the caller explicitly detaches them.
bool canRemoveEditorClip(EditorProject project, EditorSelection? selection) {
  if (selection == null) return false;
  final lane = project.laneById(selection.laneId);
  if (lane == null) return false;
  EditorClip? selected;
  for (final clip in lane.clips) {
    if (clip.id == selection.clipId) selected = clip;
  }
  if (selected == null) return false;
  final linkGroupId = selected.linkGroupId;
  return !project.lanes.any(
    (candidateLane) =>
        candidateLane.locked &&
        candidateLane.clips.any(
          (clip) =>
              clip.id == selected!.id ||
              (linkGroupId != null && clip.linkGroupId == linkGroupId),
        ),
  );
}

/// Removes the selected clip and any media linked to it, leaving timeline gaps.
EditorProject removeEditorClip({
  required EditorProject project,
  required EditorSelection selection,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final selectedLane = project.laneById(selection.laneId);
  if (selectedLane == null) {
    throw EditorValidationException(
      'Selected lane does not exist: ${selection.laneId}.',
    );
  }
  EditorClip? selected;
  for (final clip in selectedLane.clips) {
    if (clip.id == selection.clipId) selected = clip;
  }
  if (selected == null) {
    throw EditorValidationException(
      'Selected clip does not exist in lane ${selectedLane.id}: '
      '${selection.clipId}.',
    );
  }

  final linkGroupId = selected.linkGroupId;
  bool belongsToSelection(EditorClip clip) =>
      clip.id == selected!.id ||
      (linkGroupId != null && clip.linkGroupId == linkGroupId);
  if (project.lanes.any(
    (lane) => lane.locked && lane.clips.any(belongsToSelection),
  )) {
    throw const EditorValidationException(
      'Selected media includes a locked lane.',
    );
  }

  final next = project.copyWith(
    lanes: [
      for (final lane in project.lanes)
        lane.copyWith(
          clips: lane.clips.where((clip) => !belongsToSelection(clip)),
        ),
    ],
  );
  validateEditorProject(next, limits: limits);
  return next;
}

EditorSplitResult splitEditorClip({
  required EditorProject project,
  required EditorSelection selection,
  required MediaTime at,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final laneIndex = project.lanes.indexWhere(
    (lane) => lane.id == selection.laneId,
  );
  if (laneIndex < 0) {
    throw EditorValidationException(
      'Selected lane does not exist: ${selection.laneId}.',
    );
  }
  final lane = project.lanes[laneIndex];
  if (lane.locked) {
    throw EditorValidationException('Lane ${lane.id} is locked.');
  }
  final clipIndex = lane.clips.indexWhere(
    (clip) => clip.id == selection.clipId,
  );
  if (clipIndex < 0) {
    throw EditorValidationException(
      'Selected clip does not exist in lane ${lane.id}: ${selection.clipId}.',
    );
  }
  final clip = lane.clips[clipIndex];
  if (!canSplitEditorClip(clip, at)) {
    throw EditorValidationException(
      'Cut position must be strictly inside clip ${clip.id}.',
    );
  }

  final linkGroupId = clip.linkGroupId;
  if (!canSplitEditorSelection(project, selection, at)) {
    throw const EditorValidationException(
      'Selected media includes a locked lane.',
    );
  }
  final rightLinkGroupId = linkGroupId == null
      ? null
      : _nextSplitLinkGroupId(project, linkGroupId, at);
  String? selectedRightId;
  final nextLanes = <EditorLane>[];
  for (final currentLane in project.lanes) {
    if (currentLane.locked) {
      nextLanes.add(currentLane);
      continue;
    }
    final nextClips = <EditorClip>[];
    for (final currentClip in currentLane.clips) {
      final linked =
          currentClip.id == clip.id ||
          (linkGroupId != null && currentClip.linkGroupId == linkGroupId);
      if (!linked) {
        nextClips.add(currentClip);
        continue;
      }
      if (!canSplitEditorClip(currentClip, at)) {
        nextClips.add(
          rightLinkGroupId != null && currentClip.timelineStart >= at
              ? _copyClipWithLinkGroup(currentClip, rightLinkGroupId)
              : currentClip,
        );
        continue;
      }
      final leftDuration = at - currentClip.timelineStart;
      final rightDuration = currentClip.duration - leftDuration;
      final rightId = _nextSplitId(project, currentClip.id, at);
      final (left, right) = _splitClip(
        currentClip,
        leftDuration: leftDuration,
        rightDuration: rightDuration,
        rightId: rightId,
        leftLinkGroupId: currentClip.linkGroupId,
        rightLinkGroupId: rightLinkGroupId,
        at: at,
      );
      nextClips.addAll([left, right]);
      if (currentClip.id == clip.id) selectedRightId = right.id;
    }
    nextLanes.add(currentLane.copyWith(clips: nextClips));
  }
  final nextProject = project.copyWith(lanes: nextLanes);
  validateEditorProject(nextProject, limits: limits);
  return EditorSplitResult(
    project: nextProject,
    selection: EditorSelection(laneId: lane.id, clipId: selectedRightId!),
  );
}

EditorClip _copyClipWithLinkGroup(EditorClip clip, String linkGroupId) =>
    switch (clip) {
      EditorVideoClip() => EditorVideoClip(
        id: clip.id,
        linkGroupId: linkGroupId,
        timelineStart: clip.timelineStart,
        duration: clip.duration,
        source: clip.source,
        sourceRange: clip.sourceRange,
        sourceDuration: clip.sourceDuration,
        destination: clip.destination,
        fit: clip.fit,
        opacity: clip.opacity,
        transition: clip.transition,
      ),
      EditorAudioClip() => EditorAudioClip(
        id: clip.id,
        linkGroupId: linkGroupId,
        timelineStart: clip.timelineStart,
        duration: clip.duration,
        source: clip.source,
        sourceRange: clip.sourceRange,
        sourceDuration: clip.sourceDuration,
        volume: clip.volume,
      ),
      EditorCaptionClip() => EditorCaptionClip(
        id: clip.id,
        linkGroupId: linkGroupId,
        timelineStart: clip.timelineStart,
        duration: clip.duration,
        text: clip.text,
        destination: clip.destination,
        style: clip.style,
      ),
    };

(EditorClip, EditorClip) _splitClip(
  EditorClip clip, {
  required MediaTime leftDuration,
  required MediaTime rightDuration,
  required String rightId,
  required String? leftLinkGroupId,
  required String? rightLinkGroupId,
  required MediaTime at,
}) {
  return switch (clip) {
    EditorVideoClip() => (
      EditorVideoClip(
        id: clip.id,
        linkGroupId: leftLinkGroupId,
        timelineStart: clip.timelineStart,
        duration: leftDuration,
        source: clip.source,
        sourceRange: MediaRange(
          start: clip.sourceRange.start,
          duration: leftDuration,
        ),
        sourceDuration: clip.sourceDuration,
        destination: clip.destination,
        fit: clip.fit,
        opacity: clip.opacity,
        transition: _clampedTransition(clip.transition, leftDuration),
      ),
      EditorVideoClip(
        id: rightId,
        linkGroupId: rightLinkGroupId,
        timelineStart: at,
        duration: rightDuration,
        source: clip.source,
        sourceRange: MediaRange(
          start: clip.sourceRange.start + leftDuration,
          duration: rightDuration,
        ),
        sourceDuration: clip.sourceDuration,
        destination: clip.destination,
        fit: clip.fit,
        opacity: clip.opacity,
      ),
    ),
    EditorAudioClip() => (
      EditorAudioClip(
        id: clip.id,
        linkGroupId: leftLinkGroupId,
        timelineStart: clip.timelineStart,
        duration: leftDuration,
        source: clip.source,
        sourceRange: MediaRange(
          start: clip.sourceRange.start,
          duration: leftDuration,
        ),
        sourceDuration: clip.sourceDuration,
        volume: clip.volume,
      ),
      EditorAudioClip(
        id: rightId,
        linkGroupId: rightLinkGroupId,
        timelineStart: at,
        duration: rightDuration,
        source: clip.source,
        sourceRange: MediaRange(
          start: clip.sourceRange.start + leftDuration,
          duration: rightDuration,
        ),
        sourceDuration: clip.sourceDuration,
        volume: clip.volume,
      ),
    ),
    EditorCaptionClip() => (
      EditorCaptionClip(
        id: clip.id,
        linkGroupId: leftLinkGroupId,
        timelineStart: clip.timelineStart,
        duration: leftDuration,
        text: clip.text,
        destination: clip.destination,
        style: clip.style,
      ),
      EditorCaptionClip(
        id: rightId,
        linkGroupId: rightLinkGroupId,
        timelineStart: at,
        duration: rightDuration,
        text: clip.text,
        destination: clip.destination,
        style: clip.style,
      ),
    ),
  };
}

String _nextSplitLinkGroupId(
  EditorProject project,
  String original,
  MediaTime at,
) {
  final prefix = original.length <= 80 ? original : original.substring(0, 80);
  final base = '$prefix.s${at.microseconds}';
  final groups = project.clips.map((clip) => clip.linkGroupId).toSet();
  if (!groups.contains(base)) return base;
  for (var suffix = 2; suffix <= 999; suffix++) {
    final candidate = '$base-$suffix';
    if (!groups.contains(candidate)) return candidate;
  }
  throw const EditorValidationException(
    'Unable to allocate a unique bounded split link group ID.',
  );
}

String _nextSplitId(EditorProject project, String original, MediaTime at) {
  final prefix = original.length <= 80 ? original : original.substring(0, 80);
  final base = '$prefix.s${at.microseconds}';
  final ids = project.clips.map((clip) => clip.id).toSet();
  if (!ids.contains(base)) return base;
  for (var suffix = 2; suffix <= 999; suffix++) {
    final candidate = '$base-$suffix';
    if (!ids.contains(candidate)) return candidate;
  }
  throw const EditorValidationException(
    'Unable to allocate a unique bounded split clip ID.',
  );
}

EditorTransition? _clampedTransition(
  EditorTransition? transition,
  MediaTime duration,
) {
  if (transition == null) return null;
  if (transition.duration <= duration) return transition;
  return transition.copyWith(duration: duration);
}
