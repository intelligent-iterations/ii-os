import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/character_selected_sheet.dart';

void main() {
  testWidgets('generation spinner remains in the empty output surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: const Scaffold(
          body: CharacterSelectedSheet(generationStatus: 'running'),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('character-selected-sheet-generating')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Generating character sheet\u2026'), findsOneWidget);
  });

  testWidgets('terminal failure replaces spinner with an inline retry', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: CharacterSelectedSheet(
            generationStatus: 'failed',
            errorCode: 'qwen_image_edit_workflow_failed',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('character-selected-sheet-failed')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.textContaining('qwen_image_edit_workflow_failed'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry generation'));
    expect(retried, isTrue);
  });

  testWidgets(
    'completed generation keeps loading until its image is attached',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: const Scaffold(
            body: CharacterSelectedSheet(generationStatus: 'completed'),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('character-selected-sheet-generating')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('Preparing generated character sheet\u2026'),
        findsOneWidget,
      );
      expect(find.text('Character sheet generation failed'), findsNothing);
    },
  );

  testWidgets('a new job replaces the previous chosen sheet with loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: const Scaffold(
          body: CharacterSelectedSheet(
            image: CharacterImageModel(
              jobId: 'old-job',
              path: 'old.png',
              generation: '1',
              contentType: 'image/png',
              url: 'https://example.invalid/old.png',
              selected: true,
              createdAt: null,
            ),
            generationStatus: 'running',
            generationJobId: 'new-job',
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('character-selected-sheet-generating')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('character-selected-sheet')),
      findsNothing,
    );
  });

  testWidgets('selected sheet exposes separate beginner editing actions', (
    tester,
  ) async {
    var tweaked = false;
    var editedArea = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: CharacterSelectedSheet(
            image: const CharacterImageModel(
              jobId: 'job-1',
              path: 'sheet.png',
              generation: '1',
              contentType: 'image/png',
              url: 'https://example.invalid/sheet.png',
              selected: true,
              createdAt: null,
            ),
            onTweakSheet: () => tweaked = true,
            onEditArea: () => editedArea = true,
          ),
        ),
      ),
    );

    expect(find.text('Inpaint'), findsNothing);
    await tester.tap(find.text('Tweak entire sheet'));
    await tester.tap(find.text('Edit an area'));
    expect(tweaked, isTrue);
    expect(editedArea, isTrue);
  });
}
