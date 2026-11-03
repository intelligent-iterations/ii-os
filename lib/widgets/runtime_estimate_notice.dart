import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/runtime_estimate.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';

class RuntimeEstimateNotice extends StatelessWidget {
  const RuntimeEstimateNotice({required this.estimate, super.key});

  final RuntimeEstimateSnapshot estimate;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final details = estimate.baselineOutputSeconds > 0
        ? 'Estimated GPU generation time, scaled from an observed '
              '${estimate.baselineOutputSeconds}-second render. Queueing, '
              'setup, and uploads can add time.'
        : 'Estimated GPU generation time from an observed render. Queueing, '
              'setup, and uploads can add time.';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.brand.container,
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.clock3, size: 18, color: palette.brand.text),
            IiOsGap.hSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About ${estimate.durationLabel} on ${estimate.hardware}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  IiOsGap.vXxs,
                  Text(details, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
