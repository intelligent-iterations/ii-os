import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// One model-specific recommendation in a [PromptingGuideContent] surface.
final class PromptingGuideSection {
  const PromptingGuideSection({required this.title, required this.body});

  final String title;
  final String body;
}

/// Readable model guidance that can be placed in a dialog or inline panel.
class PromptingGuideContent extends StatelessWidget {
  const PromptingGuideContent({
    required this.summary,
    required this.sections,
    required this.promptTemplate,
    super.key,
  });

  final String summary;
  final List<PromptingGuideSection> sections;
  final String promptTemplate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(summary, style: textTheme.bodyLarge),
        IiOsGap.vLg,
        for (final section in sections) ...[
          Text(
            section.title,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          IiOsGap.vXxs,
          Text(section.body, style: textTheme.bodyMedium),
          if (section != sections.last) IiOsGap.vMd,
        ],
        IiOsGap.vLg,
        Text(
          'Starter structure',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        IiOsGap.vXs,
        DecoratedBox(
          decoration: BoxDecoration(
            color: IiOsColors.canvas,
            border: Border.all(color: IiOsColors.border),
            borderRadius: IiOsRadii.mdAll,
          ),
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.sm),
            child: SelectableText(
              promptTemplate,
              style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}
