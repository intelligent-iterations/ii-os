import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_media.dart';

const _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('detects every generated artifact media signature', () {
    expect(
      detectArtifactMediaContentType(
        Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]),
      ),
      'image/jpeg',
    );
    expect(
      detectArtifactMediaContentType(
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      ),
      'image/png',
    );
    expect(
      detectArtifactMediaContentType(
        Uint8List.fromList('RIFF0000WEBP'.codeUnits),
      ),
      'image/webp',
    );
    expect(
      detectArtifactMediaContentType(
        Uint8List.fromList('0000ftyp0000'.codeUnits),
      ),
      'video/mp4',
    );
    expect(
      detectArtifactMediaContentType(
        Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3]),
      ),
      'video/webm',
    );
    expect(
      detectArtifactMediaContentType(
        Uint8List.fromList('RIFF0000WAVE'.codeUnits),
      ),
      'audio/wav',
    );
    expect(
      detectArtifactMediaContentType(Uint8List.fromList('fLaC'.codeUnits)),
      'audio/flac',
    );
    expect(
      detectArtifactMediaContentType(Uint8List.fromList('ID3'.codeUnits)),
      'audio/mpeg',
    );
    expect(
      detectArtifactMediaContentType(Uint8List.fromList([0x00, 0x01, 0x02])),
      isNull,
    );
  });

  test(
    'verified-byte cache shares only the complete immutable identity',
    () async {
      final cache = VerifiedArtifactMediaCache(maxRetainedBytes: 1024);
      final pending = Completer<VerifiedArtifactMedia>();
      var loads = 0;
      Future<VerifiedArtifactMedia> load() {
        loads++;
        return pending.future;
      }

      final first = cache.resolve(expected: _identity(), load: load);
      final second = cache.resolve(expected: _identity(), load: load);
      pending.complete(_media(_identity()));

      expect(await first, same(await second));
      expect(loads, 1);
      await cache.resolve(
        expected: _identity(bucket: 'other-bucket'),
        load: () {
          loads++;
          return Future.value(_media(_identity(bucket: 'other-bucket')));
        },
      );
      expect(loads, 2);
    },
  );
}

ArtifactAuthorizationIdentity _identity({String bucket = 'workspace-bucket'}) =>
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
