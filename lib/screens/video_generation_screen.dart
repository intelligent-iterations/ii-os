import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        GenerationPhase,
        GenerationSlot,
        GenerationWorkspace,
        GhostModeControl,
        IiOsMotion;
import 'package:stacked/stacked.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/minimax_h3_generation_spec.dart';
import '../repositories/job_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../services/picked_media_reader.dart';
import '../repositories/source_asset_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../state/app_controller.dart';
import '../widgets/media_picker.dart';
import '../theme/ii_os_tokens.dart';
import '../view_models/video_generation_view_model.dart';
import '../widgets/common.dart';
import '../widgets/job_submission_result.dart';
import '../widgets/model_choice.dart';
import '../widgets/workflow_unavailable_notice.dart';
import 'video_generation_form_fields.dart';
import 'video_generation_settings.dart';

class VideoGenerationScreen extends StatelessWidget {
  const VideoGenerationScreen({
    required this.controller,
    this.templateRepository,
    this.jobRepository,
    this.promptEnhancementRepository,
    this.sourceAssetRepository,
    this.ghostMode = false,
    this.onGhostModeChanged,
    this.initialH3Mode,
    this.initialH3SourceAssetId,
    super.key,
  });

  final AppController controller;
  final WorkflowTemplateRepository? templateRepository;
  final JobRepository? jobRepository;
  final PromptEnhancementRepository? promptEnhancementRepository;
  final SourceAssetRepository? sourceAssetRepository;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;
  final MiniMaxH3GenerationMode? initialH3Mode;
  final String? initialH3SourceAssetId;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<VideoGenerationViewModel>.reactive(
      viewModelBuilder: () => VideoGenerationViewModel(
        templates:
            templateRepository ?? WorkflowTemplateApiRepository(controller.api),
        jobs: jobRepository ?? JobApiRepository(controller.api),
        promptEnhancements:
            promptEnhancementRepository ??
            PromptEnhancementApiRepository(controller.api),
        sourceAssets:
            sourceAssetRepository ?? SourceAssetApiRepository(controller.api),
        media: controller.media,
        workspaceId: controller.workspace!.id,
        expectedBucket: controller.connection?.bucket ?? '',
        ghostMode: ghostMode,
        initialH3Mode: initialH3Mode,
        initialH3SourceAssetId: initialH3SourceAssetId,
        onSubmitted: controller.refreshDashboard,
      ),
      onViewModelReady: (viewModel) => viewModel.load(),
      builder: (context, viewModel, _) {
        viewModel.setGhostMode(ghostMode);
        return PageFrame(
          title: 'Video generation',
          subtitle:
              'MiniMax H3 generation · LTX image to video · SeedVR2 upscaling',
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
              _VideoModelToggle(viewModel: viewModel),
              if (viewModel.showsUnavailableNotice)
                WorkflowUnavailableNotice(
                  template: viewModel.selectedTemplate,
                  fallbackReason: 'No enabled video workflow is available.',
                ),
              GenerationWorkspace(
                form: _VideoGenerationForm(
                  viewModel: viewModel,
                  controller: controller,
                ),
                preview: AnimatedSwitcher(
                  duration: IiOsMotion.of(context, IiOsMotion.base),
                  child: switch (true) {
                    _ when viewModel.submittedJob != null =>
                      JobSubmissionResult(
                        key: const ValueKey('video-result'),
                        controller: controller,
                        result: viewModel.submittedJob!,
                        mediaKind: GeneratedMediaKind.video,
                        mediaAspectRatio: viewModel.outputAspectRatio,
                        onRetry: viewModel.retryLastSubmission,
                      ),
                    _ when viewModel.submitting => GenerationSlot(
                      key: const ValueKey('video-working'),
                      phase: GenerationPhase.working,
                      workingLabel: '${viewModel.busyLabel}\u2026',
                      aspectRatio: viewModel.outputAspectRatio,
                    ),
                    _ => GenerationSlot(
                      key: const ValueKey('video-idle'),
                      phase: GenerationPhase.idle,
                      idleHint: 'Your video will appear here',
                      aspectRatio: viewModel.outputAspectRatio,
                    ),
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VideoModelToggle extends StatelessWidget {
  const _VideoModelToggle({required this.viewModel});

  final VideoGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ModelChoice(
      label: 'Video model',
      templates: viewModel.templates,
      selectedId: viewModel.selectedTemplate?.id,
      enabled: !viewModel.submitting,
      onSelected: viewModel.selectTemplate,
    );
  }
}

class _VideoGenerationForm extends StatefulWidget {
  const _VideoGenerationForm({
    required this.viewModel,
    required this.controller,
  });

  final VideoGenerationViewModel viewModel;
  final AppController controller;

  @override
  State<_VideoGenerationForm> createState() => _VideoGenerationFormState();
}

class _VideoGenerationFormState extends State<_VideoGenerationForm> {
  final _prompt = TextEditingController();
  XFile? _sourceFile;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VideoGenerationSourceFields(
              viewModel: viewModel,
              sourceFile: _sourceFile,
              onSelectImage: _selectImage,
              onSelectVideo: _selectVideo,
            ),
            VideoGenerationPromptFields(
              viewModel: viewModel,
              prompt: _prompt,
              onOpenPromptingGuide: _openPromptingGuideSource,
            ),
            IiOsGap.vSm,
            VideoGenerationSettings(viewModel: viewModel),
            IiOsGap.vSm,
            VideoGenerationSubmitButton(
              viewModel: viewModel,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectImage() async {
    const images = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );
    final controller = widget.controller;
    final workspace = controller.workspace;
    if (workspace == null) return;

    // The source can equally be something this workspace already made or a
    // file from the operator's machine. It only offered the second.
    final picked = await showMediaPicker(
      context: context,
      history: controller.media.history(
        workspaceId: workspace.id,
        retentionDays: workspace.artifactStorage?.retentionDays ?? 30,
      ),
      title: 'Source image',
      contentTypePrefix: 'image/',
      uploadTypes: const [images],
      maxUploadBytes: _maxSourceImageBytes,
      loadPreview: (entry) => controller.readVerifiedArtifact(
        workspaceId: workspace.id,
        jobId: entry.jobId,
        artifact: entry.previewArtifact ?? entry.artifact,
      ),
    );
    if (picked == null || !mounted) return;

    try {
      final selected = await readPickedMedia(
        picked,
        readLibrary: (entry) => controller.readVerifiedArtifact(
          workspaceId: workspace.id,
          jobId: entry.jobId,
          artifact: entry.artifact,
        ),
      );
      if (!widget.viewModel.setSource(
        filename: selected.file.name,
        bytes: selected.bytes,
      )) {
        throw widget.viewModel.modelError ??
            const FormatException('The source image is invalid.');
      }
      if (mounted) {
        setState(() => _sourceFile = selected.file);
      }
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _selectVideo() async {
    const videos = XTypeGroup(
      label: 'Videos',
      extensions: ['mp4', 'webm'],
      mimeTypes: ['video/mp4', 'video/webm'],
    );
    final controller = widget.controller;
    final workspace = controller.workspace;
    if (workspace == null) return;
    final picked = await showMediaPicker(
      context: context,
      history: controller.media.history(
        workspaceId: workspace.id,
        retentionDays: workspace.artifactStorage?.retentionDays ?? 30,
      ),
      title: 'Source video',
      contentTypePrefix: 'video/',
      uploadTypes: const [videos],
      maxUploadBytes: _maxSourceVideoBytes,
      loadPreview: (entry) => controller.readVerifiedArtifact(
        workspaceId: workspace.id,
        jobId: entry.jobId,
        artifact: entry.previewArtifact ?? entry.artifact,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final selected = await readPickedMedia(
        picked,
        readLibrary: (entry) => controller.readVerifiedArtifact(
          workspaceId: workspace.id,
          jobId: entry.jobId,
          artifact: entry.artifact,
        ),
      );
      if (!widget.viewModel.setSourceVideo(
        filename: selected.file.name,
        bytes: selected.bytes,
      )) {
        throw widget.viewModel.modelError ??
            const FormatException('The source video is invalid.');
      }
      if (mounted) setState(() => _sourceFile = selected.file);
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _openPromptingGuideSource(Uri source) async {
    final opened = await launchUrl(source, webOnlyWindowName: '_blank');
    if (!opened && mounted) {
      showFailure(context, StateError('Could not open the official guide.'));
    }
  }

  Future<void> _submit() async {
    final job = await widget.viewModel.submit(prompt: _prompt.text);
    if (job != null || !mounted) return;
    final error = widget.viewModel.modelError;
    if (error != null) showFailure(context, error as Object);
  }
}

const _maxSourceImageBytes = 50 * 1024 * 1024;
const _maxSourceVideoBytes = 512 * 1024 * 1024;
