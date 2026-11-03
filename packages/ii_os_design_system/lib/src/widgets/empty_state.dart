import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// The "there is nothing here" surface, with the action that would change that
/// in the same place the content would have been.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    super.key,
    this.icon = LucideIcons.inbox,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: IiOsSpacing.xxxl,
        horizontal: IiOsSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Icon(icon, size: 28, color: IiOsColors.muted),
              IiOsGap.vSm,
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              IiOsGap.vXxs,
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (action != null) ...[IiOsGap.vMd, action!],
            ],
          ),
        ),
      ),
    );
  }
}
