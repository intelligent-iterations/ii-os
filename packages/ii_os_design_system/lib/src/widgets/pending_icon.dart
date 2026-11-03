import 'package:flutter/material.dart';

import '../tokens/icons.dart';

/// A button's icon, replaced by a spinner while its action is in flight.
///
/// Forty-one of the app's files hand-rolled this as
/// `SizedBox.square(dimension: 16, child: CircularProgressIndicator(...))`, each
/// picking its own dimension, so buttons changed width when they became busy
/// and rows jumped. The spinner here is laid out at exactly [size], which is
/// what stops the jump.
class PendingIcon extends StatelessWidget {
  const PendingIcon({
    required this.icon,
    required this.pending,
    this.size = IiOsIconSize.md,
    this.pendingLabel = 'Working',
    this.color,
    super.key,
  });

  /// Shown when [pending] is false.
  final IconData icon;

  final bool pending;

  /// Both states occupy this square, so the button keeps its width.
  final double size;

  /// Announced while the spinner is showing.
  final String pendingLabel;

  /// Tints both states. Null inherits from the ambient `IconTheme`, which is
  /// what a button wants. Pass one only where the glyph carries meaning the
  /// surrounding theme does not, and the spinner takes it too -- a coloured icon
  /// that turns default-blue mid-action reads as a different control.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!pending) return Icon(icon, size: size, color: color);
    return Semantics(
      label: pendingLabel,
      liveRegion: true,
      child: SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
    );
  }
}
