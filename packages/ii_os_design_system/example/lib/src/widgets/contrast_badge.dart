import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

/// The measured contrast of a colour against one surface, and whether that
/// clears the duty the palette records for it.
///
/// This is the part of the gallery that can be wrong in a way that matters, so
/// it computes the ratio rather than restating a number from a comment.
class ContrastBadge extends StatelessWidget {
  const ContrastBadge({
    required this.foreground,
    required this.background,
    required this.surfaceName,
    required this.minimumRatio,
    super.key,
  });

  final Color foreground;
  final Color background;
  final String surfaceName;

  /// `null` when the colour is a surface itself, or purely decorative.
  final double? minimumRatio;

  bool get _exempt => minimumRatio == null;

  bool _passes(double ratio) => _exempt || ratio >= minimumRatio!;

  Color _accent(double ratio) {
    if (_exempt) return IiOsColors.muted;
    return _passes(ratio) ? IiOsColors.green : IiOsColors.red;
  }

  String _label(double ratio) {
    final measured = '${IiOsContrast.format(ratio)}:1 on $surfaceName';
    if (_exempt) return measured;
    return '$measured (needs ${_trim(minimumRatio!)})';
  }

  String _tooltip(double ratio) {
    if (_exempt) {
      return 'No contrast duty: this is a surface or a decorative fill.';
    }
    return _passes(ratio)
        ? 'Clears the WCAG minimum for its role.'
        : 'Below the WCAG minimum for its role.';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = IiOsContrast.ratio(foreground, background);
    final accent = _accent(ratio);
    return Tooltip(
      message: _tooltip(ratio),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: IiOsSpacing.xs,
          vertical: IiOsSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: IiOsColors.surface,
          borderRadius: IiOsRadii.pillAll,
          border: Border.all(color: _exempt ? IiOsColors.border : accent),
        ),
        child: Text(
          _label(ratio),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: accent),
        ),
      ),
    );
  }
}

/// `3` rather than `3.0`, while `4.5` is left alone.
String _trim(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
