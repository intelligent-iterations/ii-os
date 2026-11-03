/// Current durable video-editor timeline schema.
const editorTimelineVersion = 1;

/// Oldest schema this build promises to open.
const editorTimelineOldestSupportedVersion = 1;

/// Every released schema this build must keep a checked fixture for.
List<int> get editorTimelineSupportedVersions => List<int>.generate(
  editorTimelineVersion - editorTimelineOldestSupportedVersion + 1,
  (index) => editorTimelineOldestSupportedVersion + index,
  growable: false,
);

enum EditorTimelineSchemaFailureKind {
  malformed,
  unsupportedLegacy,
  newerBuildRequired,
}

/// A failure found before any saved media needs to be restored.
final class EditorTimelineSchemaFailure implements Exception {
  const EditorTimelineSchemaFailure(this.kind, this.message);

  const EditorTimelineSchemaFailure.malformed()
    : this(
        EditorTimelineSchemaFailureKind.malformed,
        'This project does not contain a supported timeline document.',
      );

  const EditorTimelineSchemaFailure.unsupportedLegacy()
    : this(
        EditorTimelineSchemaFailureKind.unsupportedLegacy,
        'This project uses an unsupported older timeline version.',
      );

  const EditorTimelineSchemaFailure.newerBuildRequired()
    : this(
        EditorTimelineSchemaFailureKind.newerBuildRequired,
        'This project was saved by a newer version of the editor.',
      );

  final EditorTimelineSchemaFailureKind kind;
  final String message;

  @override
  String toString() => 'EditorTimelineSchemaFailure: $message';
}

typedef EditorTimelineMigrationStep =
    Map<String, Object?> Function(Map<String, Object?> timeline);

/// One pure, prepared current-schema timeline.
final class PreparedEditorTimeline {
  const PreparedEditorTimeline({
    required this.timeline,
    required this.mediaIds,
    required this.sourceVersion,
  });

  final Map<String, Object?> timeline;
  final List<String> mediaIds;
  final int sourceVersion;

  bool get wasMigrated => sourceVersion != editorTimelineVersion;
}

const Map<int, EditorTimelineMigrationStep> _editorTimelineMigrations = {};

/// Proves a migration chain has one adjacent step for every supported gap.
void validateEditorTimelineMigrationRegistry({
  required int oldestVersion,
  required int currentVersion,
  required Map<int, EditorTimelineMigrationStep> steps,
}) {
  if (oldestVersion <= 0 || currentVersion < oldestVersion) {
    throw StateError('Timeline migration version bounds are invalid.');
  }
  final expected = <int>{
    for (var version = oldestVersion; version < currentVersion; version++)
      version,
  };
  if (steps.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(steps.keys.toSet()).isNotEmpty) {
    throw StateError('Timeline migrations must cover every adjacent version.');
  }
}

/// Deep-copies, migrates, and shape-checks a timeline without media effects.
///
/// Opening is decode-only: this function never writes back, marks a project
/// dirty, creates history, or changes the supplied map. Unknown v1 fields are
/// refused instead of being silently erased by a later canonical save.
PreparedEditorTimeline prepareEditorTimeline(Map<String, Object?> timeline) {
  validateEditorTimelineMigrationRegistry(
    oldestVersion: editorTimelineOldestSupportedVersion,
    currentVersion: editorTimelineVersion,
    steps: _editorTimelineMigrations,
  );
  var current = _copyMap(timeline);
  final version = current['version'];
  if (version is! int) {
    throw const EditorTimelineSchemaFailure.malformed();
  }
  if (version < editorTimelineOldestSupportedVersion) {
    throw const EditorTimelineSchemaFailure.unsupportedLegacy();
  }
  if (version > editorTimelineVersion) {
    throw const EditorTimelineSchemaFailure.newerBuildRequired();
  }
  final sourceVersion = version;
  for (var next = version; next < editorTimelineVersion; next++) {
    final step = _editorTimelineMigrations[next];
    if (step == null) {
      throw StateError('Timeline migration ${next + 1} is not registered.');
    }
    current = _copyMap(step(_copyMap(current)));
    if (current['version'] != next + 1) {
      throw StateError('A timeline migration did not advance one version.');
    }
  }
  _validateV1(current);
  return PreparedEditorTimeline(
    timeline: current,
    mediaIds: _mediaIds(current),
    sourceVersion: sourceVersion,
  );
}

void _validateV1(Map<String, Object?> timeline) {
  _keys(timeline, {
    'version',
    'id',
    'width',
    'height',
    'framesPerSecond',
    'durationMicros',
    'backgroundColor',
    'output',
    'lanes',
  });
  _integer(timeline['version']);
  _string(timeline['id']);
  _integer(timeline['width']);
  _integer(timeline['height']);
  _integer(timeline['framesPerSecond']);
  _integer(timeline['durationMicros']);
  _string(timeline['backgroundColor']);
  final output = _map(timeline['output']);
  _keys(output, {
    'container',
    'videoCodec',
    'audioCodec',
    'videoBitrate',
    'audioBitrate',
  });
  _oneOf(output['container'], {'mp4', 'webm', 'mov'});
  _oneOf(output['videoCodec'], {'h264', 'vp9', 'mpeg4', 'automatic'});
  _oneOf(output['audioCodec'], {'aac', 'opus', 'automatic'});
  _integer(output['videoBitrate']);
  _integer(output['audioBitrate']);
  for (final laneValue in _list(timeline['lanes'])) {
    final lane = _map(laneValue);
    _keys(lane, {'id', 'label', 'kind', 'muted', 'hidden', 'locked', 'clips'});
    _string(lane['id']);
    _string(lane['label']);
    final laneKind = _oneOf(lane['kind'], {'video', 'audio', 'captions'});
    _boolean(lane['muted']);
    _boolean(lane['hidden']);
    _boolean(lane['locked']);
    for (final clipValue in _list(lane['clips'])) {
      _validateClip(_map(clipValue), laneKind);
    }
  }
}

void _validateClip(Map<String, Object?> clip, String laneKind) {
  final kind = _oneOf(clip['kind'], {'video', 'audio', 'caption'});
  if ((kind == 'caption' ? 'captions' : kind) != laneKind) {
    throw const EditorTimelineSchemaFailure.malformed();
  }
  final common = {'id', 'kind', 'linkGroupId', 'startMicros', 'durationMicros'};
  final required = switch (kind) {
    'video' => {
      ...common,
      'mediaId',
      'sourceStartMicros',
      'sourceDurationMicros',
      'destination',
      'fit',
      'opacity',
    },
    'audio' => {
      ...common,
      'mediaId',
      'sourceStartMicros',
      'sourceDurationMicros',
      'volume',
    },
    _ => {...common, 'text', 'destination', 'style'},
  };
  _keys(clip, required, optional: kind == 'video' ? {'transition'} : const {});
  _string(clip['id']);
  if (clip['linkGroupId'] != null) _string(clip['linkGroupId']);
  _integer(clip['startMicros']);
  _integer(clip['durationMicros']);
  if (kind == 'caption') {
    _string(clip['text']);
    _validateRect(_map(clip['destination']));
    _validateStyle(_map(clip['style']));
    return;
  }
  _string(clip['mediaId']);
  _integer(clip['sourceStartMicros']);
  _integer(clip['sourceDurationMicros']);
  if (kind == 'audio') {
    _number(clip['volume']);
    return;
  }
  _validateRect(_map(clip['destination']));
  _oneOf(clip['fit'], {'fill', 'contain', 'cover'});
  _number(clip['opacity']);
  if (clip['transition'] case final transition?) {
    final value = _map(transition);
    _keys(value, {'kind', 'durationMicros', 'color'});
    _oneOf(value['kind'], {
      'dissolve',
      'dipToColor',
      'slideFromLeft',
      'slideFromRight',
      'slideFromTop',
      'slideFromBottom',
    });
    _integer(value['durationMicros']);
    _string(value['color']);
  }
}

void _validateRect(Map<String, Object?> value) {
  _keys(value, {'x', 'y', 'width', 'height'});
  for (final key in ['x', 'y', 'width', 'height']) {
    _number(value[key]);
  }
}

void _validateStyle(Map<String, Object?> value) {
  _keys(value, {
    'fontSize',
    'fontWeight',
    'textColor',
    'backgroundColor',
    'horizontalPadding',
    'verticalPadding',
    'cornerRadius',
    'maxLines',
    'textAlign',
    'fontFamily',
  });
  _number(value['fontSize']);
  _integer(value['fontWeight']);
  _integer(value['textColor']);
  _integer(value['backgroundColor']);
  _number(value['horizontalPadding']);
  _number(value['verticalPadding']);
  _number(value['cornerRadius']);
  _integer(value['maxLines']);
  _oneOf(value['textAlign'], {'left', 'center', 'right'});
  if (value['fontFamily'] != null) _string(value['fontFamily']);
}

List<String> _mediaIds(Map<String, Object?> timeline) {
  final ids = <String>{};
  for (final lane in _list(timeline['lanes'])) {
    for (final clip in _list(_map(lane)['clips'])) {
      final mediaId = _map(clip)['mediaId'];
      if (mediaId is String) ids.add(mediaId);
    }
  }
  return ids.toList(growable: false);
}

Map<String, Object?> _copyMap(Map<String, Object?> value) => {
  for (final entry in value.entries) entry.key: _copy(entry.value),
};

Object? _copy(Object? value) => switch (value) {
  Map() => _copyMap(_map(value)),
  List() => [for (final item in value) _copy(item)],
  String() || num() || bool() || null => value,
  _ => throw const EditorTimelineSchemaFailure.malformed(),
};

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const EditorTimelineSchemaFailure.malformed();
  }
  return {for (final entry in value.entries) entry.key as String: entry.value};
}

List<Object?> _list(Object? value) => value is List
    ? value.cast<Object?>()
    : throw const EditorTimelineSchemaFailure.malformed();

String _string(Object? value) => value is String && value.isNotEmpty
    ? value
    : throw const EditorTimelineSchemaFailure.malformed();

int _integer(Object? value) =>
    value is int ? value : throw const EditorTimelineSchemaFailure.malformed();

num _number(Object? value) => value is num && value.isFinite
    ? value
    : throw const EditorTimelineSchemaFailure.malformed();

bool _boolean(Object? value) =>
    value is bool ? value : throw const EditorTimelineSchemaFailure.malformed();

String _oneOf(Object? value, Set<String> allowed) {
  final name = _string(value);
  if (!allowed.contains(name)) {
    throw const EditorTimelineSchemaFailure.malformed();
  }
  return name;
}

void _keys(
  Map<String, Object?> value,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  if (!value.keys.toSet().containsAll(required) ||
      value.keys.toSet().difference({...required, ...optional}).isNotEmpty) {
    throw const EditorTimelineSchemaFailure.malformed();
  }
}
