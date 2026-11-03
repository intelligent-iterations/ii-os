import 'package:flutter/widgets.dart';

/// The light-mode palette.
///
/// Every value here has a dark-mode counterpart in [IiOsColorsDark] under the
/// same name, and [IiOsPalette] is what a widget actually reads. Naming a
/// constant from this class inside a widget renders a fixed light colour in
/// both modes, so widgets read colour from `IiOsPalette.of(context)` instead.
abstract final class IiOsColors {
  static const ink = Color(0xFF1A1D26);
  static const muted = Color(0xFF5A6270);
  static const canvas = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);

  /// Tinted containers: where state and emphasis live.
  ///
  /// These are pastels rather than near-white washes, so a container reads as
  /// coloured at a glance instead of only under inspection. Each stays light
  /// enough that [ink] and [muted] clear WCAG AA on top of it -- `contrast_test`
  /// verifies exactly that against every surface in [textSurfaces], so a tint
  /// darkened past the point where caption text survives fails the build.
  static const greenTint = Color(0xFFDDF0E7);
  static const blueTint = Color(0xFFDEE9F9);
  static const amberTint = Color(0xFFF7EBD6);
  static const redTint = Color(0xFFF9E1E4);
  static const violetTint = Color(0xFFE7E1F7);

  /// Neutral wash for hover, pressed, and recessed wells.
  static const neutralTint = Color(0xFFF0F2F6);

  /// Structural hairline: card outlines, dividers, progress tracks.
  ///
  /// Decorative separation only. It carries no WCAG 1.4.11 duty because it
  /// never encodes the identity or state of a control -- [borderStrong] does
  /// that job.
  static const border = Color(0xFFE4E7EE);

  /// Interactive boundary: text fields, outlined buttons, selection controls.
  ///
  /// Clears the WCAG 1.4.11 non-text contrast minimum of 3:1 against both
  /// [surface] and [canvas].
  static const borderStrong = Color(0xFF767E8D);

  static const green = Color(0xFF17715A);
  static const blue = Color(0xFF2A5AAE);
  static const amber = Color(0xFF8A6321);
  static const red = Color(0xFFA83E4E);
  static const violet = Color(0xFF5B4699);
  static const charcoal = Color(0xFF2C313B);

  /// The ground generated artwork sits on, in both modes.
  static const mediaWell = Color(0xFF14161B);

  /// The fill tier: gradients, progress arcs, sparklines, glyph fills.
  ///
  /// A colour that has to survive as 12px caption text can never be luminous,
  /// which is why every hue above sits deep. These carry **no text duty** and
  /// exist so a large shape can be saturated without dragging the readable
  /// value up with it. Never put words on one, and never use one as the only
  /// carrier of meaning.
  static const greenVivid = Color(0xFF4FBF9B);
  static const blueVivid = Color(0xFF6D9FE8);
  static const amberVivid = Color(0xFFDDA64E);
  static const redVivid = Color(0xFFE28494);
  static const violetVivid = Color(0xFF9C86D9);

  /// Identity hues an operator assigns to a thing they navigate between, such
  /// as a workspace or a production line.
  ///
  /// These say *which one*, never *how is it*. [green], [amber], and [red] are
  /// already spoken for by success, warning, and error, so an identity that
  /// could claim one would make the status pill beside it unreadable.
  ///
  /// They carry the 3:1 non-text duty rather than 4.5:1 because they tint a
  /// glyph, not a string. Colour is never the only carrier: an identity always
  /// travels with its name and its icon.
  static const identityViolet = Color(0xFF5B4699);
  static const identityPlum = Color(0xFF8E2F63);
  static const identityIndigo = Color(0xFF3B4FA8);
  static const identityCyan = Color(0xFF0F6377);
  static const identitySlate = Color(0xFF4C5A67);
  static const identityMoss = Color(0xFF4F6B1F);

  /// Identity hues by their stored token key.
  ///
  /// The key is what a database holds; the [Color] never is. A stored hex
  /// would freeze a design decision into user data and could not be
  /// contrast-verified, so the token resolves here at render time instead.
  static const identity = <String, Color>{
    'violet': identityViolet,
    'plum': identityPlum,
    'indigo': identityIndigo,
    'cyan': identityCyan,
    'slate': identitySlate,
    'moss': identityMoss,
  };

  /// The container tint that belongs with a semantic colour.
  static Color tintFor(Color color) => switch (color) {
    green => greenTint,
    blue => blueTint,
    amber => amberTint,
    red => redTint,
    violet => violetTint,
    _ => neutralTint,
  };

  /// Every background a text token may legitimately be drawn on.
  static const textSurfaces = <(String, Color)>[
    ('surface', surface),
    ('canvas', canvas),
    ('greenTint', greenTint),
    ('blueTint', blueTint),
    ('amberTint', amberTint),
    ('redTint', redTint),
    ('violetTint', violetTint),
    ('neutralTint', neutralTint),
  ];

  /// The palette with the job each colour does, for galleries and tests.
  static const all = <IiOsSwatch>[
    IiOsSwatch('ink', ink, 'Primary text', 4.5),
    IiOsSwatch('muted', muted, 'Secondary text, captions', 4.5),
    IiOsSwatch('canvas', canvas, 'App background', null),
    IiOsSwatch('surface', surface, 'Cards, sheets, inputs', null),
    IiOsSwatch('border', border, 'Decorative hairline, dividers', null),
    IiOsSwatch('greenTint', greenTint, 'Success, selected, primary', null),
    IiOsSwatch('blueTint', blueTint, 'Informational container', null),
    IiOsSwatch('amberTint', amberTint, 'Warning container', null),
    IiOsSwatch('redTint', redTint, 'Error container', null),
    IiOsSwatch('violetTint', violetTint, 'Identity container', null),
    IiOsSwatch('neutralTint', neutralTint, 'Hover, pressed, recessed', null),
    IiOsSwatch('borderStrong', borderStrong, 'Interactive boundary', 3),
    IiOsSwatch('green', green, 'Brand, primary action, success', 4.5),
    IiOsSwatch('blue', blue, 'Informational status', 4.5),
    IiOsSwatch('amber', amber, 'Warning status', 4.5),
    IiOsSwatch('red', red, 'Error, destructive action', 4.5),
    IiOsSwatch('violet', violet, 'Identity status', 4.5),
    IiOsSwatch('charcoal', charcoal, 'Inverted surfaces, brand mark', null),
    IiOsSwatch('greenVivid', greenVivid, 'Fill only \u2014 no text', null),
    IiOsSwatch('blueVivid', blueVivid, 'Fill only \u2014 no text', null),
    IiOsSwatch('amberVivid', amberVivid, 'Fill only \u2014 no text', null),
    IiOsSwatch('redVivid', redVivid, 'Fill only \u2014 no text', null),
    IiOsSwatch('violetVivid', violetVivid, 'Fill only \u2014 no text', null),
    IiOsSwatch('identityViolet', identityViolet, 'Identity glyph', 3),
    IiOsSwatch('identityPlum', identityPlum, 'Identity glyph', 3),
    IiOsSwatch('identityIndigo', identityIndigo, 'Identity glyph', 3),
    IiOsSwatch('identityCyan', identityCyan, 'Identity glyph', 3),
    IiOsSwatch('identitySlate', identitySlate, 'Identity glyph', 3),
    IiOsSwatch('identityMoss', identityMoss, 'Identity glyph', 3),
  ];
}

/// The dark-mode palette.
///
/// A pastel cannot simply be lightened or darkened between modes. In light mode
/// the pastel *is* the container and a deep hue carries the words; in dark mode
/// that inverts -- the container goes deep and the pastel becomes the text. Both
/// sets therefore exist as values rather than as one set transformed.
abstract final class IiOsColorsDark {
  static const ink = Color(0xFFEDEEF2);
  static const muted = Color(0xFF9BA0AD);
  static const canvas = Color(0xFF101014);
  static const surface = Color(0xFF17181D);

  /// Containers are deep and saturated rather than washed.
  ///
  /// The first dark palette was the light pastels inverted -- the same low
  /// chroma, read the other way up -- which made both modes the same idea and
  /// left dark looking like light with the lights off. A dark interface can
  /// carry far more chroma than a light one before it shouts, because the eye
  /// is adapting to a dark field: these containers hold real colour and the
  /// text on them glows rather than washes.
  static const greenTint = Color(0xFF0E2E26);
  static const blueTint = Color(0xFF12233F);
  static const amberTint = Color(0xFF2E2413);
  static const redTint = Color(0xFF331519);
  static const violetTint = Color(0xFF241B3D);
  static const neutralTint = Color(0xFF1F2027);

  static const border = Color(0xFF2A2C34);
  static const borderStrong = Color(0xFF666B78);

  /// Jewel tones, not pastels: jade, azure, honey, coral, orchid.
  static const green = Color(0xFF5FE3B4);
  static const blue = Color(0xFF7DB2FF);
  static const amber = Color(0xFFF0C173);
  static const red = Color(0xFFFF9BA6);
  static const violet = Color(0xFFC4A6FF);

  /// The inverted surface in dark mode is a light one.
  static const charcoal = Color(0xFFEDEEF2);

  static const greenVivid = Color(0xFF16A87C);
  static const blueVivid = Color(0xFF3D74E0);
  static const amberVivid = Color(0xFFC98A2E);
  static const redVivid = Color(0xFFD4556A);
  static const violetVivid = Color(0xFF8560D8);

  static const identityViolet = Color(0xFFC4A6FF);
  static const identityPlum = Color(0xFFF49BCB);
  static const identityIndigo = Color(0xFFA9B6F0);
  static const identityCyan = Color(0xFF6FD3E8);
  static const identitySlate = Color(0xFFB6C2D0);
  static const identityMoss = Color(0xFFB9D68C);

  static const identity = <String, Color>{
    'violet': identityViolet,
    'plum': identityPlum,
    'indigo': identityIndigo,
    'cyan': identityCyan,
    'slate': identitySlate,
    'moss': identityMoss,
  };

  static Color tintFor(Color color) => switch (color) {
    green => greenTint,
    blue => blueTint,
    amber => amberTint,
    red => redTint,
    violet => violetTint,
    _ => neutralTint,
  };

  static const textSurfaces = <(String, Color)>[
    ('surface', surface),
    ('canvas', canvas),
    ('greenTint', greenTint),
    ('blueTint', blueTint),
    ('amberTint', amberTint),
    ('redTint', redTint),
    ('violetTint', violetTint),
    ('neutralTint', neutralTint),
  ];
}

/// One palette entry and the contrast duty it carries.
final class IiOsSwatch {
  const IiOsSwatch(this.name, this.color, this.role, this.minimumRatio);

  final String name;
  final Color color;
  final String role;

  /// The WCAG ratio this colour must clear against the surfaces it sits on, or
  /// `null` when it is a surface itself, a fill, or purely decorative.
  final double? minimumRatio;
}
