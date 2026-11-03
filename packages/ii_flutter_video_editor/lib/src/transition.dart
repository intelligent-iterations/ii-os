import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:meta/meta.dart';

/// The longest a single transition may run, whatever the clips around it.
const editorMaxTransitionDuration = Duration(seconds: 5);

/// How one picture gives way to the next at a cut.
enum EditorTransitionKind {
  /// The two pictures overlap; the arriving one rises through the leaving one.
  dissolve,

  /// The picture passes through a flat colour and comes back out of it.
  dipToColor,

  /// The arriving picture travels in from the left edge.
  slideFromLeft,

  /// The arriving picture travels in from the right edge.
  slideFromRight,

  /// The arriving picture travels down from the top edge.
  slideFromTop,

  /// The arriving picture travels up from the bottom edge.
  slideFromBottom,
}

/// A transition belongs to the clip it brings on screen, and runs across that
/// clip's opening. A clip with nothing adjacent before it opens from the
/// project background, or from [color] for [EditorTransitionKind.dipToColor].
@immutable
final class EditorTransition {
  const EditorTransition({
    required this.kind,
    required this.duration,
    this.color = '000000',
  });

  final EditorTransitionKind kind;
  final MediaTime duration;
  final String color;

  /// Whether the leaving picture has to stay on screen underneath this one.
  bool get needsOutgoingHold => kind != EditorTransitionKind.dipToColor;

  EditorTransition copyWith({
    EditorTransitionKind? kind,
    MediaTime? duration,
    String? color,
  }) => EditorTransition(
    kind: kind ?? this.kind,
    duration: duration ?? this.duration,
    color: color ?? this.color,
  );

  @override
  bool operator ==(Object other) =>
      other is EditorTransition &&
      other.kind == kind &&
      other.duration == duration &&
      other.color == color;

  @override
  int get hashCode => Object.hash(kind, duration, color);
}
