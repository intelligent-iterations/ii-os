import 'spacing.dart';

/// Responsive thresholds, expressed as the width at which a layout *gains* the
/// named capability.
///
/// The first three follow the Material 3 window size classes so the app agrees
/// with the framework instead of inventing a parallel scale. The rest are
/// ii-os-specific and named for the decision they drive, because a bare
/// `< 980` in a `LayoutBuilder` tells the next reader nothing.
abstract final class IiOsBreakpoints {
  /// Below this a window is a phone: single column, drawer navigation.
  static const compact = 600.0;

  /// Below this a window is a tablet or a narrow split view.
  static const medium = 840.0;

  /// At or above this a window is a desktop console.
  static const expanded = 1200.0;

  /// The navigation rail replaces the drawer.
  static const rail = 900.0;

  /// A form and its preview can sit side by side instead of stacking.
  static const sideBySide = 980.0;

  /// Paired form fields can share a row.
  static const pairedFields = 560.0;

  /// Page gutters widen from the compact inset.
  static const wideGutter = 700.0;

  static bool isCompact(double width) => width < compact;

  static bool isMedium(double width) => width >= compact && width < expanded;

  static bool isExpanded(double width) => width >= expanded;

  /// The Material window size class name for [width].
  static String sizeClass(double width) {
    if (isCompact(width)) return 'compact';
    if (width < expanded) return 'medium';
    return 'expanded';
  }

  /// Every threshold with what crossing it buys, for galleries and tests.
  static const all = <(String, double, String)>[
    ('compact', compact, 'Single column, drawer navigation below this width'),
    ('pairedFields', pairedFields, 'Paired form fields can share a row'),
    ('wideGutter', wideGutter, 'Page gutters widen from the compact inset'),
    ('medium', medium, 'Tablet or narrow split view below this width'),
    ('rail', rail, 'The navigation rail replaces the drawer'),
    ('sideBySide', sideBySide, 'Form and preview sit side by side'),
    ('expanded', expanded, 'Desktop console layout'),
  ];
}

/// Page gutter for a given viewport width.
double iiOsPageGutter(double width) =>
    width < IiOsBreakpoints.wideGutter ? IiOsSpacing.md : IiOsSpacing.xl;
