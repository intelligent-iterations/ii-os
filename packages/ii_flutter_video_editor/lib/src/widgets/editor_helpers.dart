import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';

void validateEditorControlledState({
  required EditorProject project,
  required MediaTime playhead,
  required EditorSelection? selection,
  required EditorLimits limits,
  required double initialPixelsPerSecond,
  required double minPixelsPerSecond,
  required double maxPixelsPerSecond,
}) {
  if (!minPixelsPerSecond.isFinite ||
      !maxPixelsPerSecond.isFinite ||
      !initialPixelsPerSecond.isFinite ||
      initialPixelsPerSecond <= 0 ||
      minPixelsPerSecond <= 0 ||
      maxPixelsPerSecond < minPixelsPerSecond) {
    throw const EditorValidationException('Timeline zoom bounds are invalid.');
  }
  validateEditorProject(project, limits: limits);
  if (playhead > project.duration) {
    throw const EditorValidationException(
      'Playhead extends past the project duration.',
    );
  }
  if (selection != null) {
    final lane = project.laneById(selection.laneId);
    if (lane == null ||
        !lane.clips.any((clip) => clip.id == selection.clipId)) {
      throw const EditorValidationException(
        'Selection must reference a clip in its declared lane.',
      );
    }
  }
}

void validateEditorTheme(EditorThemeData theme) {
  final positive = <double>[
    theme.laneHeight,
    theme.rulerHeight,
    theme.headerWidth,
  ];
  if (positive.any((value) => !value.isFinite || value <= 0) ||
      !theme.clipRadius.isFinite ||
      theme.clipRadius < 0) {
    throw const EditorValidationException(
      'Editor theme geometry must be finite and non-negative.',
    );
  }
}

String formatEditorTime(MediaTime value) {
  final totalMilliseconds = value.microseconds ~/ 1000;
  final minutes = totalMilliseconds ~/ 60000;
  final seconds = (totalMilliseconds ~/ 1000) % 60;
  final milliseconds = totalMilliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${milliseconds.toString().padLeft(3, '0')}';
}
