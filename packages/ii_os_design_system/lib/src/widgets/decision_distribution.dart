import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// One option and the probability a decision model gave it.
final class IiOsDecisionShare {
  const IiOsDecisionShare({
    required this.label,
    required this.probability,
    this.chosen = false,
  });

  final String label;

  /// Between 0 and 1. Values outside that range are clamped when drawn.
  final double probability;

  /// The option the model picked. Carried by weight and words, not colour
  /// alone, so it survives a monochrome screen.
  final bool chosen;
}

/// A probability per option, as horizontal bars in the order given.
///
/// The order is the caller's -- usually the order the person wrote the options
/// in -- rather than sorted, so a distribution reads the same way every time
/// the same question is asked.
class IiOsDecisionDistribution extends StatelessWidget {
  const IiOsDecisionDistribution({required this.shares, super.key});

  final List<IiOsDecisionShare> shares;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final share in shares)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
            child: _ShareRow(share: share),
          ),
      ],
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.share});

  final IiOsDecisionShare share;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final theme = Theme.of(context).textTheme;
    final value = share.probability.clamp(0.0, 1.0);
    final percent = '${(value * 100).round()}%';
    final style = share.chosen
        ? theme.labelLarge?.copyWith(color: palette.ink)
        : theme.bodySmall?.copyWith(color: palette.muted);
    return Semantics(
      label: '${share.label}, $percent${share.chosen ? ', chosen' : ''}',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              share.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          IiOsGap.hXs,
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: IiOsRadii.pillAll,
              child: SizedBox(
                height: IiOsSpacing.xs,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: palette.neutralTint),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value,
                      child: ColoredBox(
                        color: share.chosen
                            ? palette.brand.fill
                            : palette.borderStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IiOsGap.hXs,
          SizedBox(
            width: IiOsSpacing.xxl + IiOsSpacing.xs,
            child: Text(percent, textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
  }
}
