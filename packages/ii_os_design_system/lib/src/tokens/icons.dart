/// Icon sizes.
///
/// The audit that motivated this scale found 20 distinct icon sizes in use, 204
/// of the call sites clustered on 15, 16, 17, 18, 19, and 20 -- six sizes inside
/// a six-pixel band, none of them distinguishable from its neighbour at a
/// glance. That is the same pathology the 4pt spacing scale was introduced to
/// fix, one layer down.
///
/// [md] is the house size: field prefixes, button icons, list affordances.
/// Reach past it when the icon is the subject rather than a label's companion.
abstract final class IiOsIconSize {
  /// 14 -- inline with small text, dense table affordances.
  static const xs = 14.0;

  /// 16 -- secondary affordances, tight rows.
  static const sm = 16.0;

  /// 18 -- the default. Field prefixes, button icons, menu items.
  static const md = 18.0;

  /// 20 -- provider glyphs and primary actions that carry weight.
  static const lg = 20.0;

  /// 24 -- standalone icons that head a block.
  static const xl = 24.0;

  /// 32 -- empty-state and status illustrations.
  static const xxl = 32.0;

  /// The scale in order, for galleries and tests.
  static const all = <(String, double)>[
    ('xs', xs),
    ('sm', sm),
    ('md', md),
    ('lg', lg),
    ('xl', xl),
    ('xxl', xxl),
  ];
}
