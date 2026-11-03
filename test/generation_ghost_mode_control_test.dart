import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/screens/generate_screen.dart';
import 'package:ii_os/screens/image_edit_panel.dart';
import 'package:ii_os/screens/narration_generation_screen.dart';
import 'package:ii_os/screens/song_generation_screen.dart';
import 'package:ii_os/screens/video_editor_screen.dart';
import 'package:ii_os/screens/video_generation_screen.dart';

import 'page_golden_harness.dart';

void main() {
  testWidgets('every standalone creative page exposes Ghost mode', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);
    bool? requestedMode;
    void onGhostModeChanged(bool value) => requestedMode = value;

    final pages = <Widget>[
      GenerateScreen(
        controller: controller,
        onGhostModeChanged: onGhostModeChanged,
      ),
      ImageEditScreen(
        controller: controller,
        onGhostModeChanged: onGhostModeChanged,
      ),
      VideoGenerationScreen(
        controller: controller,
        onGhostModeChanged: onGhostModeChanged,
      ),
      VideoEditorScreen(
        controller: controller,
        onGhostModeChanged: onGhostModeChanged,
      ),
      SongGenerationScreen(
        controller: controller,
        onGhostModeChanged: onGhostModeChanged,
      ),
      NarrationGenerationScreen(
        controller: controller,
        onGhostModeChanged: onGhostModeChanged,
      ),
    ];

    for (final page in pages) {
      requestedMode = null;
      await pumpPage(tester, page);

      final control = find.byKey(const Key('generation-ghost-mode'));
      expect(control, findsOneWidget, reason: '${page.runtimeType}');
      await tester.tap(
        find.descendant(of: control, matching: find.byType(Switch)),
      );
      await tester.pump();

      expect(requestedMode, isTrue, reason: '${page.runtimeType}');
    }
  });
}
