import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// WCAG 2.1 contrast maths.
///
/// This lives in the design system rather than in a doc comment so the palette
/// can be asserted rather than asserted-about: `contrast_test.dart` fails the
/// build if a colour is edited to a value that no longer clears the duty
/// recorded next to it in `IiOsColors.all`.
abstract final class IiOsContrast {
  /// Relative luminance per WCAG 2.1 §relative-luminance.
  static double luminance(Color color) {
    double channel(double component) {
      return component <= 0.03928
          ? component / 12.92
          : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// Contrast ratio between two opaque colours, from 1.0 to 21.0.
  static double ratio(Color a, Color b) {
    final first = luminance(a);
    final second = luminance(b);
    final lighter = math.max(first, second);
    final darker = math.min(first, second);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Ratio as a report should print it -- two decimals, truncated rather than
  /// rounded, so a 4.497 never advertises itself as the 4.5 it does not meet.
  static String format(double value) =>
      ((value * 100).floor() / 100).toStringAsFixed(2);

  /// Whether [foreground] clears [minimumRatio] against [background].
  static bool passes(Color foreground, Color background, double minimumRatio) =>
      ratio(foreground, background) >= minimumRatio;
}
