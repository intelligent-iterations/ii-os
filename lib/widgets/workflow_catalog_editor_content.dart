part of 'workflow_catalog_editor.dart';

class _WorkflowCatalogContent extends StatelessWidget {
  const _WorkflowCatalogContent({
    required this.model,
    required this.enabled,
    required this.hasRepositories,
    required this.onChanged,
    required this.onManageWorkspaceAccess,
  });

  final WorkflowCatalogViewModel model;
  final Set<String> enabled;
  final bool hasRepositories;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback? onManageWorkspaceAccess;

  @override
  Widget build(BuildContext context) {
    if (model.isBusy && !model.loaded) {
      return const LoadingSurface(label: 'Loading workspace workflows');
    }
    if (model.templates.isEmpty && model.errorMessage != null) {
      return ErrorSurface(
        title: 'Workspace workflows could not be loaded',
        message: model.errorMessage!,
        onRetry: model.start,
      );
    }
    if (model.templates.isEmpty) {
      return EmptyState(
        title: hasRepositories
            ? 'No workflows discovered for this workspace'
            : 'Assign a repository before discovering workflows',
        message: hasRepositories
            ? 'Discover the workflow catalogs in this workspace\u2019s assigned repositories.'
            : 'Choose at least one GitHub repository in Workspace access, then return here.',
        icon: LucideIcons.workflow,
        action: hasRepositories
            ? FilledButton.icon(
                onPressed: model.refreshing ? null : model.refresh,
                icon: const Icon(LucideIcons.search, size: IiOsIconSize.sm),
                label: const Text('Discover workflows'),
              )
            : OutlinedButton.icon(
                onPressed: onManageWorkspaceAccess,
                icon: const Icon(
                  LucideIcons.shieldCheck,
                  size: IiOsIconSize.sm,
                ),
                label: const Text('Manage workspace access'),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${enabled.length} enabled for this workspace',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        IiOsGap.vXs,
        for (final template in model.templates)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled.contains(template.id),
            title: Text(template.displayName),
            subtitle: Text(
              '${template.repository} · contract ${template.version}',
            ),
            secondary: const Icon(LucideIcons.workflow, size: IiOsIconSize.md),
            onChanged: (value) {
              final next = {...enabled};
              value == true ? next.add(template.id) : next.remove(template.id);
              onChanged(next.toList()..sort());
            },
          ),
      ],
    );
  }
}
