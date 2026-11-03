import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/image_edit_selection.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import 'job_submission_result.dart';

class ImageEditSubmissionResults extends StatelessWidget {
  const ImageEditSubmissionResults({
    required this.controller,
    required this.submissions,
    super.key,
  });

  final AppController controller;
  final List<ImageEditSubmission> submissions;

  @override
  Widget build(BuildContext context) {
    final successes = submissions.where((item) => item.succeeded).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          successes == submissions.length
              ? '$successes model${successes == 1 ? '' : 's'} submitted'
              : '$successes of ${submissions.length} models submitted',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IiOsGap.vXs,
        for (var index = 0; index < submissions.length; index++) ...[
          if (submissions[index].result case final result?)
            JobSubmissionResult(
              controller: controller,
              result: result,
              title: '${submissions[index].template.model} submitted',
              mediaKind: GeneratedMediaKind.image,
            )
          else
            _FailureCard(submission: submissions[index]),
          if (index < submissions.length - 1) IiOsGap.vXs,
        ],
      ],
    );
  }
}

class ImageEditGenerationLoading extends StatelessWidget {
  const ImageEditGenerationLoading({
    required this.templates,
    required this.useAll,
    required this.aspectRatio,
    required this.label,
    super.key,
  });

  final List<WorkflowTemplateModel> templates;
  final bool useAll;
  final double aspectRatio;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < (useAll ? templates.length : 1); index++) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.md),
            child: GeneratedMediaLoadingSurface(
              kind: GeneratedMediaKind.image,
              aspectRatio: aspectRatio,
              label: useAll
                  ? 'Preparing ${templates[index].model}\u2026'
                  : '$label\u2026',
            ),
          ),
        ),
        if (useAll && index < templates.length - 1) IiOsGap.vXs,
      ],
    ],
  );
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.submission});

  final ImageEditSubmission submission;

  @override
  Widget build(BuildContext context) {
    final message = submission.error.toString().replaceFirst(
      'ApiFailure: ',
      '',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.circleX, color: IiOsColors.red, size: 20),
            IiOsGap.hSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${submission.template.model} failed',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IiOsGap.vXxs,
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
