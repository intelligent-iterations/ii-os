import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/widgets/prompt_enhancement_editor.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    required TextEditingController secret,
    required TextEditingController apiKey,
    String installedKeyLast4 = '',
    VoidCallback? onRemoveKey,
  }) async {
    var enabled = false;
    var source = PromptEnhancementKeySource.pasted;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: PromptEnhancementEditor(
              enabled: enabled,
              keySource: source,
              secretVersionController: secret,
              apiKeyController: apiKey,
              installedKeyLast4: installedKeyLast4,
              onEnabledChanged: (value) => setState(() => enabled = value),
              onKeySourceChanged: (value) => setState(() => source = value),
              onRemoveKey: onRemoveKey,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('prompt enhancement is explicit and off by default', (
    tester,
  ) async {
    final secret = TextEditingController();
    final apiKey = TextEditingController();
    addTearDown(secret.dispose);
    addTearDown(apiKey.dispose);

    await pumpEditor(tester, secret: secret, apiKey: apiKey);

    expect(find.text('Enable Enhance buttons'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('the key can be pasted before enhancement is switched on', (
    tester,
  ) async {
    final secret = TextEditingController();
    final apiKey = TextEditingController();
    addTearDown(secret.dispose);
    addTearDown(apiKey.dispose);

    await pumpEditor(tester, secret: secret, apiKey: apiKey);
    await tester.enterText(find.byType(TextField), 'sk-example-key-value');

    // Turning it on requires a credential, so a field gated on the switch
    // would make the only valid order impossible.
    expect(apiKey.text, 'sk-example-key-value');
    expect(find.text('DeepSeek API key'), findsOneWidget);
    expect(
      find.textContaining('only when someone presses Enhance'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Generation never rewrites prompts'),
      findsOneWidget,
    );
  });

  testWidgets('the pasted key is obscured and never echoed back', (
    tester,
  ) async {
    final secret = TextEditingController();
    final apiKey = TextEditingController();
    addTearDown(secret.dispose);
    addTearDown(apiKey.dispose);

    await pumpEditor(
      tester,
      secret: secret,
      apiKey: apiKey,
      installedKeyLast4: 'a1b2',
      onRemoveKey: () {},
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    expect(apiKey.text, isEmpty);
    expect(
      find.textContaining('A key ending ····a1b2 is installed'),
      findsOneWidget,
    );
    expect(find.textContaining('Leave this empty to keep it'), findsOneWidget);
  });

  testWidgets('a stored key can be removed', (tester) async {
    final secret = TextEditingController();
    final apiKey = TextEditingController();
    addTearDown(secret.dispose);
    addTearDown(apiKey.dispose);
    var removed = false;

    await pumpEditor(
      tester,
      secret: secret,
      apiKey: apiKey,
      installedKeyLast4: 'a1b2',
      onRemoveKey: () => removed = true,
    );
    await tester.tap(find.text('Remove stored key'));
    await tester.pump();

    expect(removed, isTrue);
  });

  testWidgets('Secret Manager stays available for teams that use it', (
    tester,
  ) async {
    final secret = TextEditingController();
    final apiKey = TextEditingController();
    addTearDown(secret.dispose);
    addTearDown(apiKey.dispose);

    await pumpEditor(tester, secret: secret, apiKey: apiKey);
    await tester.tap(find.text('Secret Manager'));
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek API key secret version'), findsOneWidget);
    expect(find.text('Remove stored key'), findsNothing);
    await tester.enterText(
      find.byType(TextField),
      'projects/p/secrets/deepseek-api-key/versions/latest',
    );
    expect(secret.text, 'projects/p/secrets/deepseek-api-key/versions/latest');
  });
}
