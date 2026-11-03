import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/spacing.dart';
import 'empty_state.dart';

/// The first-load surface for a page or panel.
///
/// Show this only while there is nothing to show yet. Gate it on the data being
/// empty, never on a busy flag alone -- a background refresh that replaces
/// content the operator is already reading is a regression, not a loading
/// state. Use [RefreshingStrip] for that case instead.
///
/// ```dart
/// if (viewModel.isBusy && viewModel.items.isEmpty) return const LoadingSurface();
/// ```
class LoadingSurface extends StatelessWidget {
  const LoadingSurface({this.label, super.key});

  /// What is being loaded, announced to screen readers.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final message = label ?? 'Loading';
    return Semantics(
      label: message,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxxl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              if (label != null) ...[
                IiOsGap.vSm,
                ExcludeSemantics(
                  child: Text(
                    label!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The failed-load surface, with the recovery action in the same place the
/// content would have been.
class ErrorSurface extends StatelessWidget {
  const ErrorSurface({
    required this.title,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Retry',
    this.secondaryActions = const [],
    this.disabledReason,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;
  final List<Widget> secondaryActions;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyState(
          title: title,
          message: message,
          icon: LucideIcons.triangleAlert,
          action: Wrap(
            spacing: IiOsSpacing.sm,
            runSpacing: IiOsSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(onPressed: onRetry, child: Text(retryLabel)),
              ...secondaryActions,
            ],
          ),
        ),
        if (disabledReason case final reason?) ...[
          IiOsGap.vXs,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: IiOsSpacing.md),
            child: Text(
              reason,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// A quiet strip reporting a refresh happening *behind* content that is already
/// on screen, so a background reload has an affordance to use instead of a
/// full-surface spinner.
class RefreshingStrip extends StatelessWidget {
  const RefreshingStrip({this.label = 'Refreshing\u2026', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: IiOsSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            IiOsGap.hXs,
            ExcludeSemantics(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
