import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart' show IiOsPalette;

import '../models/github_setup_copy.dart';
import '../models/github_setup_readiness.dart';
import '../theme/ii_os_tokens.dart';

/// The one setup task standing between this repository and a queued ticket.
///
/// One blocker, named the way the setup wizard names it, with the step that
/// clears it. The rest stay a count so the reader always has one next action.
class WorkshopNextSetupTask extends StatelessWidget {
  const WorkshopNextSetupTask({
    required this.blocker,
    required this.remaining,
    super.key,
  });

  final GitHubSetupCheckModel blocker;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(IiOsRadii.md),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Next: ${setupTaskTitle(blocker)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            IiOsGap.vXxs,
            Text(
              setupTaskExplanation(blocker),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vXxs,
            Text(
              remaining > 0
                  ? 'In \u201c${setupStepTitleFor(blocker)}\u201d in agent setup, with $remaining more after it.'
                  : 'In \u201c${setupStepTitleFor(blocker)}\u201d in agent setup.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
