import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

const _presets = [
  IiOsPreset(label: 'Loose', value: 0.5, description: 'Biggest changes.'),
  IiOsPreset(label: 'Balanced', value: 1, description: 'Changes what you asked.'),
  IiOsPreset(label: 'Faithful', value: 1.4, description: 'Holds the original.'),
];

Widget _host(Widget child) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(body: SizedBox(width: 420, child: child)),
);

Widget _scale({
  required double value,
  required ValueChanged<double>? onChanged,
}) => IiOsPresetScale(
  label: 'How closely to follow the source',
  presets: _presets,
  value: value,
  minimum: 0.1,
  maximum: 1.5,
  divisions: 28,
  onChanged: onChanged,
);

void main() {
  group('IiOsPresetScale', () {
    testWidgets('names the choice instead of showing a bare number', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_scale(value: 1, onChanged: (_) {})));

      expect(find.text('Loose'), findsOneWidget);
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.text('Faithful'), findsOneWidget);
      expect(find.text('Changes what you asked.'), findsOneWidget);
      expect(find.text('1.00'), findsNothing);
    });

    testWidgets('choosing a preset reports its value', (tester) async {
      double? reported;
      await tester.pumpWidget(
        _host(_scale(value: 1, onChanged: (value) => reported = value)),
      );

      await tester.tap(find.text('Faithful'));
      expect(reported, 1.4);
    });

    testWidgets('a value between presets reads as its own setting', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_scale(value: 1.25, onChanged: (_) {})));

      expect(find.text('Custom · 1.25'), findsOneWidget);
      // The presets stay visible, so getting back to a known setting is one tap.
      expect(find.text('Balanced'), findsOneWidget);
    });

    testWidgets('the exact value is available, and folded away', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_scale(value: 1, onChanged: (_) {})));

      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.text('Set an exact value'));
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 1);
      expect(slider.min, 0.1);
      expect(slider.max, 1.5);
    });

    testWidgets('disabled when there is nothing to change it for', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_scale(value: 1, onChanged: null)));

      await tester.tap(find.text('Faithful'), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
