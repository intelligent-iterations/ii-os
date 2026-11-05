import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show IiOsGateState, IiOsGatedTab;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../repositories/workflow_template_repository.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../view_models/playground_view_model.dart';
import 'classification_screen.dart';
import 'generate_screen.dart';
import 'image_edit_panel.dart';
import 'narration_generation_screen.dart';
import 'song_generation_screen.dart';
import 'video_editor_screen.dart';
import 'video_generation_screen.dart';

/// Tab host for the generation surfaces.
///
/// Deliberately does *not* use `PageFrame`: it is a container of pages, and
/// each tab already brings its own frame, title, and gutters. It also does not
/// open a second `Scaffold` -- the operator shell owns the only one, so nesting
/// another here stacked a second app bar under the real one.
class PlaygroundScreen extends StatelessWidget {
  const PlaygroundScreen({
    required this.controller,
    this.templateRepository,
    super.key,
  });

  final AppController controller;
  final WorkflowTemplateRepository? templateRepository;

  static const _tabs = [
    (icon: LucideIcons.image, label: 'Create images'),
    (icon: LucideIcons.brush, label: 'Edit images'),
    (icon: LucideIcons.clapperboard, label: 'Video gen'),
    (icon: LucideIcons.film, label: 'Video editor'),
    (icon: LucideIcons.audioLines, label: 'Song gen'),
    (icon: LucideIcons.mic2, label: 'Narration'),
  ];

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<PlaygroundViewModel>.reactive(
      viewModelBuilder: () => PlaygroundViewModel(
        templates:
            templateRepository ?? WorkflowTemplateApiRepository(controller.api),
        workspaceId: controller.workspace?.id ?? '',
      ),
      onViewModelReady: (viewModel) => viewModel.load(),
      builder: (context, viewModel, _) => DefaultTabController(
        length: _tabs.length + 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PlaygroundHeader(
              tabs: _tabs,
              classification: viewModel.classification,
              ghostMode: viewModel.ghostMode,
              onGhostModeChanged: viewModel.setGhostMode,
            ),
            Expanded(
              child: _PlaygroundTabs(
                controller: controller,
                templateRepository: templateRepository,
                ghostMode: viewModel.ghostMode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaygroundTabs extends StatelessWidget {
  const _PlaygroundTabs({
    required this.controller,
    required this.templateRepository,
    required this.ghostMode,
  });

  final AppController controller;
  final WorkflowTemplateRepository? templateRepository;
  final bool ghostMode;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      children: [
        GenerateScreen(
          controller: controller,
          ghostMode: ghostMode,
          templateRepository: templateRepository,
        ),
        ImageEditScreen(
          controller: controller,
          ghostMode: ghostMode,
          templateRepository: templateRepository,
        ),
        VideoGenerationScreen(controller: controller, ghostMode: ghostMode),
        VideoEditorScreen(controller: controller, ghostMode: ghostMode),
        SongGenerationScreen(controller: controller, ghostMode: ghostMode),
        NarrationGenerationScreen(controller: controller, ghostMode: ghostMode),
        ClassificationScreen(
          controller: controller,
          ghostMode: ghostMode,
          templateRepository: templateRepository,
        ),
      ],
    );
  }
}

/// The Classify tab reads as ready once its runtime is installed, or when the
/// deployment reports no runner capacity and the run checks for the model.
IiOsGatedTab classificationTab(ClassificationAvailability availability) =>
    IiOsGatedTab(
      icon: LucideIcons.listChecks,
      label: 'Classify',
      state: switch (availability) {
        ClassificationAvailability.available ||
        ClassificationAvailability.checkedOnRun => IiOsGateState.open,
        ClassificationAvailability.notInstalled ||
        ClassificationAvailability.notConfigured => IiOsGateState.locked,
        ClassificationAvailability.checking ||
        ClassificationAvailability.unconfirmed => IiOsGateState.pending,
      },
      reason: switch (availability) {
        ClassificationAvailability.available ||
        ClassificationAvailability.checkedOnRun => '',
        ClassificationAvailability.notInstalled =>
          'Open JEV runtime not installed',
        ClassificationAvailability.notConfigured =>
          'Classification is not set up for this workspace',
        ClassificationAvailability.checking => 'Checking the open JEV runtime',
        ClassificationAvailability.unconfirmed =>
          'Open JEV runtime status not confirmed yet',
      },
    );

class _PlaygroundHeader extends StatelessWidget {
  const _PlaygroundHeader({
    required this.tabs,
    required this.classification,
    required this.ghostMode,
    required this.onGhostModeChanged,
  });

  final List<({IconData icon, String label})> tabs;
  final ClassificationAvailability classification;
  final bool ghostMode;
  final ValueChanged<bool> onGhostModeChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: IiOsColors.surface,
        border: Border(bottom: BorderSide(color: IiOsColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: IiOsSpacing.md,
              top: IiOsSpacing.xs,
              right: IiOsSpacing.xs,
              bottom: IiOsSpacing.xxs,
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.ghost,
                  size: 18,
                  color: ghostMode
                      ? IiOsColors.identityViolet
                      : IiOsColors.muted,
                ),
                IiOsGap.hSm,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ghost mode',
                        style: IiOsTypography.textTheme.labelLarge,
                      ),
                      Text(
                        ghostMode
                            ? 'Nothing is added to history. Keep this tab open and download the result\u2014closing it discards your only copy.'
                            : 'Generations are saved to workspace history.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: IiOsTypography.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const Key('playground-ghost-mode'),
                  value: ghostMode,
                  onChanged: onGhostModeChanged,
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: [
              for (final tab in tabs)
                Tab(icon: Icon(tab.icon, size: 17), text: tab.label),
              classificationTab(classification),
            ],
          ),
        ],
      ),
    );
  }
}
