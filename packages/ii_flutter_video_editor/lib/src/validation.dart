import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';

final class EditorValidationException implements Exception {
  const EditorValidationException(this.message);

  final String message;

  @override
  String toString() => 'EditorValidationException: $message';
}

const _hardMaxLanes = 24;
const _hardMaxClips = 256;
const _hardMaxCaptionCharacters = 4000;
const _hardMaxCaptionRasterBytes = 16 * 1024 * 1024;
const _hardMaxCaptionPixels = 16 * 1024 * 1024;
const _hardMaxCaptionTotalRasterBytes = 64 * 1024 * 1024;
const _hardMaxCaptionTotalPixels = 64 * 1024 * 1024;

final class EditorLimits {
  const EditorLimits({
    this.maxLanes = 24,
    this.maxClips = 256,
    this.maxDuration = const Duration(minutes: 30),
    this.maxDimension = 4096,
    this.maxCanvasPixels = 4096 * 4096,
    this.maxCaptionCharacters = 4000,
    this.maxCaptionRasterBytes = 16 * 1024 * 1024,
    this.maxCaptionPixels = 16 * 1024 * 1024,
    this.maxCaptionTotalRasterBytes = 64 * 1024 * 1024,
    this.maxCaptionTotalPixels = 64 * 1024 * 1024,
    this.captionRasterTimeout = const Duration(seconds: 15),
  });

  final int maxLanes;
  final int maxClips;
  final Duration maxDuration;
  final int maxDimension;
  final int maxCanvasPixels;
  final int maxCaptionCharacters;
  final int maxCaptionRasterBytes;
  final int maxCaptionPixels;
  final int maxCaptionTotalRasterBytes;
  final int maxCaptionTotalPixels;
  final Duration captionRasterTimeout;

  void validateSelf() {
    if (maxLanes <= 0 ||
        maxLanes > _hardMaxLanes ||
        maxClips <= 0 ||
        maxClips > _hardMaxClips ||
        maxDuration <= Duration.zero ||
        maxDuration > const Duration(hours: 2) ||
        maxDimension <= 0 ||
        maxDimension > 8192 ||
        maxCanvasPixels <= 0 ||
        maxCanvasPixels > 8192 * 8192 ||
        maxCaptionCharacters <= 0 ||
        maxCaptionCharacters > _hardMaxCaptionCharacters ||
        maxCaptionRasterBytes <= 0 ||
        maxCaptionRasterBytes > _hardMaxCaptionRasterBytes ||
        maxCaptionPixels <= 0 ||
        maxCaptionPixels > _hardMaxCaptionPixels ||
        maxCaptionTotalRasterBytes <= 0 ||
        maxCaptionTotalRasterBytes > _hardMaxCaptionTotalRasterBytes ||
        maxCaptionTotalPixels <= 0 ||
        maxCaptionTotalPixels > _hardMaxCaptionTotalPixels ||
        captionRasterTimeout <= Duration.zero ||
        captionRasterTimeout > const Duration(minutes: 2) ||
        maxCaptionRasterBytes > maxCaptionTotalRasterBytes ||
        maxCaptionPixels > maxCaptionTotalPixels) {
      throw const EditorValidationException(
        'Editor limits are inconsistent or outside their hard safety bounds.',
      );
    }
  }
}

final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final RegExp _forbiddenText = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

void validateEditorProject(
  EditorProject project, {
  EditorLimits limits = const EditorLimits(),
}) {
  limits.validateSelf();
  _requireSafeId(project.id, 'Project');
  if (project.width <= 0 ||
      project.height <= 0 ||
      project.width > limits.maxDimension ||
      project.height > limits.maxDimension ||
      project.width * project.height > limits.maxCanvasPixels) {
    throw const EditorValidationException(
      'Project dimensions are out of bounds.',
    );
  }
  if (project.width.isOdd || project.height.isOdd) {
    throw const EditorValidationException(
      'Project dimensions must be even for yuv420p output.',
    );
  }
  if (project.framesPerSecond < 1 || project.framesPerSecond > 120) {
    throw const EditorValidationException(
      'Project frame rate must be between 1 and 120.',
    );
  }
  if (project.duration == MediaTime.zero ||
      project.duration.microseconds > limits.maxDuration.inMicroseconds) {
    throw const EditorValidationException('Project duration is out of bounds.');
  }
  if (project.lanes.length > limits.maxLanes) {
    throw const EditorValidationException('Project has too many lanes.');
  }
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(project.backgroundColor)) {
    throw const EditorValidationException(
      'Project background must be a six-digit hex color.',
    );
  }

  final laneIds = <String>{};
  final clipIds = <String>{};
  var clipCount = 0;
  for (final lane in project.lanes) {
    _requireSafeId(lane.id, 'Lane');
    if (!laneIds.add(lane.id)) {
      throw EditorValidationException('Lane ID is repeated: ${lane.id}.');
    }
    _validateLabel(lane.label, 'Lane ${lane.id} label');
    MediaTime? priorEnd;
    for (final clip in lane.clips) {
      clipCount++;
      if (clipCount > limits.maxClips) {
        throw const EditorValidationException('Project has too many clips.');
      }
      _requireSafeId(clip.id, 'Clip');
      if (clip.linkGroupId case final linkGroupId?) {
        _requireSafeId(linkGroupId, 'Clip link group');
      }
      if (!clipIds.add(clip.id)) {
        throw EditorValidationException('Clip ID is repeated: ${clip.id}.');
      }
      if (clip.duration == MediaTime.zero) {
        throw EditorValidationException(
          'Clip ${clip.id} duration must be positive.',
        );
      }
      if (clip.timelineEnd > project.duration) {
        throw EditorValidationException(
          'Clip ${clip.id} extends past the project duration.',
        );
      }
      if (priorEnd != null && clip.timelineStart < priorEnd) {
        throw EditorValidationException(
          'Lane ${lane.id} clips must be ordered and may not overlap.',
        );
      }
      priorEnd = clip.timelineEnd;
      _validateClip(lane, clip, project, limits);
    }
  }
}

void _validateClip(
  EditorLane lane,
  EditorClip clip,
  EditorProject project,
  EditorLimits limits,
) {
  switch (clip) {
    case EditorVideoClip():
      _requireLaneKind(lane, EditorLaneKind.video, clip.id);
      _requireMatchingDuration(clip.id, clip.duration, clip.sourceRange);
      _requireAvailableSource(clip.id, clip.sourceRange, clip.sourceDuration);
      _validateRect(clip.id, clip.destination, project);
      if (!clip.opacity.isFinite || clip.opacity < 0 || clip.opacity > 1) {
        throw EditorValidationException(
          'Video clip ${clip.id} opacity must be between 0 and 1.',
        );
      }
      _validateTransition(clip);
    case EditorAudioClip():
      _requireLaneKind(lane, EditorLaneKind.audio, clip.id);
      _requireMatchingDuration(clip.id, clip.duration, clip.sourceRange);
      _requireAvailableSource(clip.id, clip.sourceRange, clip.sourceDuration);
      if (!clip.volume.isFinite || clip.volume < 0 || clip.volume > 4) {
        throw EditorValidationException(
          'Audio clip ${clip.id} volume must be between 0 and 4.',
        );
      }
    case EditorCaptionClip():
      _requireLaneKind(lane, EditorLaneKind.captions, clip.id);
      _validateCaption(clip, project, limits);
  }
}

void _requireAvailableSource(
  String id,
  MediaRange range,
  MediaTime sourceDuration,
) {
  if (sourceDuration == MediaTime.zero || range.end > sourceDuration) {
    throw EditorValidationException(
      'Media clip $id source range exceeds its available duration.',
    );
  }
}

void _validateCaption(
  EditorCaptionClip clip,
  EditorProject project,
  EditorLimits limits,
) {
  if (clip.text.trim().isEmpty ||
      clip.text.length > limits.maxCaptionCharacters ||
      _forbiddenText.hasMatch(clip.text)) {
    throw EditorValidationException(
      'Caption ${clip.id} text is empty, oversized, or contains controls.',
    );
  }
  _validateRect(clip.id, clip.destination, project);
  final style = clip.style;
  final finite = <double>[
    style.fontSize,
    style.horizontalPadding,
    style.verticalPadding,
    style.cornerRadius,
  ].every((value) => value.isFinite);
  if (!finite ||
      style.fontSize < 4 ||
      style.fontSize > 512 ||
      style.fontWeight < 100 ||
      style.fontWeight > 900 ||
      style.fontWeight % 100 != 0 ||
      style.horizontalPadding < 0 ||
      style.verticalPadding < 0 ||
      style.cornerRadius < 0 ||
      style.maxLines < 1 ||
      style.maxLines > 20 ||
      !_validColor(style.textColor) ||
      !_validColor(style.backgroundColor)) {
    throw EditorValidationException('Caption ${clip.id} style is invalid.');
  }
  final family = style.fontFamily;
  if (family != null &&
      (family.trim().isEmpty ||
          family.length > 128 ||
          _forbiddenText.hasMatch(family))) {
    throw EditorValidationException(
      'Caption ${clip.id} font family is invalid.',
    );
  }
}

bool _validColor(int value) => value >= 0 && value <= 0xffffffff;

void _requireMatchingDuration(
  String id,
  MediaTime duration,
  MediaRange sourceRange,
) {
  if (sourceRange.duration != duration) {
    throw EditorValidationException(
      'Media clip $id source and timeline durations must match.',
    );
  }
}

void _requireLaneKind(EditorLane lane, EditorLaneKind expected, String clipId) {
  if (lane.kind != expected) {
    throw EditorValidationException(
      'Clip $clipId is incompatible with ${lane.kind.name} lane ${lane.id}.',
    );
  }
}

void _validateRect(String id, MediaRect rect, EditorProject project) {
  final values = <double>[rect.x, rect.y, rect.width, rect.height];
  if (values.any((value) => !value.isFinite) ||
      rect.x < 0 ||
      rect.y < 0 ||
      rect.width <= 0 ||
      rect.height <= 0 ||
      rect.x + rect.width > 1 ||
      rect.y + rect.height > 1 ||
      _pixelSpan(rect.x, rect.width, project.width) < 1 ||
      _pixelSpan(rect.y, rect.height, project.height) < 1) {
    throw EditorValidationException(
      'Visual clip $id destination must fit inside the project canvas.',
    );
  }
}

int _pixelSpan(double start, double length, int extent) =>
    ((start + length) * extent).round() - (start * extent).round();

void _requireSafeId(String id, String subject) {
  if (!_safeId.hasMatch(id)) {
    throw EditorValidationException('$subject ID is invalid: $id.');
  }
}

void _validateLabel(String value, String subject) {
  if (value.trim().isEmpty ||
      value.length > 80 ||
      _forbiddenText.hasMatch(value)) {
    throw EditorValidationException('$subject is invalid.');
  }
}

void _validateTransition(EditorVideoClip clip) {
  final transition = clip.transition;
  if (transition == null) return;
  if (transition.duration == MediaTime.zero ||
      transition.duration > clip.duration ||
      transition.duration.microseconds >
          editorMaxTransitionDuration.inMicroseconds) {
    throw EditorValidationException(
      'Clip ${clip.id} has a transition longer than the clip itself.',
    );
  }
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(transition.color)) {
    throw EditorValidationException(
      'Clip ${clip.id} has a transition colour that is not six hex digits.',
    );
  }
}
