@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/widgets/reference_media_thumbnail.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'golden_harness.dart';

final _png = base64Decode(
  // An 8x8 crimson swatch, so the golden proves an image actually
  // renders rather than capturing an invisible white pixel.
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAACXBIWXMAAAAB'
  'AAAAAQBPJcTWAAAAFElEQVR4nGO8KWTFgA2wYBUdtBIA770BQ1nOJUMAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('reference thumbnails render their media or their kind', (
    tester,
  ) async {
    // Deterministic states only: a live VideoPlayer would make this flaky.
    // Image.memory decodes through real async work, so the pump has to happen
    // inside runAsync or the image cell paints empty.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        goldenHarness(
          const Padding(padding: EdgeInsets.all(12), child: _ThumbnailRow()),
          width: 240,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(_ThumbnailRow),
      matchesGoldenFile('goldens/reference_media_thumbnail.png'),
    );
  });
}

final class _ThumbnailRow extends StatelessWidget {
  const _ThumbnailRow();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      ReferenceMediaThumbnail(
        bytes: _png,
        contentType: 'image/png',
        icon: LucideIcons.image,
      ),
      ReferenceMediaThumbnail(
        bytes: Uint8List(0),
        contentType: 'video/mp4',
        icon: LucideIcons.film,
      ),
      ReferenceMediaThumbnail(
        bytes: _png,
        contentType: 'audio/wav',
        icon: LucideIcons.audioLines,
      ),
    ],
  );
}
