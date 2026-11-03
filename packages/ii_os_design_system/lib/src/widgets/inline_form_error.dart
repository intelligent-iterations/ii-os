import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/colors.dart';
import '../tokens/icons.dart';
import '../tokens/spacing.dart';

/// A validation or submission failure reported next to the field that caused
/// it, rather than in a snackbar that disappears before it is read.
///
/// Renders nothing when [message] is null, so a form can hold one of these in
/// its layout permanently instead of conditionally inserting a widget and
/// shifting everything below it.
///
/// This is the inline counterpart to `ErrorSurface`: use that when the whole
/// surface failed to load, and this when the surface is fine and one action
/// was rejected.
class InlineFormError extends StatelessWidget {
  const InlineFormError({required this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: IiOsSpacing.sm),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.circleAlert,
              size: IiOsIconSize.sm,
              color: IiOsColors.red,
            ),
            IiOsGap.hXs,
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: IiOsColors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
