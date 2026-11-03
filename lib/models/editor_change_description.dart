import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

const _transitionNames = <EditorTransitionKind, String>{
  EditorTransitionKind.dissolve: 'cross dissolve',
  EditorTransitionKind.dipToColor: 'dip to colour',
  EditorTransitionKind.slideFromLeft: 'slide from the left',
  EditorTransitionKind.slideFromRight: 'slide from the right',
  EditorTransitionKind.slideFromTop: 'slide from the top',
  EditorTransitionKind.slideFromBottom: 'slide from the bottom',
};

/// One short sentence naming what changed between two versions of a timeline,
/// written for the person who made the change rather than for a log.
///
/// The editor reports a new timeline, not what was done to it, so this reads
/// the difference. It stays deliberately general where the difference is
/// ambiguous: a wrong specific sentence in a project's history is worse than a
/// true vague one.
String describeEditorChange(EditorProject before, EditorProject after) {
  final detached = _detached(before, after);
  if (detached != null) return detached;
  final transition = _transitionChange(before, after);
  if (transition != null) return transition;
  final caption = _captionAddition(before, after);
  if (caption != null) return caption;
  final lane = _laneChange(before, after);
  if (lane != null) return lane;
  if (after.duration < before.duration) {
    final removed =
        (before.duration.microseconds - after.duration.microseconds) /
        Duration.microsecondsPerSecond;
    return 'Removed ${removed.toStringAsFixed(1)} seconds from the timeline';
  }
  final clipChange = _clipCountChange(before, after);
  if (clipChange != null) return clipChange;
  final timing = _timingChange(before, after);
  if (timing != null) return timing;
  if (after.output.videoBitrate != before.output.videoBitrate) {
    final mbps = after.output.videoBitrate / 1000000;
    return 'Set the export to ${mbps.toStringAsFixed(1)} Mbps';
  }
  return 'Edited the timeline';
}

String? _captionAddition(EditorProject before, EditorProject after) {
  final beforeIds = {for (final clip in before.clips) clip.id};
  final addedCaption = after.clips.any(
    (clip) => clip is EditorCaptionClip && !beforeIds.contains(clip.id),
  );
  if (!addedCaption) return null;
  final preservesEveryExistingClip = before.clips.every(
    (clip) => identical(after.clipById(clip.id), clip),
  );
  return preservesEveryExistingClip ? 'Added a caption' : null;
}

String? _detached(EditorProject before, EditorProject after) {
  for (final clip in before.clips) {
    if (clip.linkGroupId == null) continue;
    final now = after.clipById(clip.id);
    if (now != null && now.linkGroupId == null) {
      return 'Separated a picture from its sound';
    }
  }
  return null;
}

String? _transitionChange(EditorProject before, EditorProject after) {
  final was = _transitions(before);
  final now = _transitions(after);
  for (final entry in now.entries) {
    final previous = was[entry.key];
    if (previous == null) {
      return 'Added a ${_transitionNames[entry.value.kind]}';
    }
    if (previous.kind != entry.value.kind) {
      return 'Changed a transition to a ${_transitionNames[entry.value.kind]}';
    }
    if (previous.duration != entry.value.duration) {
      final seconds =
          entry.value.duration.microseconds / Duration.microsecondsPerSecond;
      return 'Made a transition ${seconds.toStringAsFixed(2)} seconds long';
    }
  }
  for (final id in was.keys) {
    if (!now.containsKey(id) && after.clipById(id) != null) {
      return 'Removed a transition';
    }
  }
  return null;
}

Map<String, EditorTransition> _transitions(EditorProject project) => {
  for (final clip in project.clips.whereType<EditorVideoClip>())
    clip.id: ?clip.transition,
};

String? _laneChange(EditorProject before, EditorProject after) {
  final was = {for (final lane in before.lanes) lane.id};
  final added = after.lanes.where((lane) => !was.contains(lane.id)).toList();
  if (added.isNotEmpty) {
    if (added.every((lane) => lane.kind == EditorLaneKind.captions)) {
      return 'Added a caption';
    }
    final named = added.firstWhere(
      (lane) => lane.kind == EditorLaneKind.video,
      orElse: () => added.first,
    );
    return 'Added ${named.label}';
  }
  final now = {for (final lane in after.lanes) lane.id};
  if (before.lanes.any((lane) => !now.contains(lane.id))) {
    return 'Removed a lane';
  }
  return null;
}

String? _clipCountChange(EditorProject before, EditorProject after) {
  var cutLanes = 0;
  var lostClips = 0;
  for (final lane in after.lanes) {
    final was = before.laneById(lane.id);
    if (was == null) continue;
    if (lane.clips.length > was.clips.length) cutLanes++;
    if (lane.clips.length < was.clips.length) {
      lostClips += was.clips.length - lane.clips.length;
    }
  }
  if (cutLanes > 1) return 'Cut $cutLanes lanes';
  if (cutLanes == 1) return 'Cut a clip';
  if (lostClips > 0) {
    return lostClips == 1 ? 'Removed a clip' : 'Removed $lostClips clips';
  }
  return null;
}

String? _timingChange(EditorProject before, EditorProject after) {
  for (final clip in after.clips) {
    final was = before.clipById(clip.id);
    if (was == null) continue;
    if (was.duration != clip.duration) return 'Trimmed a clip';
    if (was.timelineStart != clip.timelineStart) return 'Moved a clip';
  }
  for (final lane in after.lanes) {
    final was = before.laneById(lane.id);
    if (was == null) continue;
    if (was.muted != lane.muted) {
      return lane.muted ? 'Silenced a lane' : 'Turned a lane back on';
    }
    if (was.hidden != lane.hidden) {
      return lane.hidden ? 'Hid a lane' : 'Showed a lane again';
    }
    if (was.locked != lane.locked) {
      return lane.locked ? 'Locked a lane' : 'Unlocked a lane';
    }
  }
  return null;
}
