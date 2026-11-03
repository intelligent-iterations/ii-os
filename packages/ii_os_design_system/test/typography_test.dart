import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

void main() {
  group('IiOsTypography', () {
    test('defines every Material text slot', () {
      // A slot left null falls through to a Material default with the wrong
      // size, colour, and tracking. That fallthrough is what this asserts
      // against: all fifteen are ours.
      const theme = IiOsTypography.textTheme;
      final defined = <String, TextStyle?>{
        'displayLarge': theme.displayLarge,
        'displayMedium': theme.displayMedium,
        'displaySmall': theme.displaySmall,
        'headlineLarge': theme.headlineLarge,
        'headlineMedium': theme.headlineMedium,
        'headlineSmall': theme.headlineSmall,
        'titleLarge': theme.titleLarge,
        'titleMedium': theme.titleMedium,
        'titleSmall': theme.titleSmall,
        'bodyLarge': theme.bodyLarge,
        'bodyMedium': theme.bodyMedium,
        'bodySmall': theme.bodySmall,
        'labelLarge': theme.labelLarge,
        'labelMedium': theme.labelMedium,
        'labelSmall': theme.labelSmall,
      };
      for (final entry in defined.entries) {
        expect(entry.value, isNotNull, reason: '${entry.key} is undefined');
      }
      expect(defined.length, 15);
    });

    test('the gallery slot list covers every defined slot', () {
      expect(IiOsTypography.slots.map((slot) => slot.$1).toSet().length, 15);
    });

    test('every slot pins size, weight, tracking, height and colour', () {
      for (final (name, style) in IiOsTypography.slots) {
        expect(style.fontSize, isNotNull, reason: '$name has no fontSize');
        expect(style.fontWeight, isNotNull, reason: '$name has no fontWeight');
        expect(
          style.letterSpacing,
          isNotNull,
          reason:
              '$name leaves tracking to Material, which is what put '
              'letterSpacing: 0 into 85 inline styles.',
        );
        expect(style.height, isNotNull, reason: '$name has no line height');
        expect(style.color, isNotNull, reason: '$name has no colour');
      }
    });

    test('the font family is package-qualified so consumers resolve it', () {
      // Fonts declared by a package resolve under a packages/<name>/ prefix.
      // A bare 'Manrope' here silently falls back to the platform default in
      // every consuming app.
      expect(iiOsFontFamily, 'packages/ii_os_design_system/Manrope');
    });

    test('the theme applies the brand family to every slot', () {
      final applied = IiOsTheme.light().textTheme;
      for (final (name, _) in IiOsTypography.slots) {
        final style = switch (name) {
          'displayLarge' => applied.displayLarge,
          'displayMedium' => applied.displayMedium,
          'displaySmall' => applied.displaySmall,
          'headlineLarge' => applied.headlineLarge,
          'headlineMedium' => applied.headlineMedium,
          'headlineSmall' => applied.headlineSmall,
          'titleLarge' => applied.titleLarge,
          'titleMedium' => applied.titleMedium,
          'titleSmall' => applied.titleSmall,
          'bodyLarge' => applied.bodyLarge,
          'bodyMedium' => applied.bodyMedium,
          'bodySmall' => applied.bodySmall,
          'labelLarge' => applied.labelLarge,
          'labelMedium' => applied.labelMedium,
          _ => applied.labelSmall,
        };
        expect(style?.fontFamily, iiOsFontFamily, reason: '$name lost the brand family');
      }
    });
  });
}
