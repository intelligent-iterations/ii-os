import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/colors.dart';
import '../tokens/icons.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// A setup step the product is deliberately not allowed to perform, shown with
/// the exact command that completes it.
///
/// Some gates are only meaningful because software cannot pass them by itself:
/// a marker proving a human reviewed code before it gains authority is worth
/// nothing if the thing being authorised can mint it. That makes the copyable
/// command the whole of the user experience. Without it the step reads as an
/// unexplained wall, and a refresh button is the cruellest possible affordance
/// to offer next to it.
class ReviewedCommitGuide extends StatelessWidget {
  const ReviewedCommitGuide({
    required this.subject,
    required this.marker,
    required this.command,
    this.onCopied,
    super.key,
  });

  /// What the marker is created on, named the way the reader knows it.
  final String subject;

  /// The exact marker name, shown so it can be recognised once it exists.
  final String marker;

  /// The exact command that creates it. Empty renders prose guidance only.
  final String command;

  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IiOsColors.surface,
        border: Border.all(color: IiOsColors.border),
        borderRadius: IiOsRadii.lgAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Run this once',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            IiOsGap.vXs,
            Text(
              command.isEmpty
                  ? 'Create the marker on the current commit of $subject.'
                  : 'From a clean checkout of $subject:',
              style: textTheme.bodyMedium,
            ),
            if (command.isNotEmpty) ...[
              IiOsGap.vSm,
              _CommandBlock(command: command, onCopied: onCopied),
            ],
            if (marker.isNotEmpty) ...[
              IiOsGap.vSm,
              Text('Marker: $marker', style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.command, this.onCopied});

  final String command;
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: IiOsColors.canvas,
      borderRadius: IiOsRadii.mdAll,
    ),
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          IiOsGap.hXs,
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              onCopied?.call();
            },
            icon: const Icon(LucideIcons.copy, size: IiOsIconSize.md),
            tooltip: 'Copy the command',
          ),
        ],
      ),
    ),
  );
}
