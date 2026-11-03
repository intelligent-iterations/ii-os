import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        GenerationPhase,
        GenerationSlot,
        GenerationWorkspace,
        GhostModeControl,
        IiOsGap,
        IiOsMotion;
import 'package:stacked/stacked.dart';

import '../repositories/job_repository.dart';
import '../repositories/generation_history_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../services/source_asset_uploader.dart';
import '../services/verified_artifact_media.dart';
import '../models/generation_history.dart';
import '../state/app_controller.dart';
import '../view_models/narration_generation_view_model.dart';
import '../widgets/common.dart';
import '../widgets/job_submission_result.dart';
import '../widgets/model_choice.dart';
import '../widgets/runtime_estimate_notice.dart';
import '../widgets/workflow_unavailable_notice.dart';
import 'narration_generation_form.dart';

class NarrationGenerationScreen extends StatelessWidget {
  const NarrationGenerationScreen({
    required this.controller,
    this.templateRepository,
    this.jobRepository,
    this.promptEnhancementRepository,
    this.ghostMode = false,
    this.onGhostModeChanged,
    super.key,
  });

  final AppController controller;
  final WorkflowTemplateRepository? templateRepository;
  final JobRepository? jobRepository;
  final PromptEnhancementRepository? promptEnhancementRepository;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<NarrationGenerationViewModel>.reactive(
      viewModelBuilder: _viewModel,
      onViewModelReady: (viewModel) => viewModel.load(),
      builder: (context, viewModel, _) {
        viewModel.setGhostMode(ghostMode);
        return PageFrame(
          title: 'Narration',
          subtitle: 'Text-to-speech through your workspace workflow',
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
              ModelChoice(
                label: 'Voice engine',
                templates: viewModel.templates,
                selectedId: viewModel.selectedTemplate?.id,
                enabled: !viewModel.submitting,
                onSelected: viewModel.selectTemplate,
              ),
              if (viewModel.showsUnavailableNotice)
                WorkflowUnavailableNotice(
                  template: viewModel.selectedTemplate,
                  fallbackReason: 'No enabled narration workflow is available.',
                ),
              if (viewModel.runtimeEstimate case final estimate?) ...[
                RuntimeEstimateNotice(estimate: estimate),
                IiOsGap.vMd,
              ],
              GenerationWorkspace(
                form: NarrationGenerationForm(
                  key: ValueKey('narration-form-ghost-$ghostMode'),
                  canSubmit: viewModel.canSubmit,
                  submitting: viewModel.submitting,
                  onUploadVoiceReference: viewModel.uploadVoiceReference,
                  history: _history,
                  loadLibraryPreview: _loadLibraryPreview,
                  readLibraryMedia: _readLibraryMedia,
                  promptEnhance: viewModel.narrationBinding,
                  onSubmit:
                      ({
                        required text,
                        required voiceModel,
                        required language,
                        required seed,
                        voiceReferenceAssetId,
                        voiceCloneConsent = false,
                      }) => _submit(
                        context,
                        viewModel,
                        text: text,
                        voiceModel: voiceModel,
                        language: language,
                        seed: seed,
                        voiceReferenceAssetId: voiceReferenceAssetId,
                        voiceCloneConsent: voiceCloneConsent,
                      ),
                ),
                preview: _NarrationPreviewPane(
                  controller: controller,
                  viewModel: viewModel,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  GenerationHistoryRepository get _history => controller.media.history(
    workspaceId: controller.workspace!.id,
    retentionDays: controller.workspace!.artifactStorage?.retentionDays ?? 30,
  );

  Future<VerifiedArtifactMedia> _loadLibraryPreview(HistoryEntryModel entry) =>
      controller.readVerifiedArtifact(
        workspaceId: controller.workspace!.id,
        jobId: entry.jobId,
        artifact: entry.previewArtifact ?? entry.artifact,
      );

  Future<VerifiedArtifactMedia> _readLibraryMedia(HistoryEntryModel entry) =>
      controller.readVerifiedArtifact(
        workspaceId: controller.workspace!.id,
        jobId: entry.jobId,
        artifact: entry.artifact,
      );

  NarrationGenerationViewModel _viewModel() => NarrationGenerationViewModel(
    templates:
        templateRepository ?? WorkflowTemplateApiRepository(controller.api),
    jobs: jobRepository ?? JobApiRepository(controller.api),
    promptEnhancements:
        promptEnhancementRepository ??
        PromptEnhancementApiRepository(controller.api),
    workspaceId: controller.workspace!.id,
    voiceReferenceUploader: SourceAssetUploader(controller.api).upload,
    expectedBucket: controller.connection?.bucket ?? '',
    ghostMode: ghostMode,
    onSubmitted: controller.refreshDashboard,
  );

  Future<void> _submit(
    BuildContext context,
    NarrationGenerationViewModel viewModel, {
    required String text,
    required String voiceModel,
    required String language,
    required String seed,
    String? voiceReferenceAssetId,
    bool voiceCloneConsent = false,
  }) async {
    final job = await viewModel.submit(
      text: text,
      voiceModel: voiceModel,
      language: language,
      seed: seed,
      voiceReferenceAssetId: voiceReferenceAssetId,
      voiceCloneConsent: voiceCloneConsent,
    );
    if (job != null || !context.mounted) return;
    final error = viewModel.modelError;
    if (error != null) showFailure(context, error as Object);
  }
}

class _NarrationPreviewPane extends StatelessWidget {
  const _NarrationPreviewPane({
    required this.controller,
    required this.viewModel,
  });

  final AppController controller;
  final NarrationGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: IiOsMotion.of(context, IiOsMotion.base),
      child: switch (true) {
        _ when viewModel.submittedJob != null => JobSubmissionResult(
          key: const ValueKey('narration-result'),
          controller: controller,
          result: viewModel.submittedJob!,
          title: 'Narration submitted',
          mediaKind: GeneratedMediaKind.audio,
          mediaLabel: 'narration',
        ),
        _ when viewModel.submitting => const GenerationSlot(
          key: ValueKey('narration-working'),
          phase: GenerationPhase.working,
          workingLabel: 'Submitting narration generation\u2026',
          aspectRatio: 3,
        ),
        _ => const GenerationSlot(
          key: ValueKey('narration-idle'),
          phase: GenerationPhase.idle,
          idleHint: 'Your narration will appear here',
          aspectRatio: 3,
        ),
      },
    );
  }
}
