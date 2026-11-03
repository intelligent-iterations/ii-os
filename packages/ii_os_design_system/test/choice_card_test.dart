import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? IiOsTheme.light() : IiOsTheme.dark(),
    home: Scaffold(body: SizedBox(width: 360, child: child)),
  );
}

void main() {
  group('IiOsChoiceCard', () {
    testWidgets('shows what the option is for, not only its name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          IiOsChoiceCard(
            title: 'Z-Image Turbo',
            description: 'Fast, clean images from a plain description.',
            meta: const ['Fastest'],
            icon: LucideIcons.zap,
            selected: false,
            onSelected: () {},
          ),
        ),
      );

      expect(find.text('Z-Image Turbo'), findsOneWidget);
      expect(
        find.text('Fast, clean images from a plain description.'),
        findsOneWidget,
      );
      expect(find.text('Fastest'), findsOneWidget);
    });

    testWidgets('reports the choice when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          IiOsChoiceCard(
            title: 'Qwen Image',
            description: 'Follows long, specific instructions.',
            selected: false,
            onSelected: () => taps++,
          ),
        ),
      );

      await tester.tap(find.text('Qwen Image'));
      expect(taps, 1);
    });

    testWidgets('marks the selected card for assistive technology', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          IiOsChoiceCard(
            title: 'FLUX.2 Klein',
            description: 'Holds detail in faces and text.',
            selected: true,
            onSelected: () {},
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(IiOsChoiceCard));
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(semantics.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    });

    testWidgets('an unavailable option says why, beside itself', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          IiOsChoiceCard(
            title: 'FLUX.2 Klein',
            description: 'Holds detail in faces and text.',
            selected: false,
            onSelected: null,
            unavailableReason: 'Not installed on this workspace.',
          ),
        ),
      );

      expect(find.text('Not installed on this workspace.'), findsOneWidget);
      await tester.tap(find.text('FLUX.2 Klein'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('reads its colours from the palette in both modes', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _host(
            IiOsChoiceCard(
              title: 'Z-Image Turbo',
              description: 'Fast, clean images from a plain description.',
              selected: true,
              onSelected: () {},
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(IiOsChoiceCard));
        final palette = IiOsPalette.of(context);
        final decoration =
            tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: find.byType(IiOsChoiceCard),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;

        expect(palette.brightness, brightness);
        expect(decoration.color, palette.brand.container);
      }
    });
  });
}
