import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_file_saver.dart';
import 'package:ii_os/services/verified_artifact_media.dart';

void main() {
  test('maps every verified generated media type to a download extension', () {
    expect(verifiedArtifactSaveFormat('image/jpeg').extension, 'jpg');
    expect(verifiedArtifactSaveFormat('image/png').mimeType, MimeType.png);
    expect(verifiedArtifactSaveFormat('image/webp').extension, 'webp');
    expect(verifiedArtifactSaveFormat('video/mp4').mimeType, MimeType.mp4Video);
    expect(verifiedArtifactSaveFormat('video/webm').extension, 'webm');
    expect(verifiedArtifactSaveFormat('audio/mpeg').mimeType, MimeType.mp3);
    expect(verifiedArtifactSaveFormat('audio/wav').customMimeType, 'audio/wav');
    expect(verifiedArtifactSaveFormat('audio/flac').extension, 'flac');
    expect(
      () => verifiedArtifactSaveFormat('application/octet-stream'),
      throwsArgumentError,
    );
  });

  test('derives a bounded safe local name without retaining an object path', () {
    final media = VerifiedArtifactMedia(
      identity: const ArtifactAuthorizationIdentity(
        workspaceId: 'workspace-1',
        jobId: 'job-1',
        bucket: 'bucket',
        objectName: 'workspaces/workspace-1/ghost/job-1/image/private.png',
        generation: '1',
        sizeBytes: 8,
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        contentType: 'image/png',
      ),
      filename: '../private scene?.png',
      detectedContentType: 'image/png',
      bytes: Uint8List.fromList(const [1]),
    );

    final name = verifiedArtifactDownloadName(
      media,
      fallbackName: 'ii-os-ghost-image-job-1',
    );
    expect(name, 'private-scene');
    expect(name, isNot(contains('/')));
    expect(name.length, lessThanOrEqualTo(100));
  });
}
