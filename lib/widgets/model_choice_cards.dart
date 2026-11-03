import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/creative_model_guide.dart';
import '../models/models.dart';

/// The model cards, paired once the row is wide enough for two to stay readable
/// and stacked below that.
///
/// Laid out as explicit rows rather than a [Wrap] so two cards side by side are
/// the same height. A wrapped run sizes each child to its own text, and a row
/// of cards with different bottom edges reads as a rendering mistake rather
/// than as a set of equals.
class ModelChoiceCards extends StatelessWidget {
  const ModelChoiceCards({
    required this.templates,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final List<WorkflowTemplateModel> templates;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= IiOsBreakpoints.pairedFields
            ? 2
            : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < templates.length; start += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) IiOsGap.hXs,
                        Expanded(
                          child: start + column < templates.length
                              ? _ModelCard(
                                  template: templates[start + column],
                                  selected:
                                      templates[start + column].id ==
                                      selectedId,
                                  enabled: enabled,
                                  onSelected: onSelected,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.template,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final WorkflowTemplateModel template;
  final bool selected;
  final bool enabled;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final guide = creativeModelGuide(template);
    final available = enabled && template.enabled;
    return IiOsChoiceCard(
      title: template.model,
      description: guide.summary,
      meta: creativeModelFacts(template),
      icon: guide.icon,
      selected: selected,
      unavailableReason: template.enabled ? '' : template.disabledReason,
      onSelected: available ? () => onSelected(template.id) : null,
    );
  }
}
