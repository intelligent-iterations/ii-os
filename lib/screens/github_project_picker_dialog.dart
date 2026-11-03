import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/github_project_repository.dart';
import '../view_models/github_project_picker_view_model.dart';

Future<ProjectConnection?> showGitHubProjectPickerDialog(
  BuildContext context, {
  required String workspaceId,
  required List<String> repositories,
  required Set<String> connectedProjectIds,
  required GitHubProjectRepository repository,
}) => showDialog<ProjectConnection>(
  context: context,
  builder: (context) => _GitHubProjectPickerDialog(
    workspaceId: workspaceId,
    repositories: repositories,
    connectedProjectIds: connectedProjectIds,
    repository: repository,
  ),
);

class _GitHubProjectPickerDialog extends StatelessWidget {
  const _GitHubProjectPickerDialog({
    required this.workspaceId,
    required this.repositories,
    required this.connectedProjectIds,
    required this.repository,
  });

  final String workspaceId;
  final List<String> repositories;
  final Set<String> connectedProjectIds;
  final GitHubProjectRepository repository;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<GitHubProjectPickerViewModel>.reactive(
      viewModelBuilder: () => GitHubProjectPickerViewModel(
        workspaceId: workspaceId,
        repositories: repositories,
        connectedProjectIds: connectedProjectIds,
        repository: repository,
      ),
      onViewModelReady: (model) => model.start(),
      builder: (context, model, _) => AlertDialog(
        icon: const Icon(LucideIcons.columns3),
        title: const Text('Connect a GitHub Project'),
        content: SizedBox(
          width: IiOsBreakpoints.compact,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose a repository, then select one of its linked GitHub Projects. ii-os fills in the owner, number, title, and node ID.',
              ),
              IiOsGap.vMd,
              DropdownButtonFormField<String>(
                initialValue: model.selectedRepository,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Repository'),
                items: [
                  for (final value in model.repositories)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: model.isBusy ? null : model.selectRepository,
              ),
              IiOsGap.vSm,
              Text(
                'Linked GitHub Projects',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              IiOsGap.vXs,
              Flexible(child: _ProjectChoices(model: model)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: model.selectedProject == null
                ? null
                : () => Navigator.pop(context, model.selectedProject),
            child: const Text('Connect project'),
          ),
        ],
      ),
    );
  }
}

class _ProjectChoices extends StatelessWidget {
  const _ProjectChoices({required this.model});

  final GitHubProjectPickerViewModel model;

  @override
  Widget build(BuildContext context) {
    if (model.isBusy && !model.loaded) {
      return const LoadingSurface(label: 'Loading linked GitHub Projects');
    }
    if (model.errorMessage case final error?) {
      return ErrorSurface(
        title: 'GitHub Projects could not be loaded',
        message: error,
        onRetry: model.retry,
      );
    }
    if (model.projects.isEmpty) {
      return const EmptyState(
        title: 'No available linked Projects',
        message:
            'Link a GitHub Project to this repository, or disconnect an existing Project before choosing it again.',
        icon: LucideIcons.columns3,
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final project in model.projects)
          ListTile(
            selected: project == model.selectedProject,
            onTap: () => model.selectProject(project),
            leading: Icon(
              project == model.selectedProject
                  ? LucideIcons.circleCheck
                  : LucideIcons.circle,
            ),
            title: Text(project.title),
            subtitle: Text('${project.owner} · Project #${project.number}'),
          ),
      ],
    );
  }
}
