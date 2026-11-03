import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/ii_os_tokens.dart';
import 'model_choice.dart';

/// The image-edit model, plus the option to run the same edit through all of
/// them.
///
/// Which model to edit with is the same decision as which model to generate
/// with, so it is made the same way. What is particular here is the comparison
/// run: an edit is a judgement call, and seeing three answers side by side is
/// often faster than reasoning about which model would have been right.
class ImageEditModelPicker extends StatelessWidget {
  const ImageEditModelPicker({
    required this.templates,
    required this.selectedId,
    required this.useAll,
    required this.enabled,
    required this.onSelected,
    required this.onUseAllChanged,
    super.key,
  });

  final List<WorkflowTemplateModel> templates;
  final String? selectedId;
  final bool useAll;
  final bool enabled;
  final ValueChanged<String?> onSelected;
  final ValueChanged<bool> onUseAllChanged;

  @override
  Widget build(BuildContext context) {
    final enabledCount = templates.where((template) => template.enabled).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModelChoice(
          templates: templates,
          selectedId: selectedId,
          enabled: enabled && !useAll,
          onSelected: onSelected,
        ),
        if (enabledCount > 1)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: useAll,
            onChanged: enabled ? onUseAllChanged : null,
            title: const Text('Try every model'),
            subtitle: Text(
              'Run this edit through all $enabledCount and compare the results.',
            ),
          ),
        IiOsGap.vXs,
      ],
    );
  }
}
