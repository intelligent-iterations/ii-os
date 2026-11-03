import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/screens/song_generation_screen.dart';

import 'page_golden_harness.dart';

void main() {
  testWidgets('the render choice is named for what it gets you', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, SongGenerationScreen(controller: controller));

    expect(find.text('Full draft'), findsOneWidget);
    expect(find.text('Final quality'), findsOneWidget);
    expect(find.textContaining('Up to 2 minutes'), findsOneWidget);
    // A technical profile line described the graph, not the outcome, and
    // named hardware the customer does not own.
    expect(find.textContaining('shift 3.0'), findsNothing);
    expect(find.textContaining('GPU'), findsNothing);
    expect(find.text('Generation profile'), findsNothing);
  });

  testWidgets('the render choice is inert while nothing can run it', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, SongGenerationScreen(controller: controller));

    // No workflow resolves without a network, and the page says so above. A
    // segmented button that still accepts a tap would be offering a decision
    // that changes nothing.
    final choice = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(choice.onSelectionChanged, isNull);
    expect(
      find.text('No enabled song-generation workflow is available.'),
      findsOneWidget,
    );
  });

  testWidgets('vocal language is a searchable model-valid choice', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, SongGenerationScreen(controller: controller));

    expect(find.text('Vocal language'), findsOneWidget);
    expect(find.text('Auto \u2014 match lyrics'), findsOneWidget);
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
    expect(find.text('A language code, such as en.'), findsNothing);
  });

  testWidgets('vocal language selection updates the visible choice', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, SongGenerationScreen(controller: controller));

    await tester.tap(find.byKey(const Key('song-vocal-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spanish').last);
    await tester.pumpAndSettle();

    expect(find.text('Spanish'), findsOneWidget);
    expect(find.text('Auto \u2014 match lyrics'), findsNothing);
  });

  testWidgets('six-eight is labelled as six-eight, not six-four', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, SongGenerationScreen(controller: controller));

    final meter = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(meter);
    await tester.tap(meter);
    await tester.pumpAndSettle();

    expect(find.text('6/8'), findsOneWidget);
    expect(find.text('6/4'), findsNothing);
  });

  testWidgets('an instrumental is not asked what language it sings in', (
    tester,
  ) async {
    final controller = pageController();
    addTearDown(controller.dispose);

    await pumpPage(tester, SongGenerationScreen(controller: controller));

    expect(find.text('Vocal language'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(find.text('Vocal language'), findsNothing);
  });
}
