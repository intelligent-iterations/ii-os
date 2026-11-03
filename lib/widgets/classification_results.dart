import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        IiOsDecisionDistribution,
        IiOsDecisionShare,
        IiOsGap,
        IiOsIconSize,
        IiOsMetaChip,
        IiOsPalette,
        IiOsSpacing;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/classification_decisions.dart';
import '../models/classification_presentation.dart';

/// Verified classification answers, one card per question, plus run facts.
class ClassificationResults extends StatelessWidget {
  const ClassificationResults({required this.decisions, super.key});

  final ClassificationDecisions decisions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final answer in decisions.answers) ...[
              _AnswerSection(view: viewOfAnswer(answer)),
              IiOsGap.vMd,
            ],
            if (decisions.run.stateTruncated) ...[
              const _TruncatedNotice(),
              IiOsGap.vSm,
            ],
            Wrap(
              spacing: IiOsSpacing.xs,
              runSpacing: IiOsSpacing.xs,
              children: [
                for (final fact in runFactsOf(decisions))
                  IiOsMetaChip(label: fact),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerSection extends StatelessWidget {
  const _AnswerSection({required this.view});

  final ClassificationAnswerView view;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(view.name, style: text.labelLarge),
            IiOsGap.hXs,
            Expanded(
              child: Text(
                view.verdict,
                style: text.titleMedium?.copyWith(color: palette.brand.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (view.confidence case final confidence?)
              Text(
                confidence,
                style: text.bodySmall?.copyWith(color: palette.muted),
              ),
          ],
        ),
        IiOsGap.vXs,
        IiOsDecisionDistribution(
          shares: [
            for (final share in view.shares)
              IiOsDecisionShare(
                label: share.label,
                probability: share.probability,
                chosen: share.chosen,
              ),
          ],
        ),
      ],
    );
  }
}

class _TruncatedNotice extends StatelessWidget {
  const _TruncatedNotice();

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Row(
      children: [
        Icon(
          LucideIcons.scissors,
          size: IiOsIconSize.sm,
          color: palette.warning.text,
        ),
        IiOsGap.hXs,
        Expanded(
          child: Text(
            'The text was longer than the model reads, so its middle was '
            'left out. Shorten it for an answer about all of it.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.warning.text),
          ),
        ),
      ],
    );
  }
}
