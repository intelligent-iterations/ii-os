import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/character_design_regions.dart';
import 'package:ii_os/widgets/character_designer.dart';

void main() {
  test('guided regions expose every character question exactly once', () {
    final headKeys = headDesignRegions
        .expand((region) => region.questionKeys)
        .toList();
    final bodyKeys = bodyDesignRegions
        .expand((region) => region.questionKeys)
        .toList();
    final expectedBodyKeys = [
      ...characterBodyQuestions.map((question) => question.key),
      ...characterClothingQuestions.map((question) => question.key),
    ];

    expect(
      headKeys,
      unorderedEquals(characterHeadQuestions.map((item) => item.key)),
    );
    expect(
      characterSharedQuestions.map((item) => item.key),
      unorderedEquals(characterSharedAnswerKeys),
    );
    expect(headKeys.toSet(), hasLength(headKeys.length));
    expect(bodyKeys, unorderedEquals(expectedBodyKeys));
    expect(bodyKeys.toSet(), hasLength(bodyKeys.length));
  });

  testWidgets('head feature menu updates its editor and silhouette progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(theme: IiOsTheme.light(), home: const _DesignerHarness()),
    );
    await tester.pump();

    expect(find.text('Shape the head'), findsOneWidget);
    expect(find.text('Face shape'), findsWidgets);
    expect(
      find.text('What is the character\u2019s skin tone and undertone?'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('character-region-eyes')));
    await tester.pumpAndSettle();
    expect(find.text('Eyes & brows'), findsWidgets);
    expect(
      find.text('What are the character\u2019s eyes like?'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('character-field-eyes')),
      'Wide-set hazel eyes with heavy upper lids.',
    );
    await tester.pump();

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('character-head-progress')),
    );
    expect(progress.value, closeTo(1 / characterHeadQuestions.length, 0.0001));
    expect(find.text('Eyes & brows · 1/2'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Eyes & brows, 50 percent complete')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('character-hotspot-mouth')));
    await tester.pumpAndSettle();
    expect(
      find.text('What are the character\u2019s lips like?'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('character-field-expression')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

class _DesignerHarness extends StatefulWidget {
  const _DesignerHarness();

  @override
  State<_DesignerHarness> createState() => _DesignerHarnessState();
}

class _DesignerHarnessState extends State<_DesignerHarness> {
  final headAnswers = {
    for (final question in characterQuestions)
      question.key: TextEditingController(),
  };
  final bodyAnswers = {
    for (final question in characterBodyQuestions)
      question.key: TextEditingController(),
  };
  final clothingAnswers = {
    for (final question in characterClothingQuestions)
      question.key: TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in [
      ...headAnswers.values,
      ...bodyAnswers.values,
      ...clothingAnswers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: CharacterDesigner(
          kind: CharacterDesignKind.head,
          headAnswers: headAnswers,
          bodyAnswers: bodyAnswers,
          clothingAnswers: clothingAnswers,
          onChanged: () => setState(() {}),
          enabled: true,
        ),
      ),
    );
  }
}
