part of 'image_edit_panel.dart';

/// The image-edit result pane: reserved, working, or the arrived edit(s).
///
/// Comparing models produces more than one result card at once, so unlike the
/// other generation screens this can't collapse to a single [GenerationSlot]
/// once a job exists -- it keeps the existing [ImageEditSubmissionResults] /
/// [ImageEditGenerationLoading] widgets, which already render one card per
/// model, and only reserves [GenerationSlot] for the idle state before
/// anything has been launched.
class _ImageEditPreviewPane extends StatelessWidget {
  const _ImageEditPreviewPane({
    required this.controller,
    required this.submissions,
    required this.busy,
    required this.enabledTemplates,
    required this.useAll,
    required this.aspectRatio,
    required this.busyLabel,
  });

  final AppController controller;
  final List<ImageEditSubmission> submissions;
  final bool busy;
  final List<WorkflowTemplateModel> enabledTemplates;
  final bool useAll;
  final double aspectRatio;
  final String busyLabel;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: IiOsMotion.of(context, IiOsMotion.base),
      child: switch (true) {
        _ when submissions.isNotEmpty => SingleChildScrollView(
          key: const ValueKey('image-edit-results'),
          child: ImageEditSubmissionResults(
            controller: controller,
            submissions: submissions,
          ),
        ),
        _ when busy => SingleChildScrollView(
          key: const ValueKey('image-edit-working'),
          child: ImageEditGenerationLoading(
            templates: enabledTemplates,
            useAll: useAll,
            aspectRatio: aspectRatio,
            label: busyLabel,
          ),
        ),
        _ => GenerationSlot(
          key: const ValueKey('image-edit-idle'),
          phase: GenerationPhase.idle,
          idleHint: 'Your edited image will appear here',
          aspectRatio: aspectRatio,
        ),
      },
    );
  }
}
