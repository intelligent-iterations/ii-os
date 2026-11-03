import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/widgets/video_editor_progress_surface.dart';

void main() {
  testWidgets('local render progress occupies the future output surface', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: VideoEditorProgressSurface(
            stage: 'Rendering and compressing on this device\u2026',
            progress: 0.25,
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('video-editor-output-surface')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('compressing on this device'), findsOneWidget);
    await tester.tap(find.text('Cancel local render'));
    expect(cancelled, isTrue);
  });

  testWidgets('direct upload keeps the same output surface busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.expand(
          child: VideoEditorProgressSurface(
            stage: 'Uploading directly to the workspace GCS bucket\u2026',
            progress: null,
            onCancel: null,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('video-editor-output-surface')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('workspace GCS bucket'), findsOneWidget);
    expect(find.text('Cancel local render'), findsNothing);
  });
}
