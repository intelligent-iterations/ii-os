import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show
        GenerationWorkspace,
        GhostModeControl,
        IiOsGap,
        IiOsMetaChip,
        IiOsSpacing;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../repositories/classification_result_repository.dart';
import '../repositories/job_repository.dart';
import '../repositories/workflow_template_repository.dart';
import '../state/app_controller.dart';
import '../view_models/classification_view_model.dart';
import '../view_models/playground_view_model.dart';
import '../widgets/common.dart';
import '../widgets/workflow_unavailable_notice.dart';
import 'classification_form.dart';
import 'classification_output.dart';

/// Typed decisions from the open JEV model, run on the workspace's own GPU.
class ClassificationScreen extends StatelessWidget {
  const ClassificationScreen({
    required this.controller,
    this.templateRepository,
    this.jobRepository,
    this.resultRepository,
    this.ghostMode = false,
    this.onGhostModeChanged,
    super.key,
  });

  final AppController controller;
  final WorkflowTemplateRepository? templateRepository;
  final JobRepository? jobRepository;
  final ClassificationResultRepository? resultRepository;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ClassificationViewModel>.reactive(
      viewModelBuilder: _viewModel,
      onViewModelReady: (viewModel) => viewModel.load(),
      builder: (context, viewModel, _) {
        viewModel.setGhostMode(ghostMode);
        return PageFrame(
          title: 'Classification',
          subtitle: 'Typed decisions from an open-weights model on your GPU',
          actions: [
            if (onGhostModeChanged != null)
              GhostModeControl(
                key: const Key('classification-ghost-mode'),
                enabled: ghostMode,
                onChanged: onGhostModeChanged!,
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModelFacts(
                model: viewModel.template?.model ?? 'autotrust/JEV-9B',
                availability: viewModel.availability,
              ),
              IiOsGap.vMd,
              if (viewModel.showsUnavailableNotice)
                WorkflowUnavailableNotice(
                  template: viewModel.template,
                  fallbackReason:
                      'Classification is not set up for this workspace yet.',
                ),
              GenerationWorkspace(
                form: ClassificationForm(viewModel: viewModel),
                preview: ClassificationOutput(viewModel: viewModel),
              ),
            ],
          ),
        );
      },
    );
  }

  ClassificationViewModel _viewModel() => ClassificationViewModel(
    templates:
        templateRepository ?? WorkflowTemplateApiRepository(controller.api),
    jobs: jobRepository ?? JobApiRepository(controller.api),
    results:
        resultRepository ?? ClassificationResultApiRepository(controller.api),
    workspaceId: controller.workspace?.id ?? '',
    expectedBucket: controller.connection?.bucket ?? '',
    ghostMode: ghostMode,
    onFinished: controller.refreshDashboard,
  );
}

class _ModelFacts extends StatelessWidget {
  const _ModelFacts({required this.model, required this.availability});

  final String model;
  final ClassificationAvailability availability;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IiOsSpacing.xs,
      runSpacing: IiOsSpacing.xs,
      children: [
        IiOsMetaChip(label: model, icon: LucideIcons.cpu),
        const IiOsMetaChip(
          label: 'Open weights · Apache-2.0',
          icon: LucideIcons.scale,
        ),
        IiOsMetaChip(
          label: switch (availability) {
            ClassificationAvailability.available => 'Runtime installed',
            ClassificationAvailability.notInstalled => 'Runtime not installed',
            ClassificationAvailability.notConfigured => 'Not set up',
            ClassificationAvailability.checking => 'Checking runtime',
            ClassificationAvailability.unconfirmed => 'Runtime unconfirmed',
          },
          icon: availability == ClassificationAvailability.available
              ? LucideIcons.circleCheck
              : LucideIcons.clock3,
        ),
      ],
    );
  }
}
