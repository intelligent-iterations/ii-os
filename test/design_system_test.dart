import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/theme/ii_os_tokens.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4) as double;
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.1 contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final first = _luminance(a);
  final second = _luminance(b);
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void main() {
  const backgrounds = {
    'surface': IiOsColors.surface,
    'canvas': IiOsColors.canvas,
  };

  group('colour contrast', () {
    test('every text colour clears WCAG AA on both backgrounds', () {
      const textColors = {
        'ink': IiOsColors.ink,
        'muted': IiOsColors.muted,
        'green': IiOsColors.green,
        'blue': IiOsColors.blue,
        'amber': IiOsColors.amber,
        'red': IiOsColors.red,
        'charcoal': IiOsColors.charcoal,
      };
      for (final MapEntry(key: name, value: color) in textColors.entries) {
        for (final MapEntry(key: surface, value: background)
            in backgrounds.entries) {
          expect(
            contrastRatio(color, background),
            greaterThanOrEqualTo(4.5),
            reason: '$name on $surface must clear WCAG AA for normal text',
          );
        }
      }
    });

    test('borderStrong clears WCAG 1.4.11 non-text contrast', () {
      for (final MapEntry(key: surface, value: background)
          in backgrounds.entries) {
        expect(
          contrastRatio(IiOsColors.borderStrong, background),
          greaterThanOrEqualTo(3.0),
          reason:
              'borderStrong bounds text fields and outlined buttons on $surface, '
              'so it must clear 3:1',
        );
      }
    });

    test('input and outlined-button boundaries use borderStrong', () {
      final theme = IiOsTheme.light();
      expect(
        theme.inputDecorationTheme.enabledBorder?.borderSide.color,
        IiOsColors.borderStrong,
      );
      final outlined = theme.outlinedButtonTheme.style?.side?.resolve(
        const <WidgetState>{},
      );
      expect(outlined?.color, IiOsColors.borderStrong);
    });
  });

  group('type scale', () {
    final textTheme = IiOsTypography.textTheme;
    final slots = <String, TextStyle?>{
      'displayLarge': textTheme.displayLarge,
      'displayMedium': textTheme.displayMedium,
      'displaySmall': textTheme.displaySmall,
      'headlineLarge': textTheme.headlineLarge,
      'headlineMedium': textTheme.headlineMedium,
      'headlineSmall': textTheme.headlineSmall,
      'titleLarge': textTheme.titleLarge,
      'titleMedium': textTheme.titleMedium,
      'titleSmall': textTheme.titleSmall,
      'bodyLarge': textTheme.bodyLarge,
      'bodyMedium': textTheme.bodyMedium,
      'bodySmall': textTheme.bodySmall,
      'labelLarge': textTheme.labelLarge,
      'labelMedium': textTheme.labelMedium,
      'labelSmall': textTheme.labelSmall,
    };

    test('every Material slot is defined', () {
      // An undefined slot silently falls through to the Material default, which
      // is the wrong size, the wrong colour, and carries its own tracking.
      for (final MapEntry(key: name, value: style) in slots.entries) {
        expect(style, isNotNull, reason: '$name falls through to Material');
      }
    });

    test('every slot pins colour, size, weight, and tracking', () {
      for (final MapEntry(key: name, value: style) in slots.entries) {
        expect(style!.color, isNotNull, reason: '$name has no colour');
        expect(style.fontSize, isNotNull, reason: '$name has no size');
        expect(style.fontWeight, isNotNull, reason: '$name has no weight');
        expect(style.letterSpacing, isNotNull, reason: '$name has no tracking');
        expect(
          {IiOsColors.ink, IiOsColors.muted},
          contains(style.color),
          reason: '$name must use a brand text colour',
        );
      }
    });
  });

  group('typeface', () {
    test('the theme resolves every slot to the bundled family', () {
      // Fonts declared by a package resolve under a packages/<name>/ prefix.
      // A bare 'Manrope' here would silently fall back to the platform default.
      expect(iiOsFontFamily, 'packages/ii_os_design_system/Manrope');
      final resolved = IiOsTheme.light().textTheme;
      for (final style in [
        resolved.displayLarge,
        resolved.headlineLarge,
        resolved.titleMedium,
        resolved.bodyMedium,
        resolved.bodySmall,
        resolved.labelSmall,
      ]) {
        expect(style?.fontFamily, iiOsFontFamily);
      }
    });

    test('every weight declared in pubspec is present on disk', () {
      // The typeface is declared by the design system and inherited from
      // there, so the app carries no second copy. The duty is unchanged: every
      // weight the package advertises has to exist, and the OFL licence has to
      // travel with the files.
      const packageRoot = 'packages/ii_os_design_system';
      final pubspec = File('$packageRoot/pubspec.yaml').readAsStringSync();
      final assets = RegExp(
        r'asset:\s*(fonts/[^\s]+\.ttf)',
      ).allMatches(pubspec).map((match) => match.group(1)!).toList();
      expect(assets.length, 4, reason: 'Manrope ships at 400, 600, 700, and 800');
      for (final asset in assets) {
        expect(
          File('$packageRoot/$asset').existsSync(),
          isTrue,
          reason: '$asset is declared in pubspec but missing',
        );
      }
      expect(
        File('$packageRoot/fonts/Manrope-LICENSE.txt').existsSync(),
        isTrue,
        reason: 'the OFL requires the licence to travel with the fonts',
      );
    });

    test('the app does not carry a second copy of the typeface', () {
      // Two declarations of the same face would bundle the bytes twice and let
      // the two drift. web/index.html loads the package path for the
      // pre-Flutter startup surface, so this also guards that path.
      expect(
        Directory('fonts').existsSync(),
        isFalse,
        reason: 'fonts belong to ii_os_design_system now',
      );
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('asset: fonts/')),
      );
      expect(
        File('web/index.html').readAsStringSync(),
        contains('assets/packages/ii_os_design_system/fonts/Manrope-Regular.ttf'),
      );
    });
  });

  group('tokens', () {
    test('spacing is a strictly ascending 4pt scale', () {
      const scale = [
        IiOsSpacing.xxs,
        IiOsSpacing.xs,
        IiOsSpacing.sm,
        IiOsSpacing.md,
        IiOsSpacing.lg,
        IiOsSpacing.xl,
        IiOsSpacing.xxl,
        IiOsSpacing.xxxl,
      ];
      for (var i = 0; i < scale.length; i++) {
        expect(scale[i] % 4, 0, reason: '${scale[i]} is off the 4pt grid');
        if (i > 0) expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('breakpoints ascend and follow the Material window classes', () {
      expect(IiOsBreakpoints.compact, 600.0);
      expect(IiOsBreakpoints.medium, 840.0);
      expect(IiOsBreakpoints.expanded, 1200.0);
      expect(IiOsBreakpoints.isCompact(599), isTrue);
      expect(IiOsBreakpoints.isCompact(600), isFalse);
      expect(IiOsBreakpoints.isExpanded(1200), isTrue);
    });

    test('the page gutter widens past the wide-gutter breakpoint', () {
      expect(iiOsPageGutter(375), IiOsSpacing.md);
      expect(iiOsPageGutter(1440), IiOsSpacing.xl);
    });
  });
}
