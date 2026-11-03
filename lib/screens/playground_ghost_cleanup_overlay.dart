import 'package:flutter/material.dart';

import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class PlaygroundGhostCleanupOverlay extends StatelessWidget {
  const PlaygroundGhostCleanupOverlay({
    required this.content,
    required this.cleaning,
    required this.onRetry,
    super.key,
  });

  final Widget content;
  final bool cleaning;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: IiOsColors.red.withValues(alpha: .92),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IiOsSpacing.sm,
                vertical: IiOsSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Workspace cleanup needs a retry.',
                      style: IiOsTypography.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('ghost-cleanup-retry'),
                    onPressed: cleaning ? null : onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white70,
                    ),
                    child: Text(cleaning ? 'Deleting\u2026' : 'Delete now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
