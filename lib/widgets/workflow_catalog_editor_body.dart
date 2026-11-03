part of 'workflow_catalog_editor.dart';

class _WorkflowCatalogBody extends StatelessWidget {
  const _WorkflowCatalogBody({
    required this.model,
    required this.selected,
    required this.hasRepositories,
    required this.onChanged,
    required this.onManageWorkspaceAccess,
  });

  final WorkflowCatalogViewModel model;
  final List<String> selected;
  final bool hasRepositories;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback? onManageWorkspaceAccess;

  @override
  Widget build(BuildContext context) {
    final enabled = selected.toSet();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'Generation workflows',
              trailing: OutlinedButton.icon(
                onPressed: model.refreshing || !hasRepositories
                    ? null
                    : model.refresh,
                icon: model.refreshing
                    ? const SizedBox.square(
                        dimension: IiOsIconSize.sm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.refreshCw, size: IiOsIconSize.sm),
                label: Text(
                  model.templates.isEmpty
                      ? 'Discover workflows'
                      : 'Refresh workflows',
                ),
              ),
            ),
            IiOsGap.vXxs,
            Text(
              'Resource access does not enable workflows automatically. '
              'Discover workflows from assigned repositories, then choose '
              'which ones people may run.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vSm,
            if (model.errorMessage != null && model.templates.isNotEmpty) ...[
              InlineFormError(message: model.errorMessage),
              IiOsGap.vSm,
            ],
            _WorkflowCatalogContent(
              model: model,
              enabled: enabled,
              hasRepositories: hasRepositories,
              onChanged: onChanged,
              onManageWorkspaceAccess: onManageWorkspaceAccess,
            ),
            if (model.issues.isNotEmpty) ...[
              const Divider(),
              for (final issue in model.issues)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    LucideIcons.triangleAlert,
                    size: IiOsIconSize.sm,
                  ),
                  title: Text(issue.repository),
                  subtitle: const Text(
                    'This repository\u2019s workflow catalog could not be read.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
