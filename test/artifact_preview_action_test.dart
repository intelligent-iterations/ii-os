import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/widgets/artifact_preview.dart';
import 'package:ii_os/widgets/verified_artifact_playback.dart';

void main() {
  testWidgets('play control opens the verified video and requests autoplay', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      _harness(() async {
        reads++;
        return _video();
      }),
    );

    await tester.tap(find.byKey(const Key('history-video-play')));
    await tester.pump();

    expect(reads, 1);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester
          .widget<VerifiedArtifactVideo>(find.byType(VerifiedArtifactVideo))
          .autoplay,
      isTrue,
    );
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('play control supports ${key.keyLabel} activation', (
      tester,
    ) async {
      var reads = 0;
      await tester.pumpWidget(
        _harness(() async {
          reads++;
          return _video();
        }),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(key);
      await tester.pump();

      expect(reads, 1);
      expect(find.byType(Dialog), findsOneWidget);
    });
  }

  testWidgets('eye preview keeps verified loading and manual video start', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      _harness(
        () async {
          reads++;
          return _video();
        },
        autoplay: false,
        presentation: ArtifactPreviewPresentation.eye,
      ),
    );

    await tester.tap(find.byTooltip('Preview asset'));
    await tester.pump();

    expect(reads, 1);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester
          .widget<VerifiedArtifactVideo>(find.byType(VerifiedArtifactVideo))
          .autoplay,
      isFalse,
    );
  });
}

Widget _harness(
  Future<VerifiedArtifactMedia> Function() load, {
  bool autoplay = true,
  ArtifactPreviewPresentation presentation = ArtifactPreviewPresentation.play,
}) => MaterialApp(
  home: Scaffold(
    body: ArtifactPreviewAction(
      load: load,
      autoplay: autoplay,
      presentation: presentation,
    ),
  ),
);

VerifiedArtifactMedia _video() => VerifiedArtifactMedia(
  identity: const ArtifactAuthorizationIdentity(
    workspaceId: 'workspace-1',
    jobId: 'job-1',
    bucket: 'workspace-bucket',
    objectName: 'workspaces/workspace-1/runs/job-1/video.mp4',
    generation: '1',
    sizeBytes: 4,
    sha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    contentType: 'video/mp4',
  ),
  filename: 'video.mp4',
  detectedContentType: 'video/mp4',
  bytes: Uint8List.fromList(const [0, 0, 0, 0]),
);
