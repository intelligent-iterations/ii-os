import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'colors.dart';

/// The glyphs and hues an operator picks from to tell one thing apart from
/// another -- a production line, or anything else they navigate between.
///
/// Both halves are closed sets addressed by a stored key. A free text field
/// for an icon name renders a missing glyph the moment the icon package
/// changes, and a stored hex cannot be contrast-verified. Resolution happens
/// here, at render time, against tokens the design system can prove.
abstract final class IiOsIdentity {
  /// Glyphs by stored token key.
  ///
  /// Curated rather than open: a gallery of twelve recognisable shapes stays
  /// legible in a sidebar, where a thousand would just become noise.
  static const icons = <String, IconData>{
    'factory': LucideIcons.factory,
    'rocket': LucideIcons.rocket,
    'beaker': LucideIcons.beaker,
    'wrench': LucideIcons.wrench,
    'boxes': LucideIcons.boxes,
    'shield': LucideIcons.shield,
    'smartphone': LucideIcons.smartphone,
    'globe': LucideIcons.globe,
    'database': LucideIcons.database,
    'creditCard': LucideIcons.creditCard,
    'sparkles': LucideIcons.sparkles,
    'terminal': LucideIcons.terminal,
  };

  /// Hues by stored token key. See [IiOsColors.identity].
  static const colors = IiOsColors.identity;

  /// The glyph for [token], or [fallbackIcon] when this build does not know it.
  ///
  /// Falls back rather than throwing because the key comes from a database: a
  /// rollback or a version skew must degrade to a plain glyph, not a red
  /// screen in the middle of someone's sidebar.
  static IconData iconFor(String? token) => icons[token] ?? fallbackIcon;

  /// The hue for [token], or [fallbackColor] when this build does not know it.
  static Color colorFor(String? token) => colors[token] ?? fallbackColor;

  static const fallbackIcon = LucideIcons.factory;
  static const fallbackColor = IiOsColors.identitySlate;

  /// Every icon token in a stable order, for pickers and galleries.
  static List<String> get iconTokens => icons.keys.toList();

  /// Every colour token in a stable order, for pickers and galleries.
  static List<String> get colorTokens => colors.keys.toList();
}
