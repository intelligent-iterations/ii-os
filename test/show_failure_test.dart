import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/common.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('a failure is readable in ${brightness.name} mode', (
      tester,
    ) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.light
              ? IiOsTheme.light()
              : IiOsTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      showFailure(hostContext, const FormatException('It did not work.'));
      await tester.pump();

      final palette = IiOsPalette.of(hostContext);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      // `IiOsColors.red` is a `static const`, so the dark theme used to paint
      // the light red behind the dark theme's own content colour.
      expect(bar.backgroundColor, palette.danger.container);
      final text = tester.widget<Text>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
      );
      expect(text.style?.color, palette.danger.text);
      expect(palette.brightness, brightness);
    });
  }
}
