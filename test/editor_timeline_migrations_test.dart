import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_timeline_codec.dart';
import 'package:ii_os/models/editor_timeline_migrations.dart';

void main() {
  test('versions fail with stable and truthful classifications', () {
    for (final malformed in [null, '1', true, 1.0]) {
      expect(
        () => prepareEditorTimeline({'version': malformed}),
        throwsA(_schemaFailure(EditorTimelineSchemaFailureKind.malformed)),
      );
    }
    expect(
      () => prepareEditorTimeline(const {'version': 0}),
      throwsA(
        _schemaFailure(EditorTimelineSchemaFailureKind.unsupportedLegacy),
      ),
    );
    expect(
      () => prepareEditorTimeline(const {'version': 2}),
      throwsA(
        _schemaFailure(EditorTimelineSchemaFailureKind.newerBuildRequired),
      ),
    );
  });

  test('codec retains the typed schema failure for its callers', () {
    expect(
      () => decodeEditorTimeline(const {'version': 2}, sources: const {}),
      throwsA(
        isA<EditorTimelineDecodeFailure>().having(
          (failure) => failure.schemaFailureKind,
          'schemaFailureKind',
          EditorTimelineSchemaFailureKind.newerBuildRequired,
        ),
      ),
    );
  });

  test('frozen v1 prepares deterministically without changing its input', () {
    final source = _fixture('project.json');
    final before = jsonEncode(source);
    final first = prepareEditorTimeline(source);
    final second = prepareEditorTimeline(source);

    expect(first.timeline, second.timeline);
    expect(first.timeline, isNot(same(source)));
    expect(first.sourceVersion, 1);
    expect(first.wasMigrated, isFalse);
    expect(first.mediaIds, ['media-1', 'media-2']);
    expect(jsonEncode(source), before);
    expect(first.timeline, _fixture('expected-current.json'));
  });

  test('fixture decodes and re-encodes at the checked current shape', () {
    final prepared = prepareEditorTimeline(_fixture('project.json'));
    final decoded = decodeEditorTimeline(
      prepared.timeline,
      sources: {
        for (final id in ['media-1', 'media-2'])
          id: MediaSource(
            id: id,
            byteLength: 1,
            fileExtension: 'mp4',
            openRead: () => Stream.value(const [1]),
          ),
      },
    );

    expect(encodeEditorTimeline(decoded), _fixture('expected-current.json'));
  });

  test('same-version unknown content is rejected instead of erased', () {
    final timeline = _fixture('project.json')..['unknown'] = 'future';
    expect(
      () => prepareEditorTimeline(timeline),
      throwsA(_schemaFailure(EditorTimelineSchemaFailureKind.malformed)),
    );
  });

  test('registry steps must be adjacent and cover every supported version', () {
    expect(
      () => validateEditorTimelineMigrationRegistry(
        oldestVersion: 1,
        currentVersion: 3,
        steps: {1: (value) => value},
      ),
      throwsStateError,
    );
    expect(
      () => validateEditorTimelineMigrationRegistry(
        oldestVersion: 1,
        currentVersion: 3,
        steps: {1: (value) => value, 2: (value) => value},
      ),
      returnsNormally,
    );
  });

  test('every supported version has a provenance manifest', () {
    const fixtureRoot = 'test/fixtures/video_editor/timeline';
    final fixtureVersions =
        Directory(fixtureRoot)
            .listSync()
            .whereType<Directory>()
            .map((entry) => entry.path.split(Platform.pathSeparator).last)
            .where((name) => RegExp(r'^v\d+$').hasMatch(name))
            .map((name) => int.parse(name.substring(1)))
            .toList()
          ..sort();
    expect(fixtureVersions, editorTimelineSupportedVersions);

    for (final version in editorTimelineSupportedVersions) {
      final root = '$fixtureRoot/v$version';
      final manifest = _fixtureAt(root, 'provenance.json');
      expect(manifest['classification'], 'synthetic');
      expect(manifest['timelineVersion'], version);
      expect(
        manifest['producerCommit'],
        '0000000000000000000000000000000000000000',
      );
      expect(
        manifest['codecSha256'],
        'a7e92b41e91ed614f232cf472e17a7cd664bbd5c072144757e92cdb9100de33d',
      );
      expect(
        manifest['declaredPackageRevision'],
        '0000000000000000000000000000000000000000',
      );
      expect(
        manifest['verificationCommand'],
        'flutter test test/editor_timeline_migrations_test.dart',
      );
      expect(
        manifest['fixtureSha256'],
        sha256.convert(File('$root/project.json').readAsBytesSync()).toString(),
      );
      expect(
        manifest['expectedCurrentSha256'],
        sha256
            .convert(File('$root/expected-current.json').readAsBytesSync())
            .toString(),
      );
    }
  });
}

Matcher _schemaFailure(EditorTimelineSchemaFailureKind kind) =>
    isA<EditorTimelineSchemaFailure>().having(
      (failure) => failure.kind,
      'kind',
      kind,
    );

Map<String, Object?> _fixture(String name) =>
    _fixtureAt('test/fixtures/video_editor/timeline/v1', name);

Map<String, Object?> _fixtureAt(String root, String name) =>
    (jsonDecode(File('$root/$name').readAsStringSync()) as Map)
        .cast<String, Object?>();
