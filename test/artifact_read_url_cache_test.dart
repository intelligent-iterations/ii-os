import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';

const _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test(
    'shares an in-flight artifact URL request and reuses its grant',
    () async {
      final cache = ArtifactReadUrlCache();
      final response = Completer<JsonMap>();
      var loads = 0;

      Future<JsonMap> load() {
        loads++;
        return response.future;
      }

      const expected = ArtifactAuthorizationIdentity(
        workspaceId: 'workspace-1',
        jobId: 'job-1',
        bucket: 'workspace-bucket',
        objectName: 'workspaces/workspace-1/runs/job-1/panel.png',
        generation: '1',
        sizeBytes: 128,
        sha256: _sha256,
        contentType: 'image/png',
      );
      final first = cache.resolve(expected: expected, load: load);
      final second = cache.resolve(expected: expected, load: load);
      final signedAt = _wholeSecondNow();
      response.complete({
        'data': {
          'url':
              'https://workspace-bucket.storage.googleapis.com/'
              'workspaces/workspace-1/runs/job-1/panel.png?'
              '${_signingQuery(signedAt, 300, '1')}',
          'expiresAt': signedAt
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'workspaceId': 'workspace-1',
          'jobId': 'job-1',
          'bucket': 'workspace-bucket',
          'object': 'workspaces/workspace-1/runs/job-1/panel.png',
          'generation': '1',
          'sizeBytes': 128,
          'sha256': _sha256,
          'contentType': 'image/png',
        },
      });

      expect(
        (await first).url,
        startsWith(
          'https://workspace-bucket.storage.googleapis.com/'
          'workspaces/workspace-1/runs/job-1/panel.png?',
        ),
      );
      expect(
        (await second).url,
        startsWith(
          'https://workspace-bucket.storage.googleapis.com/'
          'workspaces/workspace-1/runs/job-1/panel.png?',
        ),
      );
      expect(loads, 1);

      await cache.resolve(expected: expected, load: load);
      expect(loads, 1);
    },
  );

  test('renews a grant before its signed URL expires', () async {
    final cache = ArtifactReadUrlCache();
    var loads = 0;

    Future<JsonMap> load() async {
      loads++;
      final seconds = loads == 1 ? 5 : 300;
      final signedAt = _wholeSecondNow();
      return {
        'data': {
          'url':
              'https://workspace-bucket.storage.googleapis.com/'
              'workspaces/workspace-1/runs/job-2/panel.mp4?'
              '${_signingQuery(signedAt, seconds, '2')}',
          'expiresAt': signedAt
              .add(Duration(seconds: seconds))
              .toIso8601String(),
          'workspaceId': 'workspace-1',
          'jobId': 'job-2',
          'bucket': 'workspace-bucket',
          'object': 'workspaces/workspace-1/runs/job-2/panel.mp4',
          'generation': '2',
          'sizeBytes': 2048,
          'sha256': _sha256,
          'contentType': 'video/mp4',
        },
      };
    }

    const expected = ArtifactAuthorizationIdentity(
      workspaceId: 'workspace-1',
      jobId: 'job-2',
      bucket: 'workspace-bucket',
      objectName: 'workspaces/workspace-1/runs/job-2/panel.mp4',
      generation: '2',
      sizeBytes: 2048,
      sha256: _sha256,
      contentType: 'video/mp4',
    );
    final first = await cache.resolve(expected: expected, load: load);
    final renewed = await cache.resolve(expected: expected, load: load);

    expect(first.url, contains('X-Goog-Expires=5'));
    expect(renewed.url, contains('X-Goog-Expires=300'));
    expect(loads, 2);
  });

  test('does not share grants across workspace cache keys', () async {
    final cache = ArtifactReadUrlCache();
    var loads = 0;
    const objectName = 'workspaces/workspace-1/runs/job-1/panel.png';

    Future<JsonMap> load(String workspaceId) async {
      loads++;
      final signedAt = _wholeSecondNow();
      return {
        'data': {
          'url':
              'https://workspace-bucket.storage.googleapis.com/$objectName?'
              '${_signingQuery(signedAt, 300, '1')}',
          'expiresAt': signedAt
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'workspaceId': workspaceId,
          'jobId': 'job-1',
          'bucket': 'workspace-bucket',
          'object': objectName,
          'generation': '1',
          'sizeBytes': 128,
          'sha256': _sha256,
          'contentType': 'image/png',
        },
      };
    }

    await cache.resolve(
      expected: _identity(workspaceId: 'workspace-1', objectName: objectName),
      load: () => load('workspace-1'),
    );
    await cache.resolve(
      expected: _identity(workspaceId: 'workspace-2', objectName: objectName),
      load: () => load('workspace-2'),
    );

    expect(loads, 2);
  });

  test('does not share grants across workspace bucket cache keys', () async {
    final cache = ArtifactReadUrlCache();
    var loads = 0;

    Future<JsonMap> load(String bucket) async {
      loads++;
      final signedAt = _wholeSecondNow();
      return {
        'data': {
          'url':
              'https://$bucket.storage.googleapis.com/'
              'workspaces/workspace-1/runs/job-1/panel.png?'
              '${_signingQuery(signedAt, 300, '1')}',
          'expiresAt': signedAt
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'workspaceId': 'workspace-1',
          'jobId': 'job-1',
          'bucket': bucket,
          'object': 'workspaces/workspace-1/runs/job-1/panel.png',
          'generation': '1',
          'sizeBytes': 128,
          'sha256': _sha256,
          'contentType': 'image/png',
        },
      };
    }

    await cache.resolve(
      expected: _identity(bucket: 'workspace-bucket'),
      load: () => load('workspace-bucket'),
    );
    await cache.resolve(
      expected: _identity(bucket: 'replacement-workspace-bucket'),
      load: () => load('replacement-workspace-bucket'),
    );

    expect(loads, 2);
  });

  test('binds signed URLs to one exact GCS object generation', () {
    const bucket = 'workspace-bucket';
    const objectName = 'workspaces/workspace-1/runs/job-1/panel.png';
    const generation = '1';
    bool matches(String value) => signedArtifactUrlIdentityMatches(
      Uri.parse(value),
      bucket: bucket,
      objectName: objectName,
      generation: generation,
    );

    expect(
      matches(
        'https://workspace-bucket.storage.googleapis.com/'
        '$objectName?generation=1',
      ),
      isTrue,
    );
    expect(
      matches(
        'https://storage.googleapis.com/workspace-bucket/'
        '$objectName?generation=1',
      ),
      isTrue,
    );
    expect(
      matches(
        'https://other-bucket.storage.googleapis.com/'
        '$objectName?generation=1',
      ),
      isFalse,
    );
    expect(
      matches(
        'https://workspace-bucket.storage.googleapis.com/'
        'workspaces/workspace-2/runs/job-1/panel.png?generation=1',
      ),
      isFalse,
    );
    expect(
      matches(
        'https://workspace-bucket.storage.googleapis.com/'
        '$objectName?generation=2',
      ),
      isFalse,
    );
  });

  test('rejects a response whose expiry differs from its signed URL', () async {
    final cache = ArtifactReadUrlCache();
    final signedAt = _wholeSecondNow();

    await expectLater(
      cache.resolve(
        expected: _identity(),
        load: () async => {
          'data': {
            'url':
                'https://workspace-bucket.storage.googleapis.com/'
                'workspaces/workspace-1/runs/job-1/panel.png?'
                '${_signingQuery(signedAt, 300, '1')}',
            'expiresAt': signedAt
                .add(const Duration(seconds: 301))
                .toIso8601String(),
            'workspaceId': 'workspace-1',
            'jobId': 'job-1',
            'bucket': 'workspace-bucket',
            'object': 'workspaces/workspace-1/runs/job-1/panel.png',
            'generation': '1',
            'sizeBytes': 128,
            'sha256': _sha256,
            'contentType': 'image/png',
          },
        },
      ),
      throwsFormatException,
    );
  });

  test('rejects a URL without the complete singular V4 signature query', () {
    final signedAt = _wholeSecondNow();
    final expiresAt = signedAt.add(const Duration(minutes: 5));
    final base =
        'https://workspace-bucket.storage.googleapis.com/'
        'workspaces/workspace-1/runs/job-1/panel.png?generation=1&'
        'X-Goog-Date=${_v4Timestamp(signedAt)}&X-Goog-Expires=300';

    expect(signedArtifactUrlExpiryMatches(Uri.parse(base), expiresAt), isFalse);
    expect(
      signedArtifactUrlExpiryMatches(
        Uri.parse('$base&${_v4Structure(signedAt)}'),
        expiresAt,
      ),
      isTrue,
    );
    expect(
      signedArtifactUrlExpiryMatches(
        Uri.parse('$base&${_v4Structure(signedAt)}&unknown=value'),
        expiresAt,
      ),
      isFalse,
    );
    expect(
      signedArtifactUrlExpiryMatches(
        Uri.parse(
          '$base&${_v4Structure(signedAt)}&'
          'X-Goog-Signature=${List.filled(512, '0').join()}',
        ),
        expiresAt,
      ),
      isFalse,
    );
  });
}

DateTime _wholeSecondNow() => DateTime.fromMillisecondsSinceEpoch(
  (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) * 1000,
  isUtc: true,
);

String _signingQuery(DateTime signedAt, int seconds, String generation) =>
    'generation=$generation&'
    'X-Goog-Date=${_v4Timestamp(signedAt)}&X-Goog-Expires=$seconds&'
    '${_v4Structure(signedAt)}';

String _v4Structure(DateTime signedAt) =>
    'X-Goog-Algorithm=GOOG4-RSA-SHA256&'
    'X-Goog-Credential=ii-os-data%40example.com%2F'
    '${_v4Timestamp(signedAt).substring(0, 8)}%2Fauto%2Fstorage%2F'
    'goog4_request&X-Goog-SignedHeaders=host&'
    'X-Goog-Signature=${List.filled(512, '0').join()}';

ArtifactAuthorizationIdentity _identity({
  String workspaceId = 'workspace-1',
  String objectName = 'workspaces/workspace-1/runs/job-1/panel.png',
  String bucket = 'workspace-bucket',
}) => ArtifactAuthorizationIdentity(
  workspaceId: workspaceId,
  jobId: 'job-1',
  bucket: bucket,
  objectName: objectName,
  generation: '1',
  sizeBytes: 128,
  sha256: _sha256,
  contentType: 'image/png',
);

String _v4Timestamp(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${two(value.month)}${two(value.day)}T'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
}
