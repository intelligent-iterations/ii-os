import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show IiOsGap, IiOsIconSize, IiOsSpacing;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/classification_questions.dart';
import '../view_models/classification_form_editing.dart';

/// The criteria a question's type needs: choices, yes / no meanings, or the
/// six score levels.
class ClassificationCriteriaFields extends StatelessWidget {
  const ClassificationCriteriaFields({
    required this.question,
    required this.enabled,
    required this.editor,
    super.key,
  });

  final ClassificationQuestionDraft question;
  final bool enabled;
  final ClassificationFormEditing editor;

  @override
  Widget build(BuildContext context) {
    final key = question.key;
    return switch (question.kind) {
      ClassificationQuestionKind.choice => _ChoiceFields(
        question: question,
        enabled: enabled,
        editor: editor,
      ),
      ClassificationQuestionKind.yesNo => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ValueKey('$key-true'),
            initialValue: question.trueMeans,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Counts as yes (optional)',
            ),
            onChanged: (value) => editor.setTrueMeans(key, value),
          ),
          IiOsGap.vXs,
          TextFormField(
            key: ValueKey('$key-false'),
            initialValue: question.falseMeans,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Counts as no (optional)',
            ),
            onChanged: (value) => editor.setFalseMeans(key, value),
          ),
        ],
      ),
      ClassificationQuestionKind.score => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var level = 0; level < question.scoreLevels.length; level++)
            Padding(
              padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
              child: TextFormField(
                key: ValueKey('$key-level-$level'),
                initialValue: question.scoreLevels[level],
                enabled: enabled,
                decoration: InputDecoration(labelText: 'Level $level means'),
                onChanged: (value) => editor.setScoreLevel(key, level, value),
              ),
            ),
        ],
      ),
    };
  }
}

class _ChoiceFields extends StatelessWidget {
  const _ChoiceFields({
    required this.question,
    required this.enabled,
    required this.editor,
  });

  final ClassificationQuestionDraft question;
  final bool enabled;
  final ClassificationFormEditing editor;

  @override
  Widget build(BuildContext context) {
    final key = question.key;
    final options = question.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < options.length; index++)
          Padding(
            key: ValueKey('$key-${options[index].id}'),
            padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('$key-${options[index].id}-name'),
                    initialValue: options[index].name,
                    enabled: enabled,
                    decoration: InputDecoration(
                      labelText: 'Choice ${index + 1}',
                    ),
                    onChanged: (value) =>
                        editor.setOptionName(key, index, value),
                  ),
                ),
                IiOsGap.hXs,
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: ValueKey('$key-${options[index].id}-description'),
                    initialValue: options[index].description,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'When it applies (optional)',
                    ),
                    onChanged: (value) =>
                        editor.setOptionDescription(key, index, value),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove choice ${index + 1}',
                  onPressed:
                      enabled &&
                          options.length > ClassificationLimits.minChoices
                      ? () => editor.removeOption(key, index)
                      : null,
                  icon: const Icon(LucideIcons.x, size: IiOsIconSize.sm),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed:
                enabled && options.length < ClassificationLimits.maxChoices
                ? () => editor.addOption(key)
                : null,
            icon: const Icon(LucideIcons.plus, size: IiOsIconSize.sm),
            label: const Text('Add choice'),
          ),
        ),
      ],
    );
  }
}
