import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        GenerationPhase,
        GenerationSlot,
        GenerationWorkspace,
        GhostModeControl,
        IiOsMotion;
import 'package:stacked/stacked.dart';

import '../repositories/job_repository.dart';
import '../repositories/prompt_enhancement_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../state/app_controller.dart';
import '../view_models/song_generation_view_model.dart';
import '../widgets/common.dart';
import '../widgets/job_submission_result.dart';
import '../widgets/model_choice.dart';
import '../widgets/workflow_unavailable_notice.dart';
import 'song_generation_form.dart';

class SongGenerationScreen extends StatelessWidget {
  const SongGenerationScreen({
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
    return ViewModelBuilder<SongGenerationViewModel>.reactive(
      viewModelBuilder: () => SongGenerationViewModel(
        templates:
            templateRepository ?? WorkflowTemplateApiRepository(controller.api),
        jobs: jobRepository ?? JobApiRepository(controller.api),
        promptEnhancements:
            promptEnhancementRepository ??
            PromptEnhancementApiRepository(controller.api),
        workspaceId: controller.workspace!.id,
        ghostMode: ghostMode,
        onSubmitted: controller.refreshDashboard,
      ),
      onViewModelReady: (viewModel) => viewModel.load(),
      builder: (context, viewModel, _) {
        viewModel.setGhostMode(ghostMode);
        return PageFrame(
          title: 'Song generation',
          subtitle: 'ACE-Step 1.5 · lyrics-aware vocals and instrumental music',
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
                label: 'Song model',
                templates: viewModel.templates,
                selectedId: viewModel.selectedTemplate?.id,
                enabled: !viewModel.submitting,
                onSelected: viewModel.selectTemplate,
              ),
              if (viewModel.showsUnavailableNotice)
                WorkflowUnavailableNotice(
                  template: viewModel.selectedTemplate,
                  fallbackReason:
                      'No enabled song-generation workflow is available.',
                ),
              GenerationWorkspace(
                form: SongGenerationForm(viewModel: viewModel),
                preview: AnimatedSwitcher(
                  duration: IiOsMotion.of(context, IiOsMotion.base),
                  child: switch (true) {
                    _ when viewModel.submittedJob != null =>
                      JobSubmissionResult(
                        key: const ValueKey('song-result'),
                        controller: controller,
                        result: viewModel.submittedJob!,
                        title: 'Song generation submitted',
                        mediaKind: GeneratedMediaKind.audio,
                      ),
                    _ when viewModel.submitting => const GenerationSlot(
                      key: ValueKey('song-working'),
                      phase: GenerationPhase.working,
                      workingLabel: 'Submitting song generation\u2026',
                      aspectRatio: 3,
                    ),
                    _ => const GenerationSlot(
                      key: ValueKey('song-idle'),
                      phase: GenerationPhase.idle,
                      idleHint: 'Your song will appear here',
                      aspectRatio: 3,
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
