@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/widgets/artifact_preview.dart';

import 'golden_harness.dart';

void main() {
  setUpAll(() async {
    await loadIiOsFonts();
    final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await lucide.load();
  });

  testWidgets('ArtifactPreviewAction renders the centered play control', (
    tester,
  ) async {
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('artifact-preview-action-golden'),
          child: SizedBox(
            height: 120,
            child: ArtifactPreviewAction(
              load: _unusedLoad,
              autoplay: true,
              presentation: ArtifactPreviewPresentation.play,
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const Key('artifact-preview-action-golden')),
      matchesGoldenFile('goldens/artifact_preview_action_play.png'),
    );
  });
}

Future<VerifiedArtifactMedia> _unusedLoad() =>
    throw StateError('The golden does not activate the control.');
