import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// One semantic hue, in the three tiers it is allowed to appear as.
///
/// The tiers exist because a single value cannot do all three jobs. A colour
/// that has to clear 4.5:1 as 12px caption text can never be luminous, so a
/// palette with one value per hue is forced deep and desaturated everywhere.
/// Splitting the duty is what lets a fill be saturated while the readable value
/// stays readable.
@immutable
final class IiOsHue {
  const IiOsHue({
    required this.text,
    required this.container,
    required this.fill,
  });

  /// Words and small icons. Clears 4.5:1 on [IiOsPalette.surface],
  /// [IiOsPalette.canvas], and its own [container].
  final Color text;

  /// A tinted surface. [IiOsPalette.ink] and [IiOsPalette.muted] clear 4.5:1
  /// on top of it.
  final Color container;

  /// Gradients, progress arcs, sparklines, glyph fills.
  ///
  /// Carries **no** text contrast duty and must never have words placed on it,
  /// nor be the only carrier of meaning.
  final Color fill;

  IiOsHue lerp(IiOsHue other, double t) => IiOsHue(
    text: Color.lerp(text, other.text, t)!,
    container: Color.lerp(container, other.container, t)!,
    fill: Color.lerp(fill, other.fill, t)!,
  );
}

/// Every colour a widget is allowed to read, resolved for the current mode.
///
/// This is the only supported way to get a colour. Naming a constant from
/// [IiOsColors] inside a widget renders a fixed light value in both modes --
/// it will look correct in review and wrong in dark mode, with no analyzer
/// error to catch it.
///
/// ```dart
/// final palette = IiOsPalette.of(context);
/// DecoratedBox(
///   decoration: BoxDecoration(color: palette.success.container),
///   child: Text('Completed', style: TextStyle(color: palette.success.text)),
/// );
/// ```
@immutable
final class IiOsPalette extends ThemeExtension<IiOsPalette> {
  const IiOsPalette({
    required this.brightness,
    required this.ink,
    required this.muted,
    required this.canvas,
    required this.surface,
    required this.neutralTint,
    required this.border,
    required this.borderStrong,
    required this.charcoal,
    required this.mediaWell,
    required this.brand,
    required this.info,
    required this.warning,
    required this.danger,
    required this.accent,
    required this.identity,
  });

  final Brightness brightness;

  final Color ink;
  final Color muted;
  final Color canvas;
  final Color surface;

  /// Hover, pressed, and recessed wells.
  final Color neutralTint;

  /// Decorative hairline. Carries no contrast duty.
  final Color border;

  /// Interactive boundary. Clears 3:1 on [surface] and [canvas].
  final Color borderStrong;

  /// Inverted surfaces and the brand mark.
  final Color charcoal;

  /// The ground generated artwork sits on.
  ///
  /// Deep in **both** modes, so a thumbnail reads the same whichever theme the
  /// viewer is in and nothing around it competes with the picture. It is why
  /// editing tools are dark, kept as one surface rather than a whole theme.
  final Color mediaWell;

  /// Brand, primary action, and success.
  final IiOsHue brand;

  /// Informational and in-progress.
  final IiOsHue info;

  /// Needs attention, pending, unchecked.
  final IiOsHue warning;

  /// Failed and destructive. Deliberately expensive -- never decorative.
  final IiOsHue danger;

  /// Identity and non-status emphasis.
  final IiOsHue accent;

  /// Identity hues by their stored token key. The key is what a database
  /// holds; the [Color] resolves here so it can be contrast-verified and so it
  /// can differ between modes.
  final Map<String, Color> identity;

  static const light = IiOsPalette(
    brightness: Brightness.light,
    ink: IiOsColors.ink,
    muted: IiOsColors.muted,
    canvas: IiOsColors.canvas,
    surface: IiOsColors.surface,
    neutralTint: IiOsColors.neutralTint,
    border: IiOsColors.border,
    borderStrong: IiOsColors.borderStrong,
    charcoal: IiOsColors.charcoal,
    mediaWell: IiOsColors.mediaWell,
    brand: IiOsHue(
      text: IiOsColors.green,
      container: IiOsColors.greenTint,
      fill: IiOsColors.greenVivid,
    ),
    info: IiOsHue(
      text: IiOsColors.blue,
      container: IiOsColors.blueTint,
      fill: IiOsColors.blueVivid,
    ),
    warning: IiOsHue(
      text: IiOsColors.amber,
      container: IiOsColors.amberTint,
      fill: IiOsColors.amberVivid,
    ),
    danger: IiOsHue(
      text: IiOsColors.red,
      container: IiOsColors.redTint,
      fill: IiOsColors.redVivid,
    ),
    accent: IiOsHue(
      text: IiOsColors.violet,
      container: IiOsColors.violetTint,
      fill: IiOsColors.violetVivid,
    ),
    identity: IiOsColors.identity,
  );

  static const dark = IiOsPalette(
    brightness: Brightness.dark,
    ink: IiOsColorsDark.ink,
    muted: IiOsColorsDark.muted,
    canvas: IiOsColorsDark.canvas,
    surface: IiOsColorsDark.surface,
    neutralTint: IiOsColorsDark.neutralTint,
    border: IiOsColorsDark.border,
    borderStrong: IiOsColorsDark.borderStrong,
    charcoal: IiOsColorsDark.charcoal,
    mediaWell: IiOsColors.mediaWell,
    brand: IiOsHue(
      text: IiOsColorsDark.green,
      container: IiOsColorsDark.greenTint,
      fill: IiOsColorsDark.greenVivid,
    ),
    info: IiOsHue(
      text: IiOsColorsDark.blue,
      container: IiOsColorsDark.blueTint,
      fill: IiOsColorsDark.blueVivid,
    ),
    warning: IiOsHue(
      text: IiOsColorsDark.amber,
      container: IiOsColorsDark.amberTint,
      fill: IiOsColorsDark.amberVivid,
    ),
    danger: IiOsHue(
      text: IiOsColorsDark.red,
      container: IiOsColorsDark.redTint,
      fill: IiOsColorsDark.redVivid,
    ),
    accent: IiOsHue(
      text: IiOsColorsDark.violet,
      container: IiOsColorsDark.violetTint,
      fill: IiOsColorsDark.violetVivid,
    ),
    identity: IiOsColorsDark.identity,
  );

  /// Both palettes, for the gallery and for `contrast_test`.
  ///
  /// A hue added to one mode and not the other fails the build here rather
  /// than rendering as a hole in whichever mode nobody opened.
  static const both = <(String, IiOsPalette)>[('light', light), ('dark', dark)];

  /// The container tint that belongs with a semantic text colour.
  Color tintFor(Color color) => switch (color) {
    _ when color == brand.text => brand.container,
    _ when color == info.text => info.container,
    _ when color == warning.text => warning.container,
    _ when color == danger.text => danger.container,
    _ when color == accent.text => accent.container,
    _ => neutralTint,
  };

  /// Every background a text token may legitimately be drawn on.
  List<(String, Color)> get textSurfaces => <(String, Color)>[
    ('surface', surface),
    ('canvas', canvas),
    ('brandContainer', brand.container),
    ('infoContainer', info.container),
    ('warningContainer', warning.container),
    ('dangerContainer', danger.container),
    ('accentContainer', accent.container),
    ('neutralTint', neutralTint),
  ];

  /// The only supported way for a widget to read a colour.
  static IiOsPalette of(BuildContext context) =>
      Theme.of(context).extension<IiOsPalette>() ?? light;

  @override
  IiOsPalette copyWith({
    Brightness? brightness,
    Color? ink,
    Color? muted,
    Color? canvas,
    Color? surface,
    Color? neutralTint,
    Color? border,
    Color? borderStrong,
    Color? charcoal,
    Color? mediaWell,
    IiOsHue? brand,
    IiOsHue? info,
    IiOsHue? warning,
    IiOsHue? danger,
    IiOsHue? accent,
    Map<String, Color>? identity,
  }) {
    return IiOsPalette(
      brightness: brightness ?? this.brightness,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      neutralTint: neutralTint ?? this.neutralTint,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      charcoal: charcoal ?? this.charcoal,
      mediaWell: mediaWell ?? this.mediaWell,
      brand: brand ?? this.brand,
      info: info ?? this.info,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      accent: accent ?? this.accent,
      identity: identity ?? this.identity,
    );
  }

  @override
  IiOsPalette lerp(covariant IiOsPalette? other, double t) {
    if (other == null) return this;
    return IiOsPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      neutralTint: Color.lerp(neutralTint, other.neutralTint, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      charcoal: Color.lerp(charcoal, other.charcoal, t)!,
      mediaWell: Color.lerp(mediaWell, other.mediaWell, t)!,
      brand: brand.lerp(other.brand, t),
      info: info.lerp(other.info, t),
      warning: warning.lerp(other.warning, t),
      danger: danger.lerp(other.danger, t),
      accent: accent.lerp(other.accent, t),
      identity: t < 0.5 ? identity : other.identity,
    );
  }
}
