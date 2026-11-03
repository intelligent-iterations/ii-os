import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens/icons.dart';
import '../tokens/widths.dart';
import 'prompting_guide_content.dart';

/// Opens concise, model-specific prompting advice without leaving the form.
class PromptingGuideButton extends StatelessWidget {
  const PromptingGuideButton({
    required this.title,
    required this.summary,
    required this.sections,
    required this.promptTemplate,
    this.onOpenSource,
    this.label = 'Prompting guide',
    this.sourceLabel = 'Read the official guide',
    super.key,
  });

  final String title;
  final String summary;
  final List<PromptingGuideSection> sections;
  final String promptTemplate;
  final Future<void> Function()? onOpenSource;
  final String label;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open $label',
      child: TextButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => _PromptingGuideDialog(
            title: title,
            summary: summary,
            sections: sections,
            promptTemplate: promptTemplate,
            onOpenSource: onOpenSource,
            sourceLabel: sourceLabel,
          ),
        ),
        icon: const Icon(LucideIcons.bookOpenText, size: IiOsIconSize.sm),
        label: Text(label),
      ),
    );
  }
}

class _PromptingGuideDialog extends StatelessWidget {
  const _PromptingGuideDialog({
    required this.title,
    required this.summary,
    required this.sections,
    required this.promptTemplate,
    required this.onOpenSource,
    required this.sourceLabel,
  });

  final String title;
  final String summary;
  final List<PromptingGuideSection> sections;
  final String promptTemplate;
  final Future<void> Function()? onOpenSource;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: IiOsWidths.prose),
        child: SingleChildScrollView(
          child: PromptingGuideContent(
            summary: summary,
            sections: sections,
            promptTemplate: promptTemplate,
          ),
        ),
      ),
      actions: [
        if (onOpenSource != null)
          TextButton.icon(
            onPressed: onOpenSource,
            icon: const Icon(LucideIcons.externalLink, size: IiOsIconSize.sm),
            label: Text(sourceLabel),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
