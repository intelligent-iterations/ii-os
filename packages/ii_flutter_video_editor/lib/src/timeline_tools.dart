import 'package:ii_flutter_video_editor/src/edits.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';

/// Whether anything on an unlocked lane sits under [at].
bool canSliceEditorProject(EditorProject project, MediaTime at) =>
    _sliceTargets(project, at).isNotEmpty;

/// Cuts every unlocked lane at one position, the way a blade would.
EditorProject sliceEditorProject({
  required EditorProject project,
  required MediaTime at,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final targets = _sliceTargets(project, at);
  if (targets.isEmpty) {
    throw const EditorValidationException(
      'Nothing on the timeline is under this position.',
    );
  }
  var next = project;
  for (final target in targets) {
    final clip = next
        .laneById(target.laneId)
        ?.clips
        .where((candidate) => candidate.id == target.clipId);
    if (clip == null || clip.isEmpty) continue;
    if (!canSplitEditorClip(clip.first, at)) continue;
    next = splitEditorClip(
      project: next,
      selection: target,
      at: at,
      limits: limits,
    ).project;
  }
  return next;
}

/// Takes the span between [from] and [to] out of every lane. With [ripple] the
/// timeline closes up behind it; without, it leaves a gap.
EditorProject removeEditorSpan({
  required EditorProject project,
  required MediaTime from,
  required MediaTime to,
  bool ripple = true,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final end = to > project.duration ? project.duration : to;
  if (end <= from) {
    throw const EditorValidationException('A span must end after it starts.');
  }
  final splitLinkGroups = _splitLinkGroups(project, from, end);
  if (project.lanes.any(
    (lane) => _lockedLaneWouldChange(lane, from, end, ripple, splitLinkGroups),
  )) {
    throw const EditorValidationException(
      'A locked lane would change when this span is removed. '
      'Unlock it or choose a span after its last clip.',
    );
  }
  final span = end - from;
  final ids = _SpanRemainderIds(project, from);
  final lanes = [
    for (final lane in project.lanes)
      if (lane.locked)
        lane
      else
        lane.copyWith(
          clips: [
            for (final clip in lane.clips)
              ..._remainderOf(
                clip,
                from,
                end,
                span,
                ripple,
                splitLinkGroups,
                ids,
              ),
          ],
        ),
  ];
  final duration = ripple
      ? MediaTime.microseconds(
          project.duration.microseconds - span.microseconds,
        )
      : project.duration;
  if (duration == MediaTime.zero) {
    throw const EditorValidationException(
      'Removing this span would leave nothing on the timeline.',
    );
  }
  final next = project.copyWith(lanes: lanes, duration: duration);
  validateEditorProject(next, limits: limits);
  return next;
}

/// Whether the clip under [selection] still moves with a partner.
bool canDetachEditorClipAudio(
  EditorProject project,
  EditorSelection? selection,
) {
  final clip = _clipOf(project, selection);
  final group = clip?.linkGroupId;
  if (clip == null || group == null) return false;
  final lanes = project.lanes.where(
    (lane) => lane.clips.any((other) => other.linkGroupId == group),
  );
  return lanes.every((lane) => !lane.locked) &&
      project.clips.where((other) => other.linkGroupId == group).length > 1;
}

/// Separates a picture from the sound that arrived with it, so each one moves,
/// trims, and cuts on its own from here.
EditorProject detachEditorClipAudio({
  required EditorProject project,
  required EditorSelection selection,
  EditorLimits limits = const EditorLimits(),
}) {
  validateEditorProject(project, limits: limits);
  final clip = _clipOf(project, selection);
  if (clip == null) {
    throw const EditorValidationException(
      'Selection does not identify a clip.',
    );
  }
  final group = clip.linkGroupId;
  if (group == null ||
      project.clips.where((other) => other.linkGroupId == group).length < 2) {
    throw const EditorValidationException(
      'This clip already moves on its own.',
    );
  }
  for (final lane in project.lanes) {
    if (lane.locked && lane.clips.any((other) => other.linkGroupId == group)) {
      throw EditorValidationException(
        'Lane ${lane.id} is locked, so this pair cannot be separated.',
      );
    }
  }
  final next = project.copyWith(
    lanes: [
      for (final lane in project.lanes)
        lane.copyWith(
          clips: [
            for (final other in lane.clips)
              if (other.linkGroupId == group)
                rebuildEditorClip(other, clearLinkGroup: true)
              else
                other,
          ],
        ),
    ],
  );
  validateEditorProject(next, limits: limits);
  return next;
}

List<EditorSelection> _sliceTargets(EditorProject project, MediaTime at) {
  final lockedGroups = <String>{
    for (final lane in project.lanes)
      if (lane.locked)
        for (final clip in lane.clips) ?clip.linkGroupId,
  };
  return [
    for (final lane in project.lanes)
      if (!lane.locked)
        for (final clip in lane.clips)
          if (canSplitEditorClip(clip, at) &&
              !lockedGroups.contains(clip.linkGroupId))
            EditorSelection(laneId: lane.id, clipId: clip.id),
  ];
}

bool _crosses(EditorClip clip, MediaTime from, MediaTime to) =>
    clip.timelineStart < to && clip.timelineEnd > from;

bool _lockedLaneWouldChange(
  EditorLane lane,
  MediaTime from,
  MediaTime to,
  bool ripple,
  Set<String> splitLinkGroups,
) =>
    lane.locked &&
    lane.clips.any(
      (clip) =>
          (ripple ? clip.timelineEnd > from : _crosses(clip, from, to)) ||
          (clip.timelineStart >= to &&
              splitLinkGroups.contains(clip.linkGroupId)),
    );

Set<String> _splitLinkGroups(
  EditorProject project,
  MediaTime from,
  MediaTime to,
) => {
  for (final clip in project.clips)
    if (clip.linkGroupId case final group?
        when clip.timelineStart < from && clip.timelineEnd > to)
      group,
};

Iterable<EditorClip> _remainderOf(
  EditorClip clip,
  MediaTime from,
  MediaTime to,
  MediaTime span,
  bool ripple,
  Set<String> splitLinkGroups,
  _SpanRemainderIds ids,
) sync* {
  final shift = ripple ? span.microseconds : 0;
  if (clip.timelineEnd <= from) {
    yield clip;
    return;
  }
  if (clip.timelineStart >= to) {
    final originalGroup = clip.linkGroupId;
    final shiftedGroup =
        originalGroup != null && splitLinkGroups.contains(originalGroup)
        ? ids.linkGroupId(originalGroup)
        : originalGroup;
    if (!ripple && shiftedGroup == originalGroup) {
      yield clip;
      return;
    }
    yield rebuildEditorClip(
      clip,
      linkGroupId: shiftedGroup,
      timelineStart: MediaTime.microseconds(
        clip.timelineStart.microseconds - shift,
      ),
    );
    return;
  }
  final head = clip.timelineStart < from;
  final tail = clip.timelineEnd > to;
  if (head) {
    yield rebuildEditorClip(clip, duration: from - clip.timelineStart);
  }
  if (!tail) return;
  final into = to - clip.timelineStart;
  final originalGroup = clip.linkGroupId;
  final tailGroup =
      originalGroup != null && splitLinkGroups.contains(originalGroup)
      ? ids.linkGroupId(originalGroup)
      : originalGroup;
  yield rebuildEditorClip(
    clip,
    id: head ? ids.clipId(clip.id) : clip.id,
    linkGroupId: tailGroup,
    timelineStart: MediaTime.microseconds((ripple ? from : to).microseconds),
    duration: clip.timelineEnd - to,
    sourceStart: MediaTime.microseconds(
      _sourceStartOf(clip).microseconds + into.microseconds,
    ),
    dropTransition: head,
  );
}

final class _SpanRemainderIds {
  _SpanRemainderIds(EditorProject project, this.at)
    : _clipIds = project.clips.map((clip) => clip.id).toSet(),
      _groupIds = project.clips
          .map((clip) => clip.linkGroupId)
          .whereType<String>()
          .toSet();

  final MediaTime at;
  final Set<String> _clipIds;
  final Set<String> _groupIds;
  final Map<String, String> _tailGroups = {};

  String clipId(String original) => _freeId(_clipIds, original, at);

  String linkGroupId(String original) =>
      _tailGroups.putIfAbsent(original, () => _freeId(_groupIds, original, at));
}

String _freeId(Set<String> taken, String original, MediaTime from) {
  final prefix = original.length <= 80 ? original : original.substring(0, 80);
  final base = '$prefix.x${from.microseconds}';
  if (taken.add(base)) return base;
  for (var suffix = 2; suffix <= 999; suffix++) {
    if (taken.add('$base-$suffix')) return '$base-$suffix';
  }
  throw const EditorValidationException(
    'Unable to name the remainder of this clip.',
  );
}

MediaTime _sourceStartOf(EditorClip clip) => switch (clip) {
  EditorVideoClip() => clip.sourceRange.start,
  EditorAudioClip() => clip.sourceRange.start,
  EditorCaptionClip() => MediaTime.zero,
};

EditorClip? _clipOf(EditorProject project, EditorSelection? selection) {
  if (selection == null) return null;
  final lane = project.laneById(selection.laneId);
  if (lane == null) return null;
  for (final clip in lane.clips) {
    if (clip.id == selection.clipId) return clip;
  }
  return null;
}

/// A copy of [clip] with only the named parts changed.
EditorClip rebuildEditorClip(
  EditorClip clip, {
  String? id,
  MediaTime? timelineStart,
  MediaTime? duration,
  MediaTime? sourceStart,
  String? linkGroupId,
  bool clearLinkGroup = false,
  bool dropTransition = false,
}) {
  final nextId = id ?? clip.id;
  final nextStart = timelineStart ?? clip.timelineStart;
  final nextDuration = duration ?? clip.duration;
  final nextGroup = clearLinkGroup ? null : linkGroupId ?? clip.linkGroupId;
  return switch (clip) {
    EditorVideoClip() => EditorVideoClip(
      id: nextId,
      linkGroupId: nextGroup,
      timelineStart: nextStart,
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
      transition: dropTransition ? null : clip.transition,
    ),
    EditorAudioClip() => EditorAudioClip(
      id: nextId,
      linkGroupId: nextGroup,
      timelineStart: nextStart,
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
      id: nextId,
      linkGroupId: nextGroup,
      timelineStart: nextStart,
      duration: nextDuration,
      text: clip.text,
      destination: clip.destination,
      style: clip.style,
    ),
  };
}
