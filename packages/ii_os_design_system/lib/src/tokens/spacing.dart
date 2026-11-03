import 'package:flutter/widgets.dart';

/// A 4pt spacing scale.
///
/// The audit that motivated these tokens found 20 distinct padding values and
/// 20 distinct gap values in use, most of them one pixel apart from a
/// neighbour. Everything below rounds to the nearest step on this scale.
abstract final class IiOsSpacing {
  /// 4 -- hairline separation inside a control.
  static const xxs = 4.0;

  /// 8 -- icon to label, chip padding.
  static const xs = 8.0;

  /// 12 -- dense list rows, form field stacking.
  static const sm = 12.0;

  /// 16 -- the default. Card padding, gaps between related blocks.
  static const md = 16.0;

  /// 20 -- comfortable card padding.
  static const lg = 20.0;

  /// 24 -- page gutters, gaps between unrelated sections.
  static const xl = 24.0;

  /// 32 -- major section breaks.
  static const xxl = 32.0;

  /// 48 -- empty-state and centred-surface breathing room.
  static const xxxl = 48.0;

  /// The scale in order, for galleries and tests.
  static const all = <(String, double)>[
    ('xxs', xxs),
    ('xs', xs),
    ('sm', sm),
    ('md', md),
    ('lg', lg),
    ('xl', xl),
    ('xxl', xxl),
    ('xxxl', xxxl),
  ];
}

/// `const` gaps for `Column` and `Row` children.
///
/// Prefer these over `SizedBox(height: 16)`: they are `const`, they name the
/// intent, and they keep the tokens-only rule satisfiable by inspection. `v` is
/// vertical (for a `Column`), `h` is horizontal (for a `Row`).
abstract final class IiOsGap {
  static const vXxs = SizedBox(height: IiOsSpacing.xxs);
  static const vXs = SizedBox(height: IiOsSpacing.xs);
  static const vSm = SizedBox(height: IiOsSpacing.sm);
  static const vMd = SizedBox(height: IiOsSpacing.md);
  static const vLg = SizedBox(height: IiOsSpacing.lg);
  static const vXl = SizedBox(height: IiOsSpacing.xl);
  static const vXxl = SizedBox(height: IiOsSpacing.xxl);

  static const hXxs = SizedBox(width: IiOsSpacing.xxs);
  static const hXs = SizedBox(width: IiOsSpacing.xs);
  static const hSm = SizedBox(width: IiOsSpacing.sm);
  static const hMd = SizedBox(width: IiOsSpacing.md);
  static const hLg = SizedBox(width: IiOsSpacing.lg);
  static const hXl = SizedBox(width: IiOsSpacing.xl);
}
