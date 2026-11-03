part of 'agent_permissions_screen.dart';

class _AgentPermissionControls extends StatelessWidget {
  const _AgentPermissionControls({required this.model});

  final AgentPermissionsViewModel model;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final repository = DropdownButtonFormField<String>(
        initialValue: model.repository,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Repository'),
        items: model.repositories
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: model.selectRepository,
      );
      final branch = Tooltip(
        message: 'Agent work always starts from the dev branch.',
        child: const Chip(
          avatar: Icon(LucideIcons.gitBranch, size: 16),
          label: Text('Agent branch: dev'),
        ),
      );
      final refresh = IconButton.outlined(
        tooltip: 'Refresh installed access',
        onPressed: model.isBusy ? null : model.load,
        icon: const Icon(LucideIcons.refreshCw, size: 17),
      );
      if (constraints.maxWidth < IiOsBreakpoints.compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            repository,
            IiOsGap.vSm,
            Row(
              children: [
                Align(alignment: Alignment.centerLeft, child: branch),
                IiOsGap.hXs,
                refresh,
              ],
            ),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: repository),
          IiOsGap.hSm,
          branch,
          IiOsGap.hXs,
          refresh,
        ],
      );
    },
  );
}

class _AgentPermissionBody extends StatelessWidget {
  const _AgentPermissionBody({
    required this.model,
    required this.canManage,
    required this.onInstall,
    required this.onEdit,
  });

  final AgentPermissionsViewModel model;
  final bool canManage;
  final ValueChanged<AgentPermissionModel> onInstall;
  final ValueChanged<AgentPermissionModel> onEdit;

  @override
  Widget build(BuildContext context) {
    if (model.repository == null) {
      return const Card(
        child: EmptyState(
          title: 'No repository connected',
          message: 'Connect a repository in GitHub setup first.',
          icon: LucideIcons.gitBranch,
        ),
      );
    }
    if (model.isBusy && model.profiles.isEmpty) {
      return const LoadingSurface(label: 'Loading installed agent access');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.errorMessage != null && model.profiles.isEmpty) ...[
          Card(
            child: ListTile(
              leading: const Icon(LucideIcons.triangleAlert, size: 20),
              title: Text(
                model.accessNeedsUpdate
                    ? 'Installed access needs an update'
                    : 'Installed access could not be checked',
              ),
              subtitle: Text(
                model.accessNeedsUpdate
                    ? 'Choose a permission shape below to replace the older profile.'
                    : 'The default shapes are still available. Retry before relying on the installed labels.',
              ),
              trailing: TextButton(
                onPressed: model.load,
                child: const Text('Retry'),
              ),
            ),
          ),
          IiOsGap.vMd,
        ],
        Text(
          'Default permission shapes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IiOsGap.vXs,
        Text(
          'Install only the roles this repository needs. Repository actions '
          'are enforced after the isolated agent run, before GitHub changes are published.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IiOsGap.vSm,
        for (var index = 0; index < model.permissionShapes.length; index++) ...[
          _PermissionCard(
            profile: model.permissionShapes[index],
            installed: model.isInstalled(model.permissionShapes[index]),
            defaultShape: model.isDefaultShape(model.permissionShapes[index]),
            canManage: canManage,
            onInstall: () => onInstall(model.permissionShapes[index]),
            onEdit: () => onEdit(model.permissionShapes[index]),
          ),
          if (index != model.permissionShapes.length - 1) IiOsGap.vSm,
        ],
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.profile,
    required this.installed,
    required this.defaultShape,
    required this.canManage,
    required this.onInstall,
    required this.onEdit,
  });

  final AgentPermissionModel profile;
  final bool installed;
  final bool defaultShape;
  final bool canManage;
  final VoidCallback onInstall;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: const Icon(LucideIcons.shieldCheck, size: 20),
      title: Text(profile.displayName),
      subtitle: Text(
        '${profile.id} · ${profile.version}',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: !canManage
          ? null
          : installed
          ? IconButton(
              tooltip: 'Review and update this access',
              onPressed: onEdit,
              icon: const Icon(LucideIcons.pencil, size: 17),
            )
          : FilledButton.tonalIcon(
              onPressed: onInstall,
              icon: const Icon(LucideIcons.shieldPlus, size: 16),
              label: Text(defaultShape ? 'Install' : 'Update'),
            ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(profile.description),
        ),
        IiOsGap.vSm,
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: IiOsSpacing.xs,
            runSpacing: IiOsSpacing.xs,
            children: [
              if (!installed)
                StatusPill(
                  'Not installed',
                  color: IiOsPalette.of(context).warning.text,
                ),
              if (installed) const StatusPill('Installed'),
              StatusPill(profile.runtimeKind),
            ],
          ),
        ),
        IiOsGap.vSm,
        _ActionList(
          title: 'Agent can',
          icon: LucideIcons.circleCheck,
          values: profile.allowedActions,
        ),
        IiOsGap.vSm,
        _ActionList(
          title: 'Agent cannot',
          icon: LucideIcons.circleX,
          values: profile.deniedActions,
        ),
      ],
    ),
  );
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.title,
    required this.icon,
    required this.values,
  });

  final String title;
  final IconData icon;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      IiOsGap.vXs,
      for (final value in values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16),
              IiOsGap.hXs,
              Expanded(child: Text(value)),
            ],
          ),
        ),
    ],
  );
}
