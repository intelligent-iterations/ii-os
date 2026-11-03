import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/repositories/classification_result_repository.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_document.dart';

const _object = 'workspaces/workspace-1/runs/job-1/open-jev/decisions.json';

DateTime _wholeSecondNow() => DateTime.fromMillisecondsSinceEpoch(
  (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) * 1000,
  isUtc: true,
);

String _v4Timestamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}T'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}Z';
}

String _signedUrl(DateTime signedAt, {String object = _object}) =>
    'https://workspace-bucket.storage.googleapis.com/$object?generation=7&'
    'X-Goog-Date=${_v4Timestamp(signedAt)}&X-Goog-Expires=300&'
    'X-Goog-Algorithm=GOOG4-RSA-SHA256&'
    'X-Goog-Credential=ii-os-data%40example.com%2F'
    '${_v4Timestamp(signedAt).substring(0, 8)}%2Fauto%2Fstorage%2F'
    'goog4_request&X-Goog-SignedHeaders=host&'
    'X-Goog-Signature=${List.filled(512, '0').join()}';

({ArtifactAuthorizationIdentity expected, ArtifactReadGrant grant}) _fixture(
  Uint8List bytes, {
  String contentType = 'application/json',
  int? sizeBytes,
}) {
  final signedAt = _wholeSecondNow();
  final expected = ArtifactAuthorizationIdentity(
    workspaceId: 'workspace-1',
    jobId: 'job-1',
    bucket: 'workspace-bucket',
    objectName: _object,
    generation: '7',
    sizeBytes: sizeBytes ?? bytes.length,
    sha256: sha256.convert(bytes).toString(),
    contentType: contentType,
  );
  return (
    expected: expected,
    grant: ArtifactReadGrant(
      url: _signedUrl(signedAt),
      expiresAt: signedAt.add(const Duration(minutes: 5)),
      workspaceId: expected.workspaceId,
      jobId: expected.jobId,
      bucket: expected.bucket,
      objectName: expected.objectName,
      generation: expected.generation,
      sizeBytes: expected.sizeBytes,
      sha256: expected.sha256,
      contentType: expected.contentType,
    ),
  );
}

void main() {
  final document = Uint8List.fromList(utf8.encode('{"schema_version":1}'));

  test('parses a document whose bytes match the reported object', () async {
    final fixture = _fixture(document);
    final requested = <int>[];

    final parsed = await downloadVerifiedJsonDocument(
      fetch: (uri, {required maxBytes}) async {
        requested.add(maxBytes);
        return document;
      },
      grant: fixture.grant,
      expected: fixture.expected,
    );

    expect(parsed, {'schema_version': 1});
    expect(requested, [document.length]);
  });

  test('refuses bytes whose digest differs from the report', () async {
    final fixture = _fixture(document);

    expect(
      downloadVerifiedJsonDocument(
        fetch: (_, {required maxBytes}) async =>
            Uint8List.fromList(utf8.encode('{"schema_version":2}')),
        grant: fixture.grant,
        expected: fixture.expected,
      ),
      throwsFormatException,
    );
  });

  test('never fetches media or a document over 1 MiB', () async {
    var fetched = false;
    Future<Uint8List> fetch(Uri uri, {required int maxBytes}) async {
      fetched = true;
      return document;
    }

    for (final fixture in [
      _fixture(document, contentType: 'image/png'),
      _fixture(document, sizeBytes: maxArtifactDocumentBytes + 1),
    ]) {
      await expectLater(
        downloadVerifiedJsonDocument(
          fetch: fetch,
          grant: fixture.grant,
          expected: fixture.expected,
        ),
        throwsFormatException,
      );
    }
    expect(fetched, isFalse);
  });

  test('builds an identity only for this job and a bounded JSON object', () {
    final artifact = {
      'path': _object,
      'content_type': 'application/json',
      'size_bytes': 512,
      'sha256': List.filled(64, 'a').join(),
      'generation': '7',
    };

    final identity = decisionsArtifactIdentity(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      expectedBucket: 'workspace-bucket',
      artifact: artifact,
    );
    expect(identity.objectName, _object);
    expect(
      decisionsArtifact({
        'artifacts': [artifact],
      }),
      artifact,
    );

    for (final invalid in [
      {...artifact, 'path': 'workspaces/workspace-1/runs/job-2/x.json'},
      {...artifact, 'content_type': 'image/png'},
      {...artifact, 'size_bytes': maxArtifactDocumentBytes + 1},
    ]) {
      expect(
        () => decisionsArtifactIdentity(
          workspaceId: 'workspace-1',
          jobId: 'job-1',
          expectedBucket: 'workspace-bucket',
          artifact: invalid,
        ),
        throwsFormatException,
        reason: '$invalid',
      );
    }
    expect(decisionsArtifact({'artifacts': const []}), isNull);
  });
}
