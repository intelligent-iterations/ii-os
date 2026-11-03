import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../tokens/elevation.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// A single dashboard metric.
///
/// Reads label-then-figure, which is the order the value is useful in: the
/// number means nothing until you know what it counts. The previous card was a
/// fixed 116px with a [Spacer] between an icon and its label, so roughly
/// two-thirds of it was empty and four of them pushed real content off a phone
/// screen entirely.
///
/// The value and the label are merged into one semantic node so a screen reader
/// announces "Active jobs, 4" rather than reading a bare number before the
/// thing it counts. An absent value renders as an em dash: the workspace has no
/// figure yet, which is not the same as zero -- pass [emptyNote] to say which.
class KpiCard extends StatelessWidget {
  const KpiCard({
    required this.label,
    required this.value,
    required this.hue,
    super.key,
    this.caption,
    this.emptyNote,
    this.emphasised = false,
  });

  final String label;
  final String? value;

  /// The semantic hue this metric belongs to. [IiOsHue.fill] tints the dot and
  /// carries no text duty; [IiOsHue.text] is what the figure may be drawn in.
  final IiOsHue hue;

  /// A short qualifier beside the figure -- "running", "+3", "no change".
  final String? caption;

  /// Why there is no figure, when [value] is null.
  final String? emptyNote;

  /// Marks the one metric currently doing work. Tints the container and lifts
  /// it, so a running job is findable on a row of resting ones.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    final reading = value ?? emptyNote ?? 'no value yet';
    return Semantics(
      label: '$label, $reading',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: IiOsMotion.of(context, IiOsMotion.base),
          curve: IiOsMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: IiOsSpacing.md,
            vertical: IiOsSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: emphasised ? hue.container : palette.surface,
            borderRadius: IiOsRadii.mdAll,
            border: Border.all(color: emphasised ? hue.fill : palette.border),
            boxShadow: emphasised ? IiOsElevation.medium : IiOsElevation.low,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _Dot(color: hue.fill),
                  IiOsGap.hXs,
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: palette.muted),
                    ),
                  ),
                ],
              ),
              IiOsGap.vXs,
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  _Figure(
                    value: value,
                    color: emphasised ? hue.text : palette.ink,
                    style: text.displaySmall,
                  ),
                  if (caption != null || (value == null && emptyNote != null))
                    Padding(
                      padding: const EdgeInsets.only(left: IiOsSpacing.xs),
                      child: Text(
                        caption ?? emptyNote!,
                        style: text.bodySmall?.copyWith(color: palette.muted),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, borderRadius: IiOsRadii.smAll),
  );
}

/// Counts up to the figure on arrival.
///
/// Only whole numbers animate. A value that is not a count -- an em dash, a
/// duration, a currency string -- is rendered as written, because interpolating
/// toward it would show numbers that were never true.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.color,
    required this.style,
  });

  final String? value;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolved = style?.copyWith(
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final target = int.tryParse(value ?? '');
    if (target == null) {
      return Text(value ?? '\u2014', style: resolved);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: target),
      duration: IiOsMotion.of(context, IiOsMotion.slow),
      curve: IiOsMotion.enter,
      builder: (context, current, _) => Text('$current', style: resolved),
    );
  }
}
