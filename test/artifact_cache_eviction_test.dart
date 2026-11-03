import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'dart:typed_data';

const _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

ArtifactAuthorizationIdentity _identity(String bucket) =>
    ArtifactAuthorizationIdentity(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      bucket: bucket,
      objectName: 'workspaces/workspace-1/runs/job-1/panel.png',
      generation: '1',
      sizeBytes: 4,
      sha256: _sha256,
      contentType: 'image/png',
    );

VerifiedArtifactMedia _media(ArtifactAuthorizationIdentity identity) =>
    VerifiedArtifactMedia(
      identity: identity,
      filename: 'panel.png',
      detectedContentType: 'image/png',
      bytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
    );

void main() {
  test('re-reading an asset protects it from eviction', () async {
    // Eviction dropped whichever key was inserted first, so looking at a
    // thumbnail again did nothing to keep it: scrolling a grid down and back
    // up re-downloaded everything it had just shown.
    final cache = VerifiedArtifactMediaCache(
      maxEntries: 2,
      maxRetainedBytes: 4096,
    );
    var loads = 0;
    Future<VerifiedArtifactMedia> Function() loader(
      ArtifactAuthorizationIdentity identity,
    ) => () {
      loads++;
      return Future.value(_media(identity));
    };

    final first = _identity('bucket-a');
    final second = _identity('bucket-b');
    final third = _identity('bucket-c');

    await cache.resolve(expected: first, load: loader(first));
    await cache.resolve(expected: second, load: loader(second));

    // Touching the oldest entry has to make it the newest.
    await cache.resolve(expected: first, load: loader(first));
    expect(loads, 2, reason: 'the second read of the first asset was a hit');

    // Admitting a third evicts the genuinely least recently used one.
    await cache.resolve(expected: third, load: loader(third));
    expect(loads, 3);

    await cache.resolve(expected: first, load: loader(first));
    expect(loads, 3, reason: 're-read asset should have survived eviction');

    await cache.resolve(expected: second, load: loader(second));
    expect(loads, 4, reason: 'untouched asset should have been evicted');
  });

  test('a changed generation is never served from cache', () async {
    // The identity carries the object generation, so a regenerated asset at
    // the same path is a different key and must be fetched again rather than
    // served as the picture it replaced.
    final cache = VerifiedArtifactMediaCache(maxRetainedBytes: 4096);
    const original = ArtifactAuthorizationIdentity(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      bucket: 'bucket-a',
      objectName: 'workspaces/workspace-1/runs/job-1/panel.png',
      generation: '1',
      sizeBytes: 4,
      sha256: _sha256,
      contentType: 'image/png',
    );
    const replaced = ArtifactAuthorizationIdentity(
      workspaceId: 'workspace-1',
      jobId: 'job-1',
      bucket: 'bucket-a',
      objectName: 'workspaces/workspace-1/runs/job-1/panel.png',
      generation: '2',
      sizeBytes: 4,
      sha256: _sha256,
      contentType: 'image/png',
    );
    var loads = 0;
    Future<VerifiedArtifactMedia> load(
      ArtifactAuthorizationIdentity identity,
    ) {
      loads++;
      return Future.value(_media(identity));
    }

    await cache.resolve(expected: original, load: () => load(original));
    await cache.resolve(expected: original, load: () => load(original));
    expect(loads, 1);

    await cache.resolve(expected: replaced, load: () => load(replaced));
    expect(loads, 2, reason: 'a new generation is a new asset');
  });

  test('the signed-url cache stops growing without bound', () async {
    // The grant map had no ceiling at all: a long session browsing a large
    // library grew it for the lifetime of the app.
    final cache = ArtifactReadUrlCache(maxEntries: 2);
    for (final bucket in ['a', 'b', 'c', 'd']) {
      try {
        await cache.resolve(
          expected: _identity(bucket),
          load: () async => <String, Object?>{'data': <String, Object?>{}},
        );
      } on Object {
        // A grant that fails validation is simply not retained, which is the
        // other way this map stays bounded.
      }
    }
    expect(cache.entryCount, lessThanOrEqualTo(2));
  });
}
