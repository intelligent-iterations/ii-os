import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/widgets/video_editor_header.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('a new structural blocker is exposed as a live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      goldenHarness(
        VideoEditorHeader(
          project: null,
          unsavedChanges: 1,
          saving: false,
          canUndo: true,
          canRedo: false,
          failure: 'This edit contains too many clip and caption segments.',
          renderingInWorkspace: false,
          onUndo: () {},
          onRedo: null,
          onSave: null,
          onOpen: () {},
          onNew: () {},
          onHistory: null,
          onDismissFailure: () {},
          onOpenLibrary: () {},
        ),
        width: 900,
      ),
    );

    final node = tester.getSemantics(
      find.byKey(const Key('video-editor-failure-live-region')),
    );
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
