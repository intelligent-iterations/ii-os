import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/creative_model_guide.dart';
import '../models/models.dart';
import 'model_choice_cards.dart';

/// The model choice, made first and made on the merits.
///
/// The workspace catalog can offer several checkpoints for the same job, and
/// which one to pick is the most consequential decision on a generation page --
/// it is also the one a `Workflow` dropdown of `name · repository` gives a
/// person no way to make. Each option gets a sentence saying what it is for.
class ModelChoice extends StatelessWidget {
  const ModelChoice({
    required this.templates,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
    this.label = 'Model',
    super.key,
  });

  final List<WorkflowTemplateModel> templates;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onSelected;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: IiOsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          IiOsGap.vXs,
          if (templates.length == 1)
            _SingleModel(template: templates.first)
          else
            ModelChoiceCards(
              templates: templates,
              selectedId: selectedId,
              enabled: enabled,
              onSelected: onSelected,
            ),
        ],
      ),
    );
  }
}

/// One available model is a fact about the page, not a decision on it.
///
/// A single card with a selection mark invites a choice that does not exist.
/// This still says which model will run and what it is for, which is the half
/// of the card that was carrying its weight.
class _SingleModel extends StatelessWidget {
  const _SingleModel({required this.template});

  final WorkflowTemplateModel template;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    final guide = creativeModelGuide(template);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(guide.icon, size: IiOsIconSize.md, color: palette.brand.text),
        IiOsGap.hXs,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(template.model, style: text.titleSmall),
              Text(
                guide.summary,
                style: text.bodySmall?.copyWith(color: palette.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
