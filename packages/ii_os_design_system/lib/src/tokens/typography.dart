import 'package:flutter/material.dart';

import 'colors.dart';

/// The bundled brand typeface.
///
/// Fonts declared by a package resolve under a `packages/<name>/` prefix, so
/// this constant -- not the bare family name -- is what a consumer must set. See
/// `fonts/README.md` for provenance, licence, and the subsetting recipe.
const iiOsFontFamily = 'packages/ii_os_design_system/Manrope';

abstract final class IiOsTypography {
  /// Every slot the app uses, defined once.
  ///
  /// Before this, five slots were defined and eleven were used, so a third of
  /// text call sites silently fell through to Material defaults -- wrong size,
  /// wrong colour, and non-zero tracking. That last one is why
  /// `letterSpacing: 0` was pasted into 85 inline styles. Define the slot here
  /// instead of patching the call site.
  ///
  /// Tracking tightens as size grows, which is how Manrope is drawn to be set.
  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
      color: IiOsColors.ink,
      fontSize: 40,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.1,
    ),
    displayMedium: TextStyle(
      color: IiOsColors.ink,
      fontSize: 34,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.12,
    ),
    displaySmall: TextStyle(
      color: IiOsColors.ink,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.15,
    ),
    headlineLarge: TextStyle(
      color: IiOsColors.ink,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    headlineMedium: TextStyle(
      color: IiOsColors.ink,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.22,
    ),
    headlineSmall: TextStyle(
      color: IiOsColors.ink,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.25,
    ),
    titleLarge: TextStyle(
      color: IiOsColors.ink,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      color: IiOsColors.ink,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      height: 1.33,
    ),
    titleSmall: TextStyle(
      color: IiOsColors.ink,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.35,
    ),
    bodyLarge: TextStyle(
      color: IiOsColors.ink,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      color: IiOsColors.ink,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.4,
    ),
    bodySmall: TextStyle(
      color: IiOsColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.35,
    ),
    labelLarge: TextStyle(
      color: IiOsColors.ink,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.3,
    ),
    labelMedium: TextStyle(
      color: IiOsColors.ink,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      height: 1.3,
    ),
    labelSmall: TextStyle(
      color: IiOsColors.muted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      height: 1.3,
    ),
  );

  /// Slot name to style, in visual order, for galleries and tests.
  ///
  /// A slot missing here is a slot nobody can see in the gallery, so
  /// `typography_test.dart` asserts this covers every slot [textTheme] defines.
  static List<(String, TextStyle)> get slots => <(String, TextStyle)>[
    ('displayLarge', textTheme.displayLarge!),
    ('displayMedium', textTheme.displayMedium!),
    ('displaySmall', textTheme.displaySmall!),
    ('headlineLarge', textTheme.headlineLarge!),
    ('headlineMedium', textTheme.headlineMedium!),
    ('headlineSmall', textTheme.headlineSmall!),
    ('titleLarge', textTheme.titleLarge!),
    ('titleMedium', textTheme.titleMedium!),
    ('titleSmall', textTheme.titleSmall!),
    ('bodyLarge', textTheme.bodyLarge!),
    ('bodyMedium', textTheme.bodyMedium!),
    ('bodySmall', textTheme.bodySmall!),
    ('labelLarge', textTheme.labelLarge!),
    ('labelMedium', textTheme.labelMedium!),
    ('labelSmall', textTheme.labelSmall!),
  ];
}
