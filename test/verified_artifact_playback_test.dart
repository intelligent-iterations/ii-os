import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/widgets/verified_artifact_playback.dart';

const _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  testWidgets('image decode failure can retry in place', (tester) async {
    final validPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
      'A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final retryableBytes = Uint8List(validPng.length)..setRange(0, 8, validPng);
    final media = VerifiedArtifactMedia(
      identity: ArtifactAuthorizationIdentity(
        workspaceId: 'workspace-1',
        jobId: 'job-1',
        bucket: 'workspace-bucket',
        objectName: 'workspaces/workspace-1/runs/job-1/broken.png',
        generation: '1',
        sizeBytes: validPng.length,
        sha256: _sha256,
        contentType: 'image/png',
      ),
      filename: 'broken.png',
      detectedContentType: 'image/png',
      bytes: retryableBytes,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 180,
          child: VerifiedArtifactImage(media: media),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('verified-image-retry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('verified-artifact-image-0')),
      findsOneWidget,
    );

    retryableBytes.setAll(0, validPng);
    await tester.tap(find.byKey(const Key('verified-image-retry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('verified-artifact-image-1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('verified-image-retry')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });
}
