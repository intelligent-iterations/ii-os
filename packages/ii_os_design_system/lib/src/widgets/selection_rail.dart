import 'package:flutter/material.dart';

import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// A leading bar marking the selected entry in a long navigation list.
///
/// A tinted pill is the right emphasis for a short list and too quiet for a
/// rail of a dozen entries, where it reads as hover. The bar gives selection a
/// second, positional cue that survives being glanced at -- and it is
/// directional, so it stays on the leading edge in a right-to-left locale.
class IiOsSelectionRail extends StatelessWidget {
  const IiOsSelectionRail({
    required this.selected,
    required this.color,
    required this.child,
    super.key,
  });

  final bool selected;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (selected)
          PositionedDirectional(
            start: 0,
            top: IiOsSpacing.xs,
            bottom: IiOsSpacing.xs,
            child: AnimatedContainer(
              duration: IiOsMotion.of(context, IiOsMotion.quick),
              curve: IiOsMotion.standard,
              width: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadiusDirectional.horizontal(
                  end: Radius.circular(IiOsRadii.sm),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
