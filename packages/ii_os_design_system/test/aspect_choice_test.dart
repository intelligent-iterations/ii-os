import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

const _ratios = [
  IiOsAspectOption(label: '1:1', width: 1, height: 1),
  IiOsAspectOption(label: '16:9', width: 16, height: 9),
  IiOsAspectOption(label: '9:16', width: 9, height: 16),
];

Widget _host(Widget child, {double width = 420}) => MaterialApp(
  theme: IiOsTheme.light(),
  home: Scaffold(body: SizedBox(width: width, child: child)),
);

void main() {
  group('IiOsAspectChoice', () {
    testWidgets('draws each option at the shape it produces', (tester) async {
      await tester.pumpWidget(
        _host(
          IiOsAspectChoice(
            options: _ratios,
            selected: '1:1',
            onSelected: (_) {},
          ),
        ),
      );

      Size shapeOf(String label) => tester.getSize(
        find.byKey(ValueKey('aspect-shape-$label')),
      );

      final square = shapeOf('1:1');
      expect(square.width, closeTo(square.height, 0.5));

      final wide = shapeOf('16:9');
      expect(wide.width / wide.height, closeTo(16 / 9, 0.05));

      final tall = shapeOf('9:16');
      expect(tall.width / tall.height, closeTo(9 / 16, 0.05));
    });

    testWidgets('every shape fits the same box, so the row reads as one row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          IiOsAspectChoice(
            options: _ratios,
            selected: '1:1',
            onSelected: (_) {},
          ),
        ),
      );

      final sizes = _ratios
          .map(
            (option) => tester.getSize(
              find.byKey(ValueKey('aspect-shape-${option.label}')),
            ),
          )
          .toList();
      final longest = sizes
          .map((size) => size.longestSide)
          .toSet();
      expect(longest.length, 1, reason: 'every shape scales from one box');
      for (final size in sizes) {
        expect(size.shortestSide, lessThanOrEqualTo(longest.single));
      }
    });

    testWidgets('reports the ratio that was chosen', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        _host(
          IiOsAspectChoice(
            options: _ratios,
            selected: '1:1',
            onSelected: (value) => chosen = value,
          ),
        ),
      );

      await tester.tap(find.text('16:9'));
      expect(chosen, '16:9');
    });

    testWidgets('marks the chosen one for assistive technology', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          IiOsAspectChoice(
            options: _ratios,
            selected: '16:9',
            onSelected: (_) {},
          ),
        ),
      );

      final node = tester.getSemantics(
        find.byKey(const ValueKey('aspect-16:9')),
      );
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.label, contains('16:9'));
    });

    testWidgets('does nothing when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          IiOsAspectChoice(
            options: _ratios,
            selected: '1:1',
            onSelected: (_) => taps++,
            enabled: false,
          ),
        ),
      );

      await tester.tap(find.text('16:9'), warnIfMissed: false);
      expect(taps, 0);
    });
  });
}
