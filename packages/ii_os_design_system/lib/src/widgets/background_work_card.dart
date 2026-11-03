import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/colors.dart';
import '../tokens/icons.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// Live state of long-running work, rendered where its result will land.
///
/// Work that takes minutes and finishes elsewhere -- a dispatched job, a remote
/// build -- has no natural place to show itself, so it usually gets a toast and
/// then nothing. The result is a surface that looks idle while it is busy,
/// which invites a second dispatch and makes a working run indistinguishable
/// from one that never started. Put this in the surface the result will replace.
class BackgroundWorkCard extends StatelessWidget {
  const BackgroundWorkCard({
    required this.running,
    required this.title,
    required this.detail,
    this.onFollow,
    this.followLabel = 'Follow the run',
    this.onRetry,
    this.retryLabel = 'Start it again',
    super.key,
  });

  /// Whether the work is still being watched. False renders the stopped-watching
  /// state, which is not the same as failure and must not claim to be.
  final bool running;

  final String title;
  final String detail;

  /// Opens wherever the work can be observed directly.
  final VoidCallback? onFollow;
  final String followLabel;

  /// Starts the same work over, for the stopped state.
  ///
  /// Without this the stopped state is a dead end: it tells the reader to go
  /// look in another system and then come back, and offers them nothing to do
  /// here. Runs that queue behind a busy runner, or fail for a reason that is
  /// explicitly retryable, both land here -- and in both cases starting again is
  /// the answer, not reading a log.
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = running ? IiOsColors.blue : IiOsColors.amber;
    final follow = onFollow;
    final retry = onRetry;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IiOsColors.surface,
        border: Border.all(color: color.withValues(alpha: 0.32)),
        borderRadius: IiOsRadii.lgAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (running)
                    const SizedBox.square(
                      dimension: IiOsIconSize.md,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      LucideIcons.circleAlert,
                      size: IiOsIconSize.md,
                      color: color,
                    ),
                  IiOsGap.hXs,
                  Expanded(
                    child: Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IiOsGap.vXs,
            Text(detail, style: textTheme.bodyMedium),
            if (follow != null || (!running && retry != null)) ...[
              IiOsGap.vSm,
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: IiOsSpacing.xs,
                  runSpacing: IiOsSpacing.xs,
                  children: [
                    if (!running && retry != null)
                      FilledButton.icon(
                        onPressed: retry,
                        icon: const Icon(
                          LucideIcons.refreshCw,
                          size: IiOsIconSize.md,
                        ),
                        label: Text(retryLabel),
                      ),
                    if (follow != null)
                      OutlinedButton.icon(
                        onPressed: follow,
                        icon: const Icon(
                          LucideIcons.externalLink,
                          size: IiOsIconSize.md,
                        ),
                        label: Text(followLabel),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
