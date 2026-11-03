import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'editor_timeline_migrations.dart';

export 'editor_timeline_migrations.dart' show editorTimelineVersion;

/// A stored timeline that cannot be turned back into an editable project.
final class EditorTimelineDecodeFailure implements Exception {
  const EditorTimelineDecodeFailure(
    this.message, {
    this.missingMediaIds = const [],
    this.schemaFailureKind,
  });

  final String message;

  /// Media the timeline refers to that the workspace could not supply.
  final List<String> missingMediaIds;

  /// Storage compatibility failures retain their machine-readable cause.
  final EditorTimelineSchemaFailureKind? schemaFailureKind;

  @override
  String toString() => 'EditorTimelineDecodeFailure: $message';
}

Map<String, Object?> encodeEditorTimeline(EditorProject project) => {
  'version': editorTimelineVersion,
  'id': project.id,
  'width': project.width,
  'height': project.height,
  'framesPerSecond': project.framesPerSecond,
  'durationMicros': project.duration.microseconds,
  'backgroundColor': project.backgroundColor,
  'output': _encodeOutput(project.output),
  'lanes': [for (final lane in project.lanes) _encodeLane(lane)],
};

/// Every media id the stored [timeline] needs before it can be opened.
List<String> editorTimelineMediaIds(Map<String, Object?> timeline) {
  final ids = <String>{};
  for (final lane in _list(timeline['lanes'])) {
    for (final clip in _list(_map(lane)['clips'])) {
      final mediaId = _map(clip)['mediaId'];
      if (mediaId is String && mediaId.isNotEmpty) ids.add(mediaId);
    }
  }
  return ids.toList(growable: false);
}

EditorProject decodeEditorTimeline(
  Map<String, Object?> timeline, {
  required Map<String, MediaSource> sources,
}) {
  late final Map<String, Object?> current;
  try {
    current = prepareEditorTimeline(timeline).timeline;
  } on EditorTimelineSchemaFailure catch (failure) {
    throw EditorTimelineDecodeFailure(
      failure.message,
      schemaFailureKind: failure.kind,
    );
  }
  final missing = [
    for (final id in editorTimelineMediaIds(current))
      if (!sources.containsKey(id)) id,
  ];
  if (missing.isNotEmpty) {
    throw EditorTimelineDecodeFailure(
      'Some of this project\u2019s media is no longer in the workspace.',
      missingMediaIds: missing,
    );
  }
  try {
    final project = EditorProject(
      id: _string(current['id']),
      width: _int(current['width']),
      height: _int(current['height']),
      framesPerSecond: _int(current['framesPerSecond']),
      duration: _time(current['durationMicros']),
      backgroundColor: _string(current['backgroundColor']),
      output: _decodeOutput(_map(current['output'])),
      lanes: [
        for (final lane in _list(current['lanes']))
          _decodeLane(_map(lane), sources),
      ],
    );
    validateEditorProject(project, limits: const EditorLimits());
    return project;
  } on EditorTimelineDecodeFailure {
    rethrow;
  } on EditorValidationException catch (error) {
    throw EditorTimelineDecodeFailure(error.message);
  } on Object {
    throw const EditorTimelineDecodeFailure(
      'This project could not be opened because its timeline is damaged.',
    );
  }
}

/// Validates current timeline semantics using inert sources and no byte reads.
void validateEditorTimelineWithoutMedia(Map<String, Object?> timeline) {
  try {
    final prepared = prepareEditorTimeline(timeline);
    final sources = {
      for (final id in prepared.mediaIds)
        id: MediaSource(
          id: id,
          byteLength: 1,
          fileExtension: 'mp4',
          openRead: () => Stream<List<int>>.value(const [0]),
        ),
    };
    decodeEditorTimeline(prepared.timeline, sources: sources);
  } on EditorTimelineSchemaFailure {
    rethrow;
  } on EditorTimelineDecodeFailure {
    rethrow;
  } on Object {
    throw const EditorTimelineDecodeFailure(
      'This project cannot be opened because its timeline is invalid.',
    );
  }
}

Map<String, Object?> _encodeOutput(MediaOutputSettings output) => {
  'container': output.container.name,
  'videoCodec': output.videoCodec.name,
  'audioCodec': output.audioCodec.name,
  'videoBitrate': output.videoBitrate,
  'audioBitrate': output.audioBitrate,
};

MediaOutputSettings _decodeOutput(Map<String, Object?> value) =>
    MediaOutputSettings(
      container: _enumOf(MediaContainer.values, value['container']),
      videoCodec: _enumOf(MediaVideoCodec.values, value['videoCodec']),
      audioCodec: _enumOf(MediaAudioCodec.values, value['audioCodec']),
      videoBitrate: _int(value['videoBitrate']),
      audioBitrate: _int(value['audioBitrate']),
    );

Map<String, Object?> _encodeLane(EditorLane lane) => {
  'id': lane.id,
  'label': lane.label,
  'kind': lane.kind.name,
  'muted': lane.muted,
  'hidden': lane.hidden,
  'locked': lane.locked,
  'clips': [for (final clip in lane.clips) _encodeClip(clip)],
};

EditorLane _decodeLane(
  Map<String, Object?> value,
  Map<String, MediaSource> sources,
) => EditorLane(
  id: _string(value['id']),
  label: _string(value['label']),
  kind: _enumOf(EditorLaneKind.values, value['kind']),
  muted: value['muted'] == true,
  hidden: value['hidden'] == true,
  locked: value['locked'] == true,
  clips: [
    for (final clip in _list(value['clips'])) _decodeClip(_map(clip), sources),
  ],
);

Map<String, Object?> _encodeClip(EditorClip clip) => switch (clip) {
  EditorVideoClip() => {
    ..._encodeCommon(clip, 'video'),
    'mediaId': clip.source.id,
    'sourceStartMicros': clip.sourceRange.start.microseconds,
    'sourceDurationMicros': clip.sourceDuration.microseconds,
    'destination': _encodeRect(clip.destination),
    'fit': clip.fit.name,
    'opacity': clip.opacity,
    if (clip.transition case final transition?)
      'transition': {
        'kind': transition.kind.name,
        'durationMicros': transition.duration.microseconds,
        'color': transition.color,
      },
  },
  EditorAudioClip() => {
    ..._encodeCommon(clip, 'audio'),
    'mediaId': clip.source.id,
    'sourceStartMicros': clip.sourceRange.start.microseconds,
    'sourceDurationMicros': clip.sourceDuration.microseconds,
    'volume': clip.volume,
  },
  EditorCaptionClip() => {
    ..._encodeCommon(clip, 'caption'),
    'text': clip.text,
    'destination': _encodeRect(clip.destination),
    'style': _encodeStyle(clip.style),
  },
};

Map<String, Object?> _encodeCommon(EditorClip clip, String kind) => {
  'id': clip.id,
  'kind': kind,
  'linkGroupId': clip.linkGroupId,
  'startMicros': clip.timelineStart.microseconds,
  'durationMicros': clip.duration.microseconds,
};

EditorClip _decodeClip(
  Map<String, Object?> value,
  Map<String, MediaSource> sources,
) {
  final id = _string(value['id']);
  final linkGroupId = value['linkGroupId'] is String
      ? value['linkGroupId']! as String
      : null;
  final start = _time(value['startMicros']);
  final duration = _time(value['durationMicros']);
  switch (_string(value['kind'])) {
    case 'video':
      return EditorVideoClip(
        id: id,
        linkGroupId: linkGroupId,
        timelineStart: start,
        duration: duration,
        source: sources[_string(value['mediaId'])]!,
        sourceRange: MediaRange(
          start: _time(value['sourceStartMicros']),
          duration: duration,
        ),
        sourceDuration: _time(value['sourceDurationMicros']),
        destination: _decodeRect(_map(value['destination'])),
        fit: _enumOf(MediaFit.values, value['fit']),
        opacity: _double(value['opacity']),
        transition: value['transition'] == null
            ? null
            : _decodeTransition(_map(value['transition'])),
      );
    case 'audio':
      return EditorAudioClip(
        id: id,
        linkGroupId: linkGroupId,
        timelineStart: start,
        duration: duration,
        source: sources[_string(value['mediaId'])]!,
        sourceRange: MediaRange(
          start: _time(value['sourceStartMicros']),
          duration: duration,
        ),
        sourceDuration: _time(value['sourceDurationMicros']),
        volume: _double(value['volume']),
      );
    case 'caption':
      return EditorCaptionClip(
        id: id,
        linkGroupId: linkGroupId,
        timelineStart: start,
        duration: duration,
        text: _string(value['text']),
        destination: _decodeRect(_map(value['destination'])),
        style: _decodeStyle(_map(value['style'])),
      );
    default:
      throw const EditorTimelineDecodeFailure(
        'This project holds a kind of clip this build does not know.',
      );
  }
}

EditorTransition _decodeTransition(Map<String, Object?> value) =>
    EditorTransition(
      kind: _enumOf(EditorTransitionKind.values, value['kind']),
      duration: _time(value['durationMicros']),
      color: _string(value['color']),
    );

Map<String, Object?> _encodeRect(MediaRect rect) => {
  'x': rect.x,
  'y': rect.y,
  'width': rect.width,
  'height': rect.height,
};

MediaRect _decodeRect(Map<String, Object?> value) => MediaRect(
  x: _double(value['x']),
  y: _double(value['y']),
  width: _double(value['width']),
  height: _double(value['height']),
);

Map<String, Object?> _encodeStyle(EditorCaptionStyle style) => {
  'fontSize': style.fontSize,
  'fontWeight': style.fontWeight,
  'textColor': style.textColor,
  'backgroundColor': style.backgroundColor,
  'horizontalPadding': style.horizontalPadding,
  'verticalPadding': style.verticalPadding,
  'cornerRadius': style.cornerRadius,
  'maxLines': style.maxLines,
  'textAlign': style.textAlign.name,
  'fontFamily': style.fontFamily,
};

EditorCaptionStyle _decodeStyle(Map<String, Object?> value) =>
    EditorCaptionStyle(
      fontSize: _double(value['fontSize']),
      fontWeight: _int(value['fontWeight']),
      textColor: _int(value['textColor']),
      backgroundColor: _int(value['backgroundColor']),
      horizontalPadding: _double(value['horizontalPadding']),
      verticalPadding: _double(value['verticalPadding']),
      cornerRadius: _double(value['cornerRadius']),
      maxLines: _int(value['maxLines']),
      textAlign: _enumOf(EditorTextAlign.values, value['textAlign']),
      fontFamily: value['fontFamily'] is String
          ? value['fontFamily']! as String
          : null,
    );

T _enumOf<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw EditorTimelineDecodeFailure('Unknown stored value: $name.');
}

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry('$key', item))
    : throw const EditorTimelineDecodeFailure(
        'This project could not be opened because its timeline is damaged.',
      );

List<Object?> _list(Object? value) => value is List ? value : const [];

String _string(Object? value) => value is String
    ? value
    : throw const EditorTimelineDecodeFailure(
        'This project could not be opened because its timeline is damaged.',
      );

int _int(Object? value) => value is num
    ? value.toInt()
    : throw const EditorTimelineDecodeFailure(
        'This project could not be opened because its timeline is damaged.',
      );

double _double(Object? value) => value is num
    ? value.toDouble()
    : throw const EditorTimelineDecodeFailure(
        'This project could not be opened because its timeline is damaged.',
      );

MediaTime _time(Object? value) => MediaTime.microseconds(_int(value));
