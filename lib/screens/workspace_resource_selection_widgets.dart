part of 'workspace_resource_selection_screen.dart';

class _WorkspaceResourcesPage extends StatelessWidget {
  const _WorkspaceResourcesPage({
    required this.model,
    required this.embedded,
    required this.onOpenWorkspaceSetup,
  });

  final WorkspaceResourcesViewModel model;
  final bool embedded;
  final VoidCallback? onOpenWorkspaceSetup;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose only the resources this workspace may use from those '
          'available from ${model.organization.name}. Credentials remain at '
          'the organization level. A workspace may receive several resources '
          'of each kind and names one primary for existing operations.',
        ),
        IiOsGap.vXs,
        Text(
          'Saving access does not enable workflows automatically. After this '
          'step, discover and enable workflows in Workspace setup.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!model.canManage) ...[
          IiOsGap.vXs,
          Text(
            'Ask a Workspace Admin or Organization Admin to change this '
            'selection.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        IiOsGap.vMd,
        _GcpGrantCard(model: model),
        IiOsGap.vMd,
        _GitHubGrantCard(model: model),
        IiOsGap.vMd,
        _RunnerGrantCard(model: model),
        InlineFormError(message: model.errorMessage),
        IiOsGap.vMd,
        Wrap(
          spacing: IiOsSpacing.xs,
          runSpacing: IiOsSpacing.xs,
          children: [
            FilledButton.icon(
              onPressed: model.canSave ? model.save : null,
              icon: model.isBusy
                  ? const SizedBox.square(
                      dimension: IiOsIconSize.sm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.shieldCheck, size: IiOsIconSize.md),
              label: const Text('Save workspace access'),
            ),
            OutlinedButton.icon(
              onPressed: model.canSave && onOpenWorkspaceSetup != null
                  ? () async {
                      if (await model.save()) onOpenWorkspaceSetup!();
                    }
                  : null,
              icon: const Icon(LucideIcons.arrowRight, size: IiOsIconSize.md),
              label: const Text('Next: discover workflows'),
            ),
          ],
        ),
      ],
    );
    final page = PageFrame(
      title: 'Workspace access',
      subtitle: 'Choose what this workspace may use',
      child: content,
    );
    return embedded
        ? page
        : Scaffold(
            appBar: AppBar(title: const Text('ii-os')),
            body: page,
          );
  }
}

class _GcpGrantCard extends StatelessWidget {
  const _GcpGrantCard({required this.model});

  final WorkspaceResourcesViewModel model;

  @override
  Widget build(BuildContext context) {
    final resources = model.organization.resources.gcp
        .where((item) => item.active)
        .toList();
    return _ResourceCard(
      title: 'GCP project',
      icon: LucideIcons.cloud,
      child: resources.isEmpty
          ? const _EmptyResource(
              'No GCP projects are available. Ask an Organization Admin to '
              'add one.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AvailableResources(names: resources.map((item) => item.name)),
                IiOsGap.vXs,
                DropdownButtonFormField<String>(
                  initialValue: model.gcpId,
                  decoration: const InputDecoration(
                    labelText: 'Primary GCP project',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Not assigned'),
                    ),
                    for (final resource in resources)
                      DropdownMenuItem(
                        value: resource.id,
                        child: Text(resource.name),
                      ),
                  ],
                  onChanged: model.canManage && !model.isBusy
                      ? (value) => model.selectGcp(
                          value?.isEmpty == true ? null : value,
                        )
                      : null,
                ),
                IiOsGap.vSm,
                _AssignedResourceChips(
                  label: 'Assigned GCP projects',
                  resources: resources
                      .map((item) => (id: item.id, name: item.name))
                      .toList(),
                  assignedIds: model.assignedGcpIds,
                  primaryId: model.gcpId,
                  enabled: model.canManage && !model.isBusy,
                  onChanged: model.setGcpAssigned,
                ),
                if (model.selectedGcp case final selected?) ...[
                  IiOsGap.vSm,
                  _PermissionChips(
                    permissions: selected.permissions,
                    selected: model.gcpPermissions,
                    enabled: model.canManage && !model.isBusy,
                    onChanged: model.setGcpPermissions,
                  ),
                ],
              ],
            ),
    );
  }
}

class _GitHubGrantCard extends StatelessWidget {
  const _GitHubGrantCard({required this.model});

  final WorkspaceResourcesViewModel model;

  @override
  Widget build(BuildContext context) {
    final resources = model.organization.resources.github
        .where((item) => item.active)
        .toList();
    final selected = model.selectedGitHub;
    return _ResourceCard(
      title: 'GitHub App',
      icon: LucideIcons.gitFork,
      child: _OptionalResourceDropdown(
        label: 'Primary GitHub App',
        value: model.githubId,
        items: resources.map((item) => (id: item.id, name: item.name)).toList(),
        enabled: model.canManage && !model.isBusy,
        onChanged: model.selectGitHub,
        assignments: _AssignedResourceChips(
          label: 'Assigned GitHub Apps',
          resources: resources
              .map((item) => (id: item.id, name: item.name))
              .toList(),
          assignedIds: model.assignedGitHubIds,
          primaryId: model.githubId,
          enabled: model.canManage && !model.isBusy,
          onChanged: model.setGitHubAssigned,
        ),
        details: selected == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PermissionChips(
                    permissions: selected.permissions,
                    selected: model.githubPermissions,
                    enabled: model.canManage && !model.isBusy,
                    onChanged: model.setGitHubPermissions,
                  ),
                  IiOsGap.vXs,
                  Text(
                    'Repositories',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  IiOsGap.vXxs,
                  _ChoiceChips(
                    choices: selected.repositories,
                    selected: model.repositories,
                    enabled: model.canManage && !model.isBusy,
                    onChanged: model.setRepositories,
                  ),
                ],
              ),
      ),
    );
  }
}

class _RunnerGrantCard extends StatelessWidget {
  const _RunnerGrantCard({required this.model});

  final WorkspaceResourcesViewModel model;

  @override
  Widget build(BuildContext context) {
    final resources = model.organization.resources.runners
        .where((item) => item.active)
        .toList();
    final selected = model.selectedRunner;
    return _ResourceCard(
      title: 'Runner pool',
      icon: LucideIcons.server,
      child: _OptionalResourceDropdown(
        label: 'Primary runner pool',
        value: model.runnerId,
        items: resources.map((item) => (id: item.id, name: item.name)).toList(),
        enabled: model.canManage && !model.isBusy,
        onChanged: model.selectRunner,
        assignments: _AssignedResourceChips(
          label: 'Assigned runner pools',
          resources: resources
              .map((item) => (id: item.id, name: item.name))
              .toList(),
          assignedIds: model.assignedRunnerIds,
          primaryId: model.runnerId,
          enabled: model.canManage && !model.isBusy,
          onChanged: model.setRunnerAssigned,
        ),
        details: selected == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Capabilities',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  IiOsGap.vXxs,
                  _ChoiceChips(
                    choices: selected.capabilities,
                    selected: model.runnerCapabilities,
                    enabled: model.canManage && !model.isBusy,
                    onChanged: model.setRunnerCapabilities,
                  ),
                  IiOsGap.vSm,
                  _RunnerCapacityFields(model: model, envelope: selected),
                  InlineFormError(
                    message: model.runnerSelectionValid
                        ? null
                        : 'Choose positive runner limits no greater than the '
                              'organization pool.',
                  ),
                ],
              ),
      ),
    );
  }
}
