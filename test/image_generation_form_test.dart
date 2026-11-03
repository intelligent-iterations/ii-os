import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/image_generation_form.dart';

Widget _host(Widget child) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('a blank seed is chosen here, and shown', (tester) async {
    String? submittedSeed;
    await tester.pumpWidget(
      _host(
        ImageGenerationForm(
          canSubmit: true,
          submitting: false,
          onSubmit:
              ({
                required String prompt,
                required String aspectRatio,
                required String seed,
              }) => submittedSeed = seed,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'a red barn');
    await tester.tap(find.text('Launch job'));
    await tester.pump();

    // The field says "reuse the seed from a result". That is only true if a
    // seed exists to reuse: left blank, the runner picked one and never told
    // anyone, so every image was unrepeatable.
    expect(submittedSeed, isNotNull);
    expect(int.tryParse(submittedSeed!), isNotNull);

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, submittedSeed);
  });

  testWidgets('a seed the person typed is used unchanged', (tester) async {
    String? submittedSeed;
    await tester.pumpWidget(
      _host(
        ImageGenerationForm(
          canSubmit: true,
          submitting: false,
          onSubmit:
              ({
                required String prompt,
                required String aspectRatio,
                required String seed,
              }) => submittedSeed = seed,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'a red barn');
    await tester.enterText(find.byType(TextField).last, '4242');
    await tester.tap(find.text('Launch job'));
    await tester.pump();

    expect(submittedSeed, '4242');
  });

  testWidgets('a seed that is not a number is left for the caller to reject', (
    tester,
  ) async {
    String? submittedSeed;
    await tester.pumpWidget(
      _host(
        ImageGenerationForm(
          canSubmit: true,
          submitting: false,
          onSubmit:
              ({
                required String prompt,
                required String aspectRatio,
                required String seed,
              }) => submittedSeed = seed,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'a red barn');
    await tester.enterText(find.byType(TextField).last, 'lucky');
    await tester.tap(find.text('Launch job'));
    await tester.pump();

    // Replacing it with a generated one would silently discard what they
    // typed; the ViewModel already explains why it is not a number.
    expect(submittedSeed, 'lucky');
  });

  testWidgets('shows only the shapes declared by the selected workflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ImageGenerationForm(
          canSubmit: true,
          submitting: false,
          aspectRatios: const ['1:1', '3:2', '2:3'],
          onSubmit:
              ({
                required String prompt,
                required String aspectRatio,
                required String seed,
              }) {},
        ),
      ),
    );

    expect(find.text('3:2'), findsOneWidget);
    expect(find.text('2:3'), findsOneWidget);
    expect(find.text('16:9'), findsNothing);
  });

  testWidgets('hides shape when the workflow has no aspect ratio input', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ImageGenerationForm(
          canSubmit: true,
          submitting: false,
          aspectRatios: const [],
          onSubmit:
              ({
                required String prompt,
                required String aspectRatio,
                required String seed,
              }) {},
        ),
      ),
    );

    expect(find.text('Shape'), findsNothing);
    expect(find.byType(ImageGenerationForm), findsOneWidget);
  });
}
