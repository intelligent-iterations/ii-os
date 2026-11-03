import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// A quiet label for a fact about the thing beside it -- a model name, a count,
/// a format, a repository.
///
/// Deliberately not a [Chip]: Material's chip is an interactive affordance and
/// reads as one, which invites a click that does nothing. This is a boundary
/// around a word, sized to sit inline with body text.
class IiOsMetaChip extends StatelessWidget {
  const IiOsMetaChip({required this.label, super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: palette.muted);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IiOsSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: palette.neutralTint,
        borderRadius: IiOsRadii.smAll,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: palette.muted),
            IiOsGap.hXxs,
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
