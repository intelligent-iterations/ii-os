import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// One permission to change in another system's settings.
final class PermissionChange {
  const PermissionChange({
    required this.name,
    required this.section,
    required this.currentValue,
    required this.requiredValue,
    this.reason = '',
  });

  /// The permission's name in the other system, spelled the way it is there.
  final String name;

  /// Where it lives in that system, so it can be found without hunting.
  final String section;

  final String currentValue;
  final String requiredValue;

  /// What this permission buys the person granting it, in their terms.
  ///
  /// Granting access to your own code is a decision, not a chore. A row that
  /// says only "Issues: none -> Read and write" asks someone to widen access
  /// without telling them what it is for, which earns either a refusal or an
  /// unread approval. Neither is consent.
  final String reason;
}

/// Exact settings to change elsewhere, with what each one is for.
class PermissionChangeGuide extends StatelessWidget {
  const PermissionChangeGuide({
    required this.changes,
    required this.steps,
    super.key,
  });

  final List<PermissionChange> changes;

  /// What to do once the values are set, in order.
  final List<String> steps;

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
              'Change this -> to this',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            IiOsGap.vSm,
            for (final change in changes) ...[
              _PermissionChangeRow(change: change),
              if (change != changes.last) IiOsGap.vXs,
            ],
            if (steps.isNotEmpty) ...[
              IiOsGap.vMd,
              const Divider(height: IiOsSpacing.xxs),
              IiOsGap.vMd,
              Text(
                'Then do this',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              IiOsGap.vXs,
              for (var index = 0; index < steps.length; index++)
                _Instruction(number: index + 1, text: steps[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionChangeRow extends StatelessWidget {
  const _PermissionChangeRow({required this.change});

  final PermissionChange change;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label:
          '${change.name}: change ${change.currentValue} to '
          '${change.requiredValue}'
          '${change.reason.isEmpty ? '' : ', ${change.reason}'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: IiOsColors.canvas,
          borderRadius: IiOsRadii.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                change.name,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              IiOsGap.vXxs,
              Text(change.section, style: textTheme.bodySmall),
              IiOsGap.vXs,
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: IiOsSpacing.xs,
                runSpacing: IiOsSpacing.xxs,
                children: [
                  Text(change.currentValue),
                  Text(
                    '->',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    change.requiredValue,
                    style: textTheme.bodyMedium?.copyWith(
                      color: IiOsColors.green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (change.reason.isNotEmpty) ...[
                IiOsGap.vXs,
                Text(change.reason, style: textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$number.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        IiOsGap.hXs,
        Expanded(child: Text(text)),
      ],
    ),
  );
}
