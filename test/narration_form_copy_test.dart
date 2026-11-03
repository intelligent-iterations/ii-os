import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/screens/narration_generation_screen.dart';

import 'page_golden_harness.dart';

void main() {
  testWidgets('the one voice is stated, not offered as a choice', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, NarrationGenerationScreen(controller: controller));

    // A dropdown with a single item is a decision that does not exist. The
    // page still has to say which voice will read the script.
    expect(find.text('Chatterbox Turbo'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('the fields say what they take', (tester) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, NarrationGenerationScreen(controller: controller));

    expect(find.text('Read in'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    expect(
      find.textContaining('Reuse the seed from a result'),
      findsOneWidget,
    );
  });

  testWidgets('storage is described as the customer owns it', (tester) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, NarrationGenerationScreen(controller: controller));

    // The assurance is worth keeping; `configured workflow`, `bucket`, and
    // `source assets` are the mechanism behind it.
    expect(find.textContaining('your own workspace storage'), findsOneWidget);
    for (final word in const ['bucket', 'source assets', 'configured workflow']) {
      expect(find.textContaining(word), findsNothing, reason: 'still says "$word"');
    }
  });
}
