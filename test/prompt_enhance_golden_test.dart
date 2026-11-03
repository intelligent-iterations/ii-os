@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/widgets/prompt_enhance_bar.dart';
import 'package:ii_os/widgets/song_creative_fields.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import 'golden_harness.dart';

/// Goldens for the rewrite affordance.
///
/// Regenerate with:
///
///     flutter test --tags golden --update-goldens
PromptEnhanceBinding _binding({
  required PromptEnhanceOutcome outcome,
  String? message,
  bool canUndo = false,
  bool hasOfficialGuide = false,
}) => PromptEnhanceBinding(
  outcome: outcome,
  message: message,
  canUndo: canUndo,
  guideSource: hasOfficialGuide
      ? Uri.parse('https://tongyi-mai.github.io/Z-Image-blog/')
      : null,
  tooltip: 'Rewrite this against the prompting guide for Z-Image Turbo',
  onEnhance: (_) async => null,
  onUndo: () => null,
);

void main() {
  setUpAll(loadIiOsFonts);

  testWidgets('prompt enhance bar, every state a person can land in', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'a quiet street at dusk');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      goldenHarness(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PromptEnhanceBar(
              controller: controller,
              binding: _binding(
                outcome: PromptEnhanceOutcome.idle,
                hasOfficialGuide: true,
              ),
            ),
            PromptEnhanceBar(
              controller: controller,
              binding: _binding(
                outcome: PromptEnhanceOutcome.running,
                hasOfficialGuide: true,
              ),
            ),
            PromptEnhanceBar(
              controller: controller,
              binding: _binding(
                outcome: PromptEnhanceOutcome.rewritten,
                message: 'Rewritten for Z-Image Turbo.',
                canUndo: true,
                hasOfficialGuide: true,
              ),
            ),
            PromptEnhanceBar(
              controller: controller,
              binding: _binding(
                outcome: PromptEnhanceOutcome.unchanged,
                message:
                    'Your text is unchanged. DeepSeek did not answer. Try '
                    'again in a moment.',
                hasOfficialGuide: true,
              ),
            ),
          ],
        ),
        width: 560,
      ),
    );

    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/prompt_enhance_bar.png'),
    );
  });

  testWidgets('prompt enhance bar goes quiet over an empty field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      goldenHarness(
        PromptEnhanceBar(
          controller: controller,
          binding: _binding(outcome: PromptEnhanceOutcome.idle),
        ),
        width: 560,
      ),
    );

    await expectLater(
      find.byType(PromptEnhanceBar),
      matchesGoldenFile('goldens/prompt_enhance_bar_empty.png'),
    );
  });

  testWidgets('song creative fields, description and lyrics', (tester) async {
    final description = TextEditingController(
      text: 'Dream pop, layered guitars, patient tempo',
    );
    final lyrics = TextEditingController(text: '[Verse]\nThe harbour lights');
    addTearDown(description.dispose);
    addTearDown(lyrics.dispose);

    await tester.pumpWidget(
      goldenHarness(
        SongCreativeFields(
          description: description,
          lyrics: lyrics,
          enabled: true,
          instrumental: false,
          onInstrumentalChanged: (_) {},
          descriptionEnhance: _binding(
            outcome: PromptEnhanceOutcome.rewritten,
            message: 'Rewritten for ACE-Step 1.5.',
            canUndo: true,
          ),
          lyricsEnhance: _binding(outcome: PromptEnhanceOutcome.idle),
        ),
        width: 560,
      ),
    );

    await expectLater(
      find.byType(SongCreativeFields),
      matchesGoldenFile('goldens/song_creative_fields.png'),
    );
  });

  testWidgets('song creative fields, lyrics off for an instrumental', (
    tester,
  ) async {
    final description = TextEditingController(text: 'Ambient piano study');
    final lyrics = TextEditingController();
    addTearDown(description.dispose);
    addTearDown(lyrics.dispose);

    await tester.pumpWidget(
      goldenHarness(
        SongCreativeFields(
          description: description,
          lyrics: lyrics,
          enabled: true,
          instrumental: true,
          onInstrumentalChanged: (_) {},
          descriptionEnhance: _binding(outcome: PromptEnhanceOutcome.idle),
          lyricsEnhance: _binding(outcome: PromptEnhanceOutcome.idle),
        ),
        width: 560,
      ),
    );

    await expectLater(
      find.byType(SongCreativeFields),
      matchesGoldenFile('goldens/song_creative_fields_instrumental.png'),
    );
  });
}
