import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

void main() {
  group('IiOsContrast', () {
    test('matches the WCAG reference values at both extremes', () {
      expect(
        IiOsContrast.ratio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.001),
      );
      expect(
        IiOsContrast.ratio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
        closeTo(1, 0.001),
      );
    });

    test('is symmetric', () {
      final forward = IiOsContrast.ratio(IiOsColors.ink, IiOsColors.canvas);
      final backward = IiOsContrast.ratio(IiOsColors.canvas, IiOsColors.ink);
      expect(forward, closeTo(backward, 0.000001));
    });

    test('truncates rather than rounds, so 4.497 never reads as 4.5', () {
      expect(IiOsContrast.format(4.497), '4.49');
      expect(IiOsContrast.format(3.0), '3.00');
    });
  });

  group('text on every supported surface', () {
    // A tint is only a supported place to put words once it is proven to
    // carry them. Darkening one past the point where caption text survives
    // now fails here rather than shipping an unreadable container.
    for (final (label, color) in const <(String, Color)>[
      ('ink', IiOsColors.ink),
      ('muted', IiOsColors.muted),
    ]) {
      for (final (surfaceName, surfaceColor) in IiOsColors.textSurfaces) {
        test('$label clears 4.5:1 on $surfaceName', () {
          final ratio = IiOsContrast.ratio(color, surfaceColor);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '$label is ${IiOsContrast.format(ratio)}:1 on $surfaceName, '
                'below the 4.5:1 body text requires.',
          );
        });
      }
    }
  });

  group('palette', () {
    // The point of this suite: editing a colour to a value that no longer
    // clears the duty recorded beside it in IiOsColors.all fails the build,
    // rather than quietly shipping an edge nobody with low vision can see.
    for (final swatch in IiOsColors.all) {
      final minimum = swatch.minimumRatio;
      if (minimum == null) continue;

      test('${swatch.name} clears $minimum:1 on surface and canvas', () {
        final onSurface = IiOsContrast.ratio(swatch.color, IiOsColors.surface);
        final onCanvas = IiOsContrast.ratio(swatch.color, IiOsColors.canvas);

        expect(
          onSurface,
          greaterThanOrEqualTo(minimum),
          reason:
              '${swatch.name} is ${IiOsContrast.format(onSurface)}:1 on '
              'surface, below the $minimum:1 its role (${swatch.role}) '
              'requires.',
        );
        expect(
          onCanvas,
          greaterThanOrEqualTo(minimum),
          reason:
              '${swatch.name} is ${IiOsContrast.format(onCanvas)}:1 on '
              'canvas, below the $minimum:1 its role (${swatch.role}) '
              'requires.',
        );
      });
    }

    test('every palette entry is opaque', () {
      for (final swatch in IiOsColors.all) {
        expect(
          swatch.color.a,
          1.0,
          reason:
              '${swatch.name} is translucent, so its measured contrast '
              'depends on whatever happens to sit behind it.',
        );
      }
    });
  });

  // Both modes carry the same duties. A pastel cannot be derived from its
  // light counterpart by transformation, so each mode is a separate set of
  // values -- and a dark-mode regression has to fail the build exactly the way
  // a light one does, or it ships to whoever opened that mode first.
  group('every mode', () {
    for (final (mode, palette) in IiOsPalette.both) {
      for (final (label, color) in <(String, Color)>[
        ('ink', palette.ink),
        ('muted', palette.muted),
      ]) {
        for (final (surfaceName, surfaceColor) in palette.textSurfaces) {
          test('$mode: $label clears 4.5:1 on $surfaceName', () {
            final ratio = IiOsContrast.ratio(color, surfaceColor);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$mode $label is ${IiOsContrast.format(ratio)}:1 on '
                  '$surfaceName, below the 4.5:1 body text requires.',
            );
          });
        }
      }

      for (final (hueName, hue) in <(String, IiOsHue)>[
        ('brand', palette.brand),
        ('info', palette.info),
        ('warning', palette.warning),
        ('danger', palette.danger),
        ('accent', palette.accent),
      ]) {
        test('$mode: $hueName text carries words on its own surfaces', () {
          for (final (name, background) in <(String, Color)>[
            ('surface', palette.surface),
            ('canvas', palette.canvas),
            ('its own container', hue.container),
          ]) {
            final ratio = IiOsContrast.ratio(hue.text, background);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$mode $hueName text is ${IiOsContrast.format(ratio)}:1 on '
                  '$name, below the 4.5:1 it needs to carry words.',
            );
          }
        });
      }

      test('$mode: borderStrong clears 3:1 as an interactive boundary', () {
        for (final (name, background) in <(String, Color)>[
          ('surface', palette.surface),
          ('canvas', palette.canvas),
        ]) {
          final ratio = IiOsContrast.ratio(palette.borderStrong, background);
          expect(
            ratio,
            greaterThanOrEqualTo(3),
            reason:
                '$mode borderStrong is ${IiOsContrast.format(ratio)}:1 on '
                '$name, below the 3:1 WCAG 1.4.11 requires.',
          );
        }
      });

      test('$mode: every identity hue clears 3:1', () {
        palette.identity.forEach((key, color) {
          final ratio = IiOsContrast.ratio(color, palette.surface);
          expect(
            ratio,
            greaterThanOrEqualTo(3),
            reason:
                '$mode identity "$key" is ${IiOsContrast.format(ratio)}:1 on '
                'surface, below the 3:1 a meaningful glyph requires.',
          );
        });
      });
    }

    test('both modes define the same identity keys', () {
      expect(
        IiOsPalette.light.identity.keys.toSet(),
        IiOsPalette.dark.identity.keys.toSet(),
        reason:
            'An identity present in one mode and missing from the other '
            'renders as a hole in whichever mode nobody opened.',
      );
    });
  });
}
