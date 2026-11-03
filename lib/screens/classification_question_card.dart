import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show IiOsGap, IiOsIconSize, IiOsSpacing, InlineFormError;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/classification_questions.dart';
import '../view_models/classification_form_editing.dart';
import 'classification_criteria_fields.dart';

/// One question: its answer key, type, wording, and type-specific criteria.
class ClassificationQuestionCard extends StatelessWidget {
  const ClassificationQuestionCard({
    required this.question,
    required this.issue,
    required this.enabled,
    required this.canRemove,
    required this.editor,
    super.key,
  });

  final ClassificationQuestionDraft question;
  final String? issue;
  final bool enabled;
  final bool canRemove;
  final ClassificationFormEditing editor;

  @override
  Widget build(BuildContext context) {
    final key = question.key;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('$key-name'),
                    initialValue: question.name,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'Answer key',
                      helperText: 'Lowercase, e.g. tone',
                    ),
                    onChanged: (value) => editor.renameQuestion(key, value),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove question',
                  onPressed: enabled && canRemove
                      ? () => editor.removeQuestion(key)
                      : null,
                  icon: const Icon(LucideIcons.trash2, size: IiOsIconSize.md),
                ),
              ],
            ),
            IiOsGap.vSm,
            SegmentedButton<ClassificationQuestionKind>(
              key: ValueKey('$key-kind'),
              segments: [
                for (final kind in ClassificationQuestionKind.values)
                  ButtonSegment(value: kind, label: Text(kind.label)),
              ],
              selected: {question.kind},
              showSelectedIcon: false,
              onSelectionChanged: enabled
                  ? (selection) => editor.setKind(key, selection.single)
                  : null,
            ),
            IiOsGap.vSm,
            TextFormField(
              key: ValueKey('$key-instructions'),
              initialValue: question.instructions,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Question',
                hintText: switch (question.kind) {
                  ClassificationQuestionKind.choice => 'What is the tone?',
                  ClassificationQuestionKind.yesNo => 'Is this about billing?',
                  ClassificationQuestionKind.score => 'How urgent is this?',
                },
              ),
              onChanged: (value) => editor.setInstructions(key, value),
            ),
            IiOsGap.vSm,
            ClassificationCriteriaFields(
              question: question,
              enabled: enabled,
              editor: editor,
            ),
            InlineFormError(message: issue),
          ],
        ),
      ),
    );
  }
}
