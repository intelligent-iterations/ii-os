import 'dart:math' as math;

import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';
import 'package:meta/meta.dart';

enum EditorTrimEdge { start, end }

@immutable
final class EditorMoveResolution {
  const EditorMoveResolution({
    required this.targetLaneId,
    required this.timelineStart,
    this.snapGuide,
  });

  final String targetLaneId;
  final MediaTime timelineStart;
  final MediaTime? snapGuide;
}

@immutable
final class EditorTrimResolution {
  const EditorTrimResolution({required this.edgeTime, this.snapGuide});

  final MediaTime edgeTime;
  final MediaTime? snapGuide;
}

EditorProject moveEditorClip({
  required EditorProject project,
  required EditorSelection selection,
  required String targetLaneId,
  required MediaTime timelineStart,
  EditorLimits limits = const EditorLimits(),
}) {
  final group = _selectedGroup(project, selection, limits);
  final anchor = group.anchor;
  final targetLane = project.laneById(targetLaneId);
  if (targetLane == null) {
    throw EditorValidationException(
      'Target lane does not exist: $targetLaneId.',
    );
  }
  if (targetLane.locked || targetLane.kind != anchor.lane.kind) {
    throw EditorValidationException(
      'Target lane $targetLaneId is locked or incompatible.',
    );
  }
  _requireUnlocked(group);
  final delta =
      timelineStart.microseconds - anchor.clip.timelineStart.microseconds;
  final targets = <String, String>{
    for (final member in group.members) member.clip.id: member.lane.id,
    anchor.clip.id: targetLaneId,
  };
  final replacements = <String, EditorClip>{};
  for (final member in group.members) {
    final start = member.clip.timelineStart.microseconds + delta;
    if (start < 0) {
      throw const EditorValidationException(
        'A moved clip cannot start before zero.',
      );
    }
    replacements[member.clip.id] = _copyClip(
      member.clip,
      timelineStart: MediaTime.microseconds(start),
    );
  }
  final lanes = _replaceClips(project, replacements, targets);
  final duration = _expandedDuration(project.duration, replacements.values);
  final result = project.copyWith(lanes: lanes, duration: duration);
  validateEditorProject(result, limits: limits);
  return result;
}

EditorProject trimEditorClip({
  required EditorProject project,
  required EditorSelection selection,
  required EditorTrimEdge edge,
  required MediaTime edgeTime,
  EditorLimits limits = const EditorLimits(),
}) {
  final group = _selectedGroup(project, selection, limits);
  _requireUnlocked(group);
  final anchorEdge = edge == EditorTrimEdge.start
      ? group.anchor.clip.timelineStart
      : group.anchor.clip.timelineEnd;
  final delta = edgeTime.microseconds - anchorEdge.microseconds;
  final replacements = <String, EditorClip>{};
  for (final member in group.members) {
    replacements[member.clip.id] = _trimmedClip(member.clip, edge, delta);
  }
  final targets = <String, String>{
    for (final member in group.members) member.clip.id: member.lane.id,
  };
  final lanes = _replaceClips(project, replacements, targets);
  final duration = _expandedDuration(project.duration, replacements.values);
  final result = project.copyWith(lanes: lanes, duration: duration);
  validateEditorProject(result, limits: limits);
  return result;
}

EditorMoveResolution resolveEditorClipMove({
  required EditorProject project,
  required EditorSelection selection,
  required String targetLaneId,
  required MediaTime proposedTimelineStart,
  required MediaTime playhead,
  required MediaTime snapThreshold,
  EditorLimits limits = const EditorLimits(),
}) {
  final group = _selectedGroup(project, selection, limits);
  final anchor = group.anchor;
  final targetLane = project.laneById(targetLaneId);
  if (targetLane == null ||
      targetLane.locked ||
      targetLane.kind != anchor.lane.kind) {
    return EditorMoveResolution(
      targetLaneId: anchor.lane.id,
      timelineStart: anchor.clip.timelineStart,
    );
  }
  final rawStart = _frameTime(proposedTimelineStart, project.framesPerSecond);
  final rawDelta =
      rawStart.microseconds - anchor.clip.timelineStart.microseconds;
  final targets = _snapTargets(project, group, playhead);
  final snapped = _snapMoveDelta(group, rawDelta, targets, snapThreshold);
  final legal = _nearestLegalMoveDelta(
    project: project,
    group: group,
    targetLaneId: targetLaneId,
    proposedDelta: snapped.delta,
    limits: limits,
  );
  return EditorMoveResolution(
    targetLaneId: targetLaneId,
    timelineStart: MediaTime.microseconds(
      anchor.clip.timelineStart.microseconds + legal,
    ),
    snapGuide: legal == snapped.delta ? snapped.guide : null,
  );
}

EditorTrimResolution resolveEditorClipTrim({
  required EditorProject project,
  required EditorSelection selection,
  required EditorTrimEdge edge,
  required MediaTime proposedEdgeTime,
  required MediaTime playhead,
  required MediaTime snapThreshold,
  EditorLimits limits = const EditorLimits(),
}) {
  final group = _selectedGroup(project, selection, limits);
  final anchorEdge = edge == EditorTrimEdge.start
      ? group.anchor.clip.timelineStart
      : group.anchor.clip.timelineEnd;
  final framed = _frameTime(proposedEdgeTime, project.framesPerSecond);
  final rawDelta = framed.microseconds - anchorEdge.microseconds;
  final snapped = _snapEdgeDelta(
    group,
    edge,
    rawDelta,
    _snapTargets(project, group, playhead),
    snapThreshold,
  );
  final bounds = _trimDeltaBounds(project, group, edge, limits);
  final delta = snapped.delta.clamp(bounds.$1, bounds.$2);
  return EditorTrimResolution(
    edgeTime: MediaTime.microseconds(anchorEdge.microseconds + delta),
    snapGuide: delta == snapped.delta ? snapped.guide : null,
  );
}

typedef _SnapDelta = ({int delta, MediaTime? guide});

_SnapDelta _snapMoveDelta(
  _ClipGroup group,
  int rawDelta,
  List<MediaTime> targets,
  MediaTime threshold,
) {
  _SnapDelta best = (delta: rawDelta, guide: null);
  var distance = threshold.microseconds + 1;
  for (final member in group.members) {
    for (final edge in [member.clip.timelineStart, member.clip.timelineEnd]) {
      for (final target in targets) {
        final candidate = target.microseconds - edge.microseconds;
        final candidateDistance = (candidate - rawDelta).abs();
        if (candidateDistance <= threshold.microseconds &&
            candidateDistance < distance) {
          distance = candidateDistance;
          best = (delta: candidate, guide: target);
        }
      }
    }
  }
  return best;
}

_SnapDelta _snapEdgeDelta(
  _ClipGroup group,
  EditorTrimEdge edge,
  int rawDelta,
  List<MediaTime> targets,
  MediaTime threshold,
) {
  _SnapDelta best = (delta: rawDelta, guide: null);
  var distance = threshold.microseconds + 1;
  for (final member in group.members) {
    final memberEdge = edge == EditorTrimEdge.start
        ? member.clip.timelineStart
        : member.clip.timelineEnd;
    for (final target in targets) {
      final candidate = target.microseconds - memberEdge.microseconds;
      final candidateDistance = (candidate - rawDelta).abs();
      if (candidateDistance <= threshold.microseconds &&
          candidateDistance < distance) {
        distance = candidateDistance;
        best = (delta: candidate, guide: target);
      }
    }
  }
  return best;
}

int _nearestLegalMoveDelta({
  required EditorProject project,
  required _ClipGroup group,
  required String targetLaneId,
  required int proposedDelta,
  required EditorLimits limits,
}) {
  final candidates = <int>{proposedDelta, 0};
  for (final member in group.members) {
    final laneId = member == group.anchor ? targetLaneId : member.lane.id;
    final lane = project.laneById(laneId)!;
    candidates
      ..add(-member.clip.timelineStart.microseconds)
      ..add(
        limits.maxDuration.inMicroseconds -
            member.clip.timelineEnd.microseconds,
      );
    for (final other in lane.clips.where(
      (clip) => !group.ids.contains(clip.id),
    )) {
      candidates.add(
        other.timelineStart.microseconds - member.clip.timelineEnd.microseconds,
      );
      candidates.add(
        other.timelineEnd.microseconds - member.clip.timelineStart.microseconds,
      );
    }
  }
  final legal = candidates
      .where(
        (delta) => _isLegalMove(project, group, targetLaneId, delta, limits),
      )
      .toList();
  if (legal.isEmpty) return 0;
  legal.sort(
    (a, b) => (a - proposedDelta).abs().compareTo((b - proposedDelta).abs()),
  );
  return legal.first;
}

bool _isLegalMove(
  EditorProject project,
  _ClipGroup group,
  String targetLaneId,
  int delta,
  EditorLimits limits,
) {
  for (final member in group.members) {
    final laneId = member == group.anchor ? targetLaneId : member.lane.id;
    final lane = project.laneById(laneId);
    if (lane == null || lane.locked || lane.kind != member.lane.kind) {
      return false;
    }
    final start = member.clip.timelineStart.microseconds + delta;
    final end = member.clip.timelineEnd.microseconds + delta;
    if (start < 0 || end > limits.maxDuration.inMicroseconds) return false;
    for (final other in lane.clips.where(
      (clip) => !group.ids.contains(clip.id),
    )) {
      if (start < other.timelineEnd.microseconds &&
          end > other.timelineStart.microseconds) {
        return false;
      }
    }
  }
  return true;
}

(int, int) _trimDeltaBounds(
  EditorProject project,
  _ClipGroup group,
  EditorTrimEdge edge,
  EditorLimits limits,
) {
  final minimumDuration =
      (Duration.microsecondsPerSecond / project.framesPerSecond).ceil();
  var lower = -limits.maxDuration.inMicroseconds;
  var upper = limits.maxDuration.inMicroseconds;
  for (final member in group.members) {
    final others = member.lane.clips.where(
      (clip) => !group.ids.contains(clip.id),
    );
    if (edge == EditorTrimEdge.start) {
      final previousEnd = others
          .where((clip) => clip.timelineEnd <= member.clip.timelineStart)
          .fold(
            0,
            (value, clip) => math.max(value, clip.timelineEnd.microseconds),
          );
      lower = math.max(
        lower,
        previousEnd - member.clip.timelineStart.microseconds,
      );
      lower = math.max(lower, -_sourceStart(member.clip));
      upper = math.min(
        upper,
        member.clip.duration.microseconds - minimumDuration,
      );
    } else {
      final nextStart = others
          .where((clip) => clip.timelineStart >= member.clip.timelineEnd)
          .fold(
            limits.maxDuration.inMicroseconds,
            (value, clip) => math.min(value, clip.timelineStart.microseconds),
          );
      lower = math.max(
        lower,
        -(member.clip.duration.microseconds - minimumDuration),
      );
      upper = math.min(upper, nextStart - member.clip.timelineEnd.microseconds);
      upper = math.min(upper, _sourceRemaining(member.clip));
      upper = math.min(
        upper,
        limits.maxDuration.inMicroseconds -
            member.clip.timelineEnd.microseconds,
      );
    }
  }
  return (lower, upper);
}

int _sourceStart(EditorClip clip) => switch (clip) {
  EditorVideoClip() => clip.sourceRange.start.microseconds,
  EditorAudioClip() => clip.sourceRange.start.microseconds,
  EditorCaptionClip() => clip.timelineStart.microseconds,
};

int _sourceRemaining(EditorClip clip) => switch (clip) {
  EditorVideoClip() =>
    clip.sourceDuration.microseconds - clip.sourceRange.end.microseconds,
  EditorAudioClip() =>
    clip.sourceDuration.microseconds - clip.sourceRange.end.microseconds,
  EditorCaptionClip() => 1 << 60,
};

List<MediaTime> _snapTargets(
  EditorProject project,
  _ClipGroup group,
  MediaTime playhead,
) => [
  MediaTime.zero,
  playhead,
  for (final lane in project.lanes)
    for (final clip in lane.clips)
      if (!group.ids.contains(clip.id)) ...[
        clip.timelineStart,
        clip.timelineEnd,
      ],
];

MediaTime _frameTime(MediaTime value, int framesPerSecond) {
  final frame =
      (value.microseconds * framesPerSecond / Duration.microsecondsPerSecond)
          .round();
  return MediaTime.microseconds(
    (frame * Duration.microsecondsPerSecond / framesPerSecond).round(),
  );
}

EditorClip _trimmedClip(EditorClip clip, EditorTrimEdge edge, int delta) {
  final start = edge == EditorTrimEdge.start
      ? clip.timelineStart.microseconds + delta
      : clip.timelineStart.microseconds;
  final duration = edge == EditorTrimEdge.start
      ? clip.duration.microseconds - delta
      : clip.duration.microseconds + delta;
  if (start < 0 || duration <= 0) {
    throw const EditorValidationException(
      'Trim would create invalid clip timing.',
    );
  }
  final sourceStart = edge == EditorTrimEdge.start
      ? _sourceStart(clip) + delta
      : _sourceStart(clip);
  if (sourceStart < 0) {
    throw const EditorValidationException(
      'Trim exceeds available source media.',
    );
  }
  return _copyClip(
    clip,
    timelineStart: MediaTime.microseconds(start),
    duration: MediaTime.microseconds(duration),
    sourceStart: MediaTime.microseconds(sourceStart),
  );
}

EditorClip _copyClip(
  EditorClip clip, {
  required MediaTime timelineStart,
  MediaTime? duration,
  MediaTime? sourceStart,
}) {
  final nextDuration = duration ?? clip.duration;
  return switch (clip) {
    EditorVideoClip() => EditorVideoClip(
      id: clip.id,
      linkGroupId: clip.linkGroupId,
      timelineStart: timelineStart,
      duration: nextDuration,
      source: clip.source,
      sourceRange: MediaRange(
        start: sourceStart ?? clip.sourceRange.start,
        duration: nextDuration,
      ),
      sourceDuration: clip.sourceDuration,
      destination: clip.destination,
      fit: clip.fit,
      opacity: clip.opacity,
      transition: _boundedTransition(clip.transition, nextDuration),
    ),
    EditorAudioClip() => EditorAudioClip(
      id: clip.id,
      linkGroupId: clip.linkGroupId,
      timelineStart: timelineStart,
      duration: nextDuration,
      source: clip.source,
      sourceRange: MediaRange(
        start: sourceStart ?? clip.sourceRange.start,
        duration: nextDuration,
      ),
      sourceDuration: clip.sourceDuration,
      volume: clip.volume,
    ),
    EditorCaptionClip() => EditorCaptionClip(
      id: clip.id,
      linkGroupId: clip.linkGroupId,
      timelineStart: timelineStart,
      duration: nextDuration,
      text: clip.text,
      destination: clip.destination,
      style: clip.style,
    ),
  };
}

List<EditorLane> _replaceClips(
  EditorProject project,
  Map<String, EditorClip> replacements,
  Map<String, String> targetLaneIds,
) => [
  for (final lane in project.lanes)
    lane.copyWith(
      clips: [
        ...lane.clips.where((clip) => !replacements.containsKey(clip.id)),
        for (final entry in replacements.entries)
          if (targetLaneIds[entry.key] == lane.id) entry.value,
      ]..sort((a, b) => a.timelineStart.compareTo(b.timelineStart)),
    ),
];

MediaTime _expandedDuration(MediaTime current, Iterable<EditorClip> clips) =>
    clips.fold(
      current,
      (duration, clip) =>
          clip.timelineEnd > duration ? clip.timelineEnd : duration,
    );

void _requireUnlocked(_ClipGroup group) {
  if (group.members.any((member) => member.lane.locked)) {
    throw const EditorValidationException(
      'Linked media includes a locked lane.',
    );
  }
}

_ClipGroup _selectedGroup(
  EditorProject project,
  EditorSelection selection,
  EditorLimits limits,
) {
  validateEditorProject(project, limits: limits);
  final members = <_ClipMember>[];
  _ClipMember? anchor;
  for (final lane in project.lanes) {
    for (final clip in lane.clips) {
      final member = _ClipMember(lane: lane, clip: clip);
      if (lane.id == selection.laneId && clip.id == selection.clipId) {
        anchor = member;
      }
    }
  }
  if (anchor == null) {
    throw const EditorValidationException(
      'Selection does not identify a clip.',
    );
  }
  final linkGroupId = anchor.clip.linkGroupId;
  for (final lane in project.lanes) {
    for (final clip in lane.clips) {
      if (clip.id == anchor.clip.id ||
          (linkGroupId != null && clip.linkGroupId == linkGroupId)) {
        members.add(_ClipMember(lane: lane, clip: clip));
      }
    }
  }
  return _ClipGroup(anchor: anchor, members: members);
}

final class _ClipMember {
  const _ClipMember({required this.lane, required this.clip});
  final EditorLane lane;
  final EditorClip clip;
}

final class _ClipGroup {
  const _ClipGroup({required this.anchor, required this.members});
  final _ClipMember anchor;
  final List<_ClipMember> members;
  Set<String> get ids => members.map((member) => member.clip.id).toSet();
}

EditorTransition? _boundedTransition(
  EditorTransition? transition,
  MediaTime duration,
) {
  if (transition == null) return null;
  if (transition.duration <= duration) return transition;
  return transition.copyWith(duration: duration);
}
