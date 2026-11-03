import 'package:flutter/material.dart';

import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'palette.dart';

abstract final class IiOsTheme {
  /// The light theme.
  static ThemeData light() => _build(IiOsPalette.light);

  /// The dark theme.
  ///
  /// Built by the same function as [light] from the other palette, so a
  /// component styled in one mode is styled in both. A second hand-maintained
  /// `ThemeData` is how the two drift apart.
  static ThemeData dark() => _build(IiOsPalette.dark);

  static ThemeData _build(IiOsPalette p) {
    final dark = p.brightness == Brightness.dark;
    // Every Material component that reads `colorScheme` gets a colour from the
    // palette rather than one generated for it. `ColorScheme.fromSeed` would
    // invent roughly thirty values nobody chose and no contrast test covers.
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.brand.text,
      onPrimary: dark ? p.canvas : p.surface,
      primaryContainer: p.brand.container,
      onPrimaryContainer: p.ink,
      secondary: p.accent.text,
      onSecondary: dark ? p.canvas : p.surface,
      secondaryContainer: p.accent.container,
      onSecondaryContainer: p.ink,
      error: p.danger.text,
      onError: dark ? p.canvas : p.surface,
      errorContainer: p.danger.container,
      onErrorContainer: p.ink,
      surface: p.surface,
      onSurface: p.ink,
      surfaceContainerHighest: p.neutralTint,
      onSurfaceVariant: p.muted,
      outline: p.borderStrong,
      outlineVariant: p.border,
      shadow: p.ink,
    );

    final text = IiOsTypography.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[p],
      scaffoldBackgroundColor: p.canvas,
      fontFamily: iiOsFontFamily,
      textTheme: text,
      // A card sits above the canvas rather than being outlined on it.
      // surfaceTintColor is cleared because Material 3 would otherwise wash
      // the surface toward the primary as elevation rises.
      cardTheme: CardThemeData(
        elevation: 1,
        color: p.surface,
        shadowColor: p.ink.withValues(alpha: dark ? 0.5 : 0.10),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: IiOsRadii.mdAll,
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: _inputBorder(p),
        enabledBorder: _inputBorder(p),
        focusedBorder: OutlineInputBorder(
          borderRadius: IiOsRadii.mdAll,
          borderSide: BorderSide(color: p.brand.text, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: IiOsSpacing.sm,
          vertical: IiOsSpacing.sm,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: p.borderStrong),
          shape: const RoundedRectangleBorder(borderRadius: IiOsRadii.mdAll),
        ),
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: p.brand.container,
        selectedColor: p.brand.text,
      ),
      // Hover is a state the theme has to express, or nothing on a page
      // acknowledges the pointer before it is clicked.
      hoverColor: p.neutralTint,
      splashColor: p.brand.container,
      highlightColor: p.brand.container,
      // Selection means one thing across the product. A list tile, a chip, and
      // a segment all say it with the brand tint; left to Material, a segment
      // reaches for `secondaryContainer` instead and a form ends up showing
      // two colours for the same idea.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.brand.container
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.brand.text
                : (states.contains(WidgetState.disabled) ? p.muted : p.ink),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.borderStrong)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.neutralTint,
        selectedColor: p.brand.container,
        side: BorderSide(color: p.border),
        shape: const RoundedRectangleBorder(borderRadius: IiOsRadii.pillAll),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: IiOsRadii.lgAll),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.charcoal,
        // The family has to be named here: `ThemeData(fontFamily:)` dresses
        // the text theme, not a component theme's own style, so a snackbar
        // styled with a bare colour is set in the platform default face.
        contentTextStyle: text.bodyMedium?.copyWith(
          fontFamily: iiOsFontFamily,
          color: dark ? p.canvas : p.surface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: IiOsRadii.mdAll),
        behavior: SnackBarBehavior.floating,
      ),
      // Page transitions inherit the motion tokens, so a viewer who asked for
      // reduced motion is not moved by navigation either.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelSmall,
        dataTextStyle: text.bodyMedium?.copyWith(fontSize: 13),
        headingRowHeight: 42,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 58,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        showDuration: IiOsMotion.slow,
        decoration: BoxDecoration(
          color: p.charcoal,
          borderRadius: IiOsRadii.smAll,
        ),
        textStyle: TextStyle(
          color: dark ? p.canvas : p.surface,
          fontSize: 12,
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}

OutlineInputBorder _inputBorder(IiOsPalette p) => OutlineInputBorder(
  borderRadius: IiOsRadii.mdAll,
  borderSide: BorderSide(color: p.borderStrong),
);
