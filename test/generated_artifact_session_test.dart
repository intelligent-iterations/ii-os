import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/state/generated_artifact_session.dart';

void main() {
  test('ghost cleanup starts only after verified bytes reach memory', () async {
    final loaded = Completer<VerifiedArtifactMedia>();
    var cleanupCalls = 0;
    final session = GeneratedArtifactSession(
      ghostMode: true,
      load: () => loaded.future,
      consume: () async => cleanupCalls += 1,
    );

    await Future<void>.delayed(Duration.zero);
    expect(cleanupCalls, 0);

    loaded.complete(_media());
    expect(await session.media, isA<VerifiedArtifactMedia>());
    expect(cleanupCalls, 1);
    expect(session.cleanupError, isNull);
    session.dispose();
  });

  test('durable generation never consumes its artifact', () async {
    var cleanupCalls = 0;
    final session = GeneratedArtifactSession(
      ghostMode: false,
      load: () async => _media(),
      consume: () async => cleanupCalls += 1,
    );

    await session.media;
    expect(cleanupCalls, 0);
    session.dispose();
  });

  test('failed ghost cleanup preserves bytes and can be retried', () async {
    var cleanupCalls = 0;
    final session = GeneratedArtifactSession(
      ghostMode: true,
      load: () async => _media(),
      consume: () async {
        cleanupCalls += 1;
        if (cleanupCalls == 1) throw StateError('temporary cleanup failure');
      },
    );

    final media = await session.media;
    expect(media.bytes, Uint8List.fromList(const [1, 2, 3]));
    expect(session.cleanupError, isA<StateError>());

    await session.retryCleanup();
    expect(cleanupCalls, 2);
    expect(session.cleanupError, isNull);
    session.dispose();
  });

  test('closing the surface does not cancel cleanup after delivery', () async {
    final loaded = Completer<VerifiedArtifactMedia>();
    final cleaned = Completer<void>();
    final session = GeneratedArtifactSession(
      ghostMode: true,
      load: () => loaded.future,
      consume: () async => cleaned.complete(),
    );

    session.dispose();
    loaded.complete(_media());

    await session.media;
    await cleaned.future;
  });
}

VerifiedArtifactMedia _media() => VerifiedArtifactMedia(
  identity: const ArtifactAuthorizationIdentity(
    workspaceId: 'workspace-1',
    jobId: 'job-1',
    bucket: 'workspace-bucket',
    objectName: 'workspaces/workspace-1/ghost/job-1/image.png',
    generation: '1',
    sizeBytes: 3,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    contentType: 'image/png',
  ),
  filename: 'image.png',
  detectedContentType: 'image/png',
  bytes: Uint8List.fromList(const [1, 2, 3]),
);
