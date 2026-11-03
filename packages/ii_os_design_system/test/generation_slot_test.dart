import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    theme: IiOsTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: SizedBox(width: 320, child: child)),
    ),
  );
}

void main() {
  group('GenerationSlot', () {
    testWidgets('holds the output region before anything is dispatched', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const GenerationSlot(phase: GenerationPhase.idle)),
      );

      expect(find.text('Your result will appear here'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows progress in the surface the output will occupy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const GenerationSlot(phase: GenerationPhase.working)),
      );
      await tester.pump();

      // The execution boundary requires progress here rather than in a toast
      // or a disabled button, so the person watching the empty box sees it.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Generating'), findsOneWidget);
    });

    testWidgets('replaces the placeholder with the artifact', (tester) async {
      await tester.pumpWidget(
        _host(
          const GenerationSlot(
            phase: GenerationPhase.arrived,
            child: Placeholder(key: ValueKey('artifact')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('artifact')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('offers recovery in the same surface as the failure', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        _host(
          GenerationSlot(
            phase: GenerationPhase.failed,
            failureMessage: 'The runner never came online.',
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('The runner never came online.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('suppresses the decorative sweep under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const GenerationSlot(phase: GenerationPhase.working),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      // Shortening a looping highlight is not enough; it still pulls the eye.
      // The state has to survive on the label and spinner alone.
      expect(find.byKey(const ValueKey('generation-sweep')), findsNothing);
      expect(find.text('Generating'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('announces working state to assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const GenerationSlot(
            phase: GenerationPhase.working,
            workingLabel: 'Generating your image',
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Generating your image'), findsOneWidget);
      handle.dispose();
    });
  });
}
