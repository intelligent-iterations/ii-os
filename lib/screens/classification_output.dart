import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show GenerationPhase, GenerationSlot, IiOsGap, IiOsMotion;

import '../view_models/classification_view_model.dart';
import '../widgets/classification_results.dart';

/// The output region: idle, working, the verified answers, or the failure,
/// always in the same place on the page.
class ClassificationOutput extends StatelessWidget {
  const ClassificationOutput({required this.viewModel, super.key});

  final ClassificationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: IiOsMotion.of(context, IiOsMotion.base),
      child: switch (viewModel.phase) {
        ClassificationRunPhase.idle => const GenerationSlot(
          key: ValueKey('classification-idle'),
          phase: GenerationPhase.idle,
          idleHint: 'Answers and their probabilities will appear here',
          aspectRatio: 4 / 3,
        ),
        ClassificationRunPhase.submitting => const GenerationSlot(
          key: ValueKey('classification-submitting'),
          phase: GenerationPhase.working,
          workingLabel: 'Starting the classification run\u2026',
          aspectRatio: 4 / 3,
        ),
        ClassificationRunPhase.running => const GenerationSlot(
          key: ValueKey('classification-running'),
          phase: GenerationPhase.working,
          workingLabel:
              'Running on your GPU host. The model loads first, so the first '
              'answer takes a minute or two.',
          aspectRatio: 4 / 3,
        ),
        ClassificationRunPhase.paused => Column(
          key: const ValueKey('classification-paused'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GenerationSlot(
              phase: GenerationPhase.idle,
              idleHint:
                  'Still running on your GPU host. This page stopped checking '
                  'after ${classificationWatchCeiling.inMinutes} minutes; the '
                  'run continues and its result is kept.',
              aspectRatio: 4 / 3,
            ),
            IiOsGap.vSm,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('classification-keep-watching'),
                onPressed: viewModel.resumeWatching,
                child: const Text('Keep watching'),
              ),
            ),
          ],
        ),
        ClassificationRunPhase.reading => const GenerationSlot(
          key: ValueKey('classification-reading'),
          phase: GenerationPhase.working,
          workingLabel: 'Checking the result\u2026',
          aspectRatio: 4 / 3,
        ),
        ClassificationRunPhase.failed => GenerationSlot(
          key: const ValueKey('classification-failed'),
          phase: GenerationPhase.failed,
          failureMessage:
              viewModel.failureMessage ?? 'The classification did not finish.',
          onRetry: viewModel.canSubmit ? viewModel.submit : null,
          aspectRatio: 4 / 3,
        ),
        ClassificationRunPhase.completed => ClassificationResults(
          key: const ValueKey('classification-results'),
          decisions: viewModel.decisions!,
        ),
      },
    );
  }
}
