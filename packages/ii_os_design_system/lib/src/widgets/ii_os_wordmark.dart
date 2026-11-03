import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'ii_os_mark.dart';

/// The mark and the name together, as one lockup.
///
/// Exists so the wordmark's weight and tracking are set once. Every place that
/// drew this by hand reached for an inline `TextStyle` with its own font size,
/// which is how a brand ends up rendered four slightly different ways.
///
/// The mark is decorative here: the name is already readable text beside it, so
/// announcing both would read "ii-os ii-os".
class IiOsWordmark extends StatelessWidget {
  const IiOsWordmark({this.markSize = 40, this.style, super.key});

  final double markSize;

  /// Defaults to `displaySmall`. Pass a smaller slot for a header lockup.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IiOsMark(size: markSize),
        IiOsGap.hSm,
        Text(
          'ii-os',
          style: style ?? IiOsTypography.textTheme.displaySmall,
        ),
      ],
    );
  }
}
