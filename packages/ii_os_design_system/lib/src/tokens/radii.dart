import 'package:flutter/widgets.dart';

/// Corner radii.
///
/// [md] is the house radius and covers cards, inputs, buttons, and menus. Reach
/// past it only when the shape itself carries meaning -- a pill for a status, a
/// circle for an avatar.
abstract final class IiOsRadii {
  /// 4 -- nested surfaces inside an already-rounded container.
  static const sm = 4.0;

  /// 8 -- the default for cards, inputs, buttons, menus.
  static const md = 8.0;

  /// 12 -- media frames and large panels.
  static const lg = 12.0;

  /// 14 -- dialogs and sheets.
  static const xl = 14.0;

  /// Fully rounded, for pills and circular affordances.
  static const pill = 999.0;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  /// The scale in order, for galleries and tests.
  static const all = <(String, double, BorderRadius)>[
    ('sm', sm, smAll),
    ('md', md, mdAll),
    ('lg', lg, lgAll),
    ('xl', xl, xlAll),
    ('pill', pill, pillAll),
  ];
}
