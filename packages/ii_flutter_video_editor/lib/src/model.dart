import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';
import 'package:meta/meta.dart';

enum EditorLaneKind { video, audio, captions }

enum EditorTextAlign { left, center, right }

@immutable
final class EditorCaptionStyle {
  const EditorCaptionStyle({
    this.fontSize = 48,
    this.fontWeight = 600,
    this.textColor = 0xffffffff,
    this.backgroundColor = 0x99000000,
    this.horizontalPadding = 24,
    this.verticalPadding = 12,
    this.cornerRadius = 12,
    this.maxLines = 3,
    this.textAlign = EditorTextAlign.center,
    this.fontFamily,
  });

  final double fontSize;
  final int fontWeight;
  final int textColor;
  final int backgroundColor;
  final double horizontalPadding;
  final double verticalPadding;
  final double cornerRadius;
  final int maxLines;
  final EditorTextAlign textAlign;
  final String? fontFamily;
}

@immutable
sealed class EditorClip {
  const EditorClip({
    required this.id,
    required this.timelineStart,
    required this.duration,
    this.linkGroupId,
  });

  final String id;
  final MediaTime timelineStart;
  final MediaTime duration;
  final String? linkGroupId;

  MediaTime get timelineEnd => timelineStart + duration;

  bool contains(MediaTime position) =>
      position >= timelineStart && position < timelineEnd;
}

@immutable
final class EditorVideoClip extends EditorClip {
  EditorVideoClip({
    required super.id,
    required super.timelineStart,
    required super.duration,
    super.linkGroupId,
    required this.source,
    required this.sourceRange,
    MediaTime? sourceDuration,
    this.destination = const MediaRect.full(),
    this.fit = MediaFit.contain,
    this.opacity = 1,
    this.transition,
  }) : sourceDuration = sourceDuration ?? sourceRange.end;

  final MediaSource source;
  final MediaRange sourceRange;
  final MediaTime sourceDuration;
  final MediaRect destination;
  final MediaFit fit;
  final double opacity;

  /// How this clip arrives on screen, if it does anything but appear.
  final EditorTransition? transition;
}

@immutable
final class EditorAudioClip extends EditorClip {
  EditorAudioClip({
    required super.id,
    required super.timelineStart,
    required super.duration,
    super.linkGroupId,
    required this.source,
    required this.sourceRange,
    MediaTime? sourceDuration,
    this.volume = 1,
  }) : sourceDuration = sourceDuration ?? sourceRange.end;

  final MediaSource source;
  final MediaRange sourceRange;
  final MediaTime sourceDuration;
  final double volume;
}

@immutable
final class EditorCaptionClip extends EditorClip {
  const EditorCaptionClip({
    required super.id,
    required super.timelineStart,
    required super.duration,
    super.linkGroupId,
    required this.text,
    this.destination = const MediaRect(
      x: 0.1,
      y: 0.72,
      width: 0.8,
      height: 0.2,
    ),
    this.style = const EditorCaptionStyle(),
  });

  final String text;
  final MediaRect destination;
  final EditorCaptionStyle style;
}

@immutable
final class EditorLane {
  EditorLane({
    required this.id,
    required this.label,
    required this.kind,
    required Iterable<EditorClip> clips,
    this.muted = false,
    this.hidden = false,
    this.locked = false,
  }) : clips = List<EditorClip>.unmodifiable(clips);

  final String id;
  final String label;
  final EditorLaneKind kind;
  final List<EditorClip> clips;
  final bool muted;
  final bool hidden;
  final bool locked;

  EditorLane copyWith({
    String? label,
    Iterable<EditorClip>? clips,
    bool? muted,
    bool? hidden,
    bool? locked,
  }) => EditorLane(
    id: id,
    label: label ?? this.label,
    kind: kind,
    clips: clips ?? this.clips,
    muted: muted ?? this.muted,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
  );
}

@immutable
final class EditorProject {
  EditorProject({
    required this.id,
    required this.width,
    required this.height,
    required this.framesPerSecond,
    required this.duration,
    required Iterable<EditorLane> lanes,
    this.output = const MediaOutputSettings(),
    this.backgroundColor = '000000',
  }) : lanes = List<EditorLane>.unmodifiable(lanes);

  final String id;
  final int width;
  final int height;
  final int framesPerSecond;
  final MediaTime duration;
  final List<EditorLane> lanes;
  final MediaOutputSettings output;
  final String backgroundColor;

  Iterable<EditorClip> get clips => lanes.expand((lane) => lane.clips);

  EditorLane? laneById(String id) {
    for (final lane in lanes) {
      if (lane.id == id) return lane;
    }
    return null;
  }

  EditorClip? clipById(String id) {
    for (final clip in clips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  EditorProject copyWith({
    Iterable<EditorLane>? lanes,
    MediaTime? duration,
    MediaOutputSettings? output,
    String? backgroundColor,
  }) => EditorProject(
    id: id,
    width: width,
    height: height,
    framesPerSecond: framesPerSecond,
    duration: duration ?? this.duration,
    lanes: lanes ?? this.lanes,
    output: output ?? this.output,
    backgroundColor: backgroundColor ?? this.backgroundColor,
  );
}
