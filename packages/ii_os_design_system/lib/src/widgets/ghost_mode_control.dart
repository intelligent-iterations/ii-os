import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/palette.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// Makes ephemeral generation an explicit, readable choice.
///
/// The enabled copy stays visible because closing the browser can discard the
/// only copy of a Ghost result. A tooltip carries the longer retention warning
/// without making every generation header taller.
class GhostModeControl extends StatelessWidget {
  const GhostModeControl({
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final detail = enabled
        ? 'Download before closing this tab'
        : 'Save generations to workspace history';
    final warning = enabled
        ? 'Nothing is added to history. Keep this tab open and download the '
              'result\u2014closing it discards your only copy.'
        : 'Generations are saved to workspace history.';
    return Tooltip(
      message: warning,
      child: MergeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: enabled ? palette.accent.container : palette.surface,
            border: Border.all(
              color: enabled ? palette.accent.text : palette.borderStrong,
            ),
            borderRadius: IiOsRadii.mdAll,
          ),
          child: Padding(
            padding: const EdgeInsets.only(
              left: IiOsSpacing.sm,
              right: IiOsSpacing.xxs,
              top: IiOsSpacing.xxs,
              bottom: IiOsSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.ghost,
                  size: IiOsSpacing.md,
                  color: enabled ? palette.accent.text : palette.muted,
                ),
                IiOsGap.hXs,
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        enabled ? 'Ghost mode on' : 'Ghost mode',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IiOsGap.hXs,
                Switch(value: enabled, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
