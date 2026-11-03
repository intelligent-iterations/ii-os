@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/widgets/prompt_enhancement_editor.dart';

import 'golden_harness.dart';

/// Goldens for the DeepSeek credential settings.
///
/// Regenerate with:
///
///     flutter test --tags golden --update-goldens
void main() {
  setUpAll(loadIiOsFonts);

  Widget editor({
    required PromptEnhancementKeySource keySource,
    required TextEditingController secret,
    required TextEditingController apiKey,
    bool enabled = false,
    String installedKeyLast4 = '',
  }) => PromptEnhancementEditor(
    enabled: enabled,
    keySource: keySource,
    secretVersionController: secret,
    apiKeyController: apiKey,
    installedKeyLast4: installedKeyLast4,
    onEnabledChanged: (_) {},
    onKeySourceChanged: (_) {},
    onRemoveKey: () {},
  );

  testWidgets('prompt enhancement settings, no key installed', (tester) async {
    final secret = TextEditingController();
    final apiKey = TextEditingController();
    addTearDown(secret.dispose);
    addTearDown(apiKey.dispose);

    await tester.pumpWidget(
      goldenHarness(
        editor(
          keySource: PromptEnhancementKeySource.pasted,
          secret: secret,
          apiKey: apiKey,
        ),
        width: 620,
      ),
    );

    await expectLater(
      find.byType(PromptEnhancementEditor),
      matchesGoldenFile('goldens/prompt_enhancement_editor.png'),
    );
  });

  testWidgets('prompt enhancement settings, a key already installed', (
    tester,
  ) async {
    final secret = TextEditingController();
    final apiKey = TextEditingController();
    addTearDown(secret.dispose);
    addTearDown(apiKey.dispose);

    await tester.pumpWidget(
      goldenHarness(
        editor(
          keySource: PromptEnhancementKeySource.pasted,
          secret: secret,
          apiKey: apiKey,
          enabled: true,
          installedKeyLast4: 'a1b2',
        ),
        width: 620,
      ),
    );

    await expectLater(
      find.byType(PromptEnhancementEditor),
      matchesGoldenFile('goldens/prompt_enhancement_editor_installed.png'),
    );
  });

}
