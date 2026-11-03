import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/image_workflow_capabilities.dart';
import '../repositories/job_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../repositories/source_asset_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../services/picked_media_reader.dart';
import '../state/app_controller.dart';
import '../view_models/image_generation_view_model.dart';
import '../widgets/common.dart';
import '../widgets/image_generation_form.dart';
import '../widgets/job_submission_result.dart';
import '../widgets/media_picker.dart';
import '../widgets/model_choice.dart';
import '../widgets/runtime_estimate_notice.dart';
import '../widgets/source_image_field.dart';
import '../widgets/workflow_unavailable_notice.dart';

typedef _ImageGenerationSubmit =
    void Function({
      required String prompt,
      required String aspectRatio,
      required String seed,
    });

/// Reference implementation of the front-end rules in
/// `docs/ii-os-frontend.md` § Rules: the page is layout,
/// `ImageGenerationViewModel` holds the state, and the repositories own the
/// network.
class GenerateScreen extends StatelessWidget {
  const GenerateScreen({
    required this.controller,
    this.ghostMode = false,
    this.onGhostModeChanged,
    this.initialMode = ImageGenerationMode.prompt,
    this.initialTemplateId,
    this.onModeChanged,
    this.onTemplateChanged,
    this.templateRepository,
    super.key,
  });

  final AppController controller;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;
  final ImageGenerationMode initialMode;
  final String? initialTemplateId;
  final ValueChanged<ImageGenerationMode>? onModeChanged;
  final ValueChanged<String?>? onTemplateChanged;
  final WorkflowTemplateRepository? templateRepository;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ImageGenerationViewModel>.reactive(
      viewModelBuilder: () => ImageGenerationViewModel(
        templates:
            templateRepository ?? WorkflowTemplateApiRepository(controller.api),
        jobs: JobApiRepository(controller.api),
        sourceAssets: SourceAssetApiRepository(controller.api),
        promptEnhancements: PromptEnhancementApiRepository(controller.api),
        workspaceId: controller.workspace!.id,
        expectedBucket: controller.connection?.bucket ?? '',
        ghostMode: ghostMode,
        initialMode: initialMode,
        initialTemplateId: initialTemplateId,
        onSubmitted: controller.refreshDashboard,
      ),
      onViewModelReady: (viewModel) => viewModel.load(),
      builder: (context, viewModel, _) {
        viewModel.setGhostMode(ghostMode);
        return _GenerateScreenBody(
          controller: controller,
          viewModel: viewModel,
          ghostMode: ghostMode,
          onGhostModeChanged: onGhostModeChanged,
          onModeChanged: onModeChanged,
          onTemplateChanged: onTemplateChanged,
          onSelectReference: (index) =>
              _selectReference(context, viewModel, index),
          onSubmit: ({required prompt, required aspectRatio, required seed}) =>
              _submit(
                context,
                viewModel,
                prompt: prompt,
                aspectRatio: aspectRatio,
                seed: seed,
              ),
        );
      },
    );
  }

  Future<void> _selectReference(
    BuildContext context,
    ImageGenerationViewModel viewModel,
    int index,
  ) async {
    const images = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );
    final workspace = controller.workspace;
    if (workspace == null) return;
    final letter = String.fromCharCode(65 + index);
    final picked = await showMediaPicker(
      context: context,
      history: controller.media.history(
        workspaceId: workspace.id,
        retentionDays: workspace.artifactStorage?.retentionDays ?? 30,
      ),
      title: 'Choose image $letter',
      contentTypePrefix: 'image/',
      uploadTypes: const [images],
      maxUploadBytes: _maximumReferenceBytes,
      loadPreview: (entry) => controller.readVerifiedArtifact(
        workspaceId: workspace.id,
        jobId: entry.jobId,
        artifact: entry.previewArtifact ?? entry.artifact,
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      final selected = await readPickedMedia(
        picked,
        readLibrary: (entry) => controller.readVerifiedArtifact(
          workspaceId: workspace.id,
          jobId: entry.jobId,
          artifact: entry.artifact,
        ),
      );
      if (!viewModel.setReference(
        index,
        filename: selected.file.name,
        bytes: selected.bytes,
      )) {
        throw viewModel.modelError ??
            const FormatException('The reference image is invalid.');
      }
    } on Object catch (error) {
      if (context.mounted) showFailure(context, error);
    }
  }

  Future<void> _submit(
    BuildContext context,
    ImageGenerationViewModel viewModel, {
    required String prompt,
    required String aspectRatio,
    required String seed,
  }) async {
    final job = await viewModel.submit(
      prompt: prompt,
      aspectRatio: aspectRatio,
      seed: seed,
    );
    if (job != null || !context.mounted) return;
    final error = viewModel.modelError;
    if (error != null) showFailure(context, error as Object);
  }
}

class _GenerateScreenBody extends StatelessWidget {
  const _GenerateScreenBody({
    required this.controller,
    required this.viewModel,
    required this.ghostMode,
    required this.onGhostModeChanged,
    required this.onModeChanged,
    required this.onTemplateChanged,
    required this.onSelectReference,
    required this.onSubmit,
  });

  final AppController controller;
  final ImageGenerationViewModel viewModel;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;
  final ValueChanged<ImageGenerationMode>? onModeChanged;
  final ValueChanged<String?>? onTemplateChanged;
  final ValueChanged<int> onSelectReference;
  final _ImageGenerationSubmit onSubmit;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Create images',
      subtitle: 'Start from a description or guide the result with images.',
      actions: [
        if (onGhostModeChanged != null)
          GhostModeControl(
            key: const Key('generation-ghost-mode'),
            enabled: ghostMode,
            onChanged: onGhostModeChanged!,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CreationModeChoice(
            value: viewModel.mode,
            enabled: !viewModel.submitting,
            onChanged: (value) {
              viewModel.setMode(value);
              onModeChanged?.call(value);
            },
          ),
          IiOsGap.vMd,
          ModelChoice(
            templates: viewModel.templates,
            selectedId: viewModel.selectedTemplate?.id,
            enabled: !viewModel.submitting,
            onSelected: (value) {
              viewModel.selectTemplate(value);
              onTemplateChanged?.call(value);
            },
          ),
          if (viewModel.showsUnavailableNotice)
            WorkflowUnavailableNotice(
              template: viewModel.selectedTemplate,
              fallbackReason: 'No enabled image workflow is available.',
            ),
          _GenerationWorkspaceBody(
            controller: controller,
            viewModel: viewModel,
            onSelectReference: onSelectReference,
            onSubmit: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _GenerationWorkspaceBody extends StatelessWidget {
  const _GenerationWorkspaceBody({
    required this.controller,
    required this.viewModel,
    required this.onSelectReference,
    required this.onSubmit,
  });

  final AppController controller;
  final ImageGenerationViewModel viewModel;
  final ValueChanged<int> onSelectReference;
  final _ImageGenerationSubmit onSubmit;

  @override
  Widget build(BuildContext context) {
    return GenerationWorkspace(
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (viewModel.runtimeEstimate case final estimate?) ...[
            RuntimeEstimateNotice(estimate: estimate),
            IiOsGap.vSm,
          ],
          if (viewModel.mode == ImageGenerationMode.references) ...[
            _ReferenceInputs(
              viewModel: viewModel,
              enabled: !viewModel.submitting,
              onSelect: onSelectReference,
            ),
            IiOsGap.vSm,
          ],
          ImageGenerationForm(
            canSubmit: viewModel.canSubmit,
            submitting: viewModel.submitting,
            promptEnhance: viewModel.promptBinding,
            promptMaxLength:
                viewModel.selectedTemplate?.inputs['prompt']?.maxLength ?? 4000,
            aspectRatios: viewModel.aspectRatios,
            submitLabel: viewModel.busyLabel,
            onSubmit: onSubmit,
          ),
        ],
      ),
      preview: _ImageGenerationPreview(
        controller: controller,
        viewModel: viewModel,
      ),
    );
  }
}

class _CreationModeChoice extends StatelessWidget {
  const _CreationModeChoice({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ImageGenerationMode value;
  final bool enabled;
  final ValueChanged<ImageGenerationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<ImageGenerationMode>(
        segments: const [
          ButtonSegment(
            value: ImageGenerationMode.prompt,
            icon: Icon(LucideIcons.textCursorInput, size: 17),
            label: Text('From text'),
          ),
          ButtonSegment(
            value: ImageGenerationMode.references,
            icon: Icon(LucideIcons.images, size: 17),
            label: Text('Use references'),
          ),
        ],
        selected: {value},
        onSelectionChanged: enabled
            ? (selection) => onChanged(selection.single)
            : null,
      ),
    );
  }
}

class _ReferenceInputs extends StatelessWidget {
  const _ReferenceInputs({
    required this.viewModel,
    required this.enabled,
    required this.onSelect,
  });

  final ImageGenerationViewModel viewModel;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reference images',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IiOsGap.vXxs,
            Text(
              'Image A anchors the result. Add B or C only when the prompt '
              'needs another subject, object, style, or setting.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (
              var index = 0;
              index < viewModel.maximumReferenceImages;
              index++
            ) ...[
              IiOsGap.vMd,
              SourceImageField(
                title: index == 0
                    ? 'Image A · main reference'
                    : 'Image ${String.fromCharCode(65 + index)} · supporting reference',
                selectLabel: 'Choose image ${String.fromCharCode(65 + index)}',
                file: switch (viewModel.references[index]) {
                  final reference? => XFile.fromData(
                    reference.bytes,
                    name: reference.filename,
                  ),
                  _ => null,
                },
                bytes: viewModel.references[index]?.bytes,
                busy: viewModel.submitting,
                enabled: enabled,
                onSelect: () => onSelect(index),
                onClear: () => viewModel.removeReference(index),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageGenerationPreview extends StatelessWidget {
  const _ImageGenerationPreview({
    required this.controller,
    required this.viewModel,
  });

  final AppController controller;
  final ImageGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: IiOsMotion.of(context, IiOsMotion.base),
      child: switch (true) {
        _ when viewModel.submittedJob != null => JobSubmissionResult(
          key: const ValueKey('image-result'),
          controller: controller,
          result: viewModel.submittedJob!,
          mediaKind: GeneratedMediaKind.image,
        ),
        _ when viewModel.submitting => GenerationSlot(
          key: ValueKey('image-working'),
          phase: GenerationPhase.working,
          workingLabel: '${viewModel.busyLabel}\u2026',
        ),
        _ => const GenerationSlot(
          key: ValueKey('image-idle'),
          phase: GenerationPhase.idle,
          idleHint: 'Your image will appear here',
        ),
      },
    );
  }
}

const _maximumReferenceBytes = 50 * 1024 * 1024;
