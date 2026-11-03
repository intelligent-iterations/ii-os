import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/reference_media_thumbnail.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
  'A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Widget _host(Widget child) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('an attached image is shown rather than described', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReferenceMediaThumbnail(
          bytes: _png,
          contentType: 'image/png',
          icon: LucideIcons.image,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(LucideIcons.image), findsNothing);
  });

  testWidgets('a reference with no bytes keeps its media-kind icon', (
    tester,
  ) async {
    // The video-editor handoff arrives as an id alone; until hydration fills
    // its bytes the row must look exactly as it did before previews existed.
    await tester.pumpWidget(
      _host(
        ReferenceMediaThumbnail(
          bytes: Uint8List(0),
          contentType: 'video/mp4',
          icon: LucideIcons.film,
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(LucideIcons.film), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('audio has nothing to show and falls back to its icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReferenceMediaThumbnail(
          bytes: _png,
          contentType: 'audio/wav',
          icon: LucideIcons.audioLines,
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(LucideIcons.audioLines), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('undecodable video settles on the icon without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReferenceMediaThumbnail(
          bytes: Uint8List.fromList(const [0, 1, 2, 3, 4, 5, 6, 7]),
          contentType: 'video/mp4',
          icon: LucideIcons.film,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(LucideIcons.film), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
