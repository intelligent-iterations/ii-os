import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show IiOsGap, IiOsIconSize, InlineFormError;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/classification_questions.dart';
import '../view_models/classification_view_model.dart';
import 'classification_question_card.dart';

/// The text to classify, its questions, and the launch control.
class ClassificationForm extends StatelessWidget {
  const ClassificationForm({required this.viewModel, super.key});

  final ClassificationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final editable = !viewModel.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('classification-state'),
          initialValue: viewModel.stateText,
          enabled: editable,
          minLines: 4,
          maxLines: 10,
          maxLength: ClassificationLimits.maxStateChars,
          decoration: const InputDecoration(
            labelText: 'Text to classify',
            helperText:
                'The model reads this once and answers every question about '
                'it.',
            alignLabelWithHint: true,
          ),
          onChanged: viewModel.setStateText,
        ),
        IiOsGap.vMd,
        for (final question in viewModel.questions) ...[
          ClassificationQuestionCard(
            key: ValueKey(question.key),
            question: question,
            issue: viewModel.issueFor(question.key),
            enabled: editable,
            canRemove: viewModel.questions.length > 1,
            editor: viewModel,
          ),
          IiOsGap.vSm,
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('classification-add-question'),
            onPressed: editable && viewModel.canAddQuestion
                ? viewModel.addQuestion
                : null,
            icon: const Icon(LucideIcons.plus, size: IiOsIconSize.sm),
            label: const Text('Add question'),
          ),
        ),
        IiOsGap.vMd,
        _LaunchRow(viewModel: viewModel),
      ],
    );
  }
}

class _LaunchRow extends StatelessWidget {
  const _LaunchRow({required this.viewModel});

  final ClassificationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineFormError(message: viewModel.launchBlockedReason),
        IiOsGap.vXs,
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('classification-launch'),
            onPressed: viewModel.canSubmit ? viewModel.submit : null,
            icon: const Icon(LucideIcons.play, size: IiOsIconSize.sm),
            label: Text(viewModel.running ? 'Classifying\u2026' : 'Classify'),
          ),
        ),
      ],
    );
  }
}
