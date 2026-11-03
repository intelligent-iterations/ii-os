part of 'project_admin_screen.dart';

class _ProjectListEditor extends StatelessWidget {
  const _ProjectListEditor({
    required this.workspaceId,
    required this.repositories,
    required this.projects,
    required this.repository,
    required this.onChanged,
  });

  final String workspaceId;
  final List<String> repositories;
  final List<ProjectConnection> projects;
  final GitHubProjectRepository repository;
  final ValueChanged<List<ProjectConnection>> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            'GitHub Projects',
            trailing: FilledButton.tonalIcon(
              onPressed: repositories.isEmpty ? null : () => _add(context),
              icon: const Icon(LucideIcons.plus, size: IiOsIconSize.sm),
              label: const Text('Connect project'),
            ),
          ),
          IiOsGap.vXxs,
          Text(
            'Software Workshop rooms use a connected GitHub Project as their '
            'ticket board.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IiOsGap.vSm,
          if (projects.isEmpty)
            EmptyState(
              title: repositories.isEmpty
                  ? 'Assign a repository first'
                  : 'No GitHub Projects connected',
              message: repositories.isEmpty
                  ? 'Choose a GitHub repository in Workspace access, then '
                        'return here.'
                  : 'Connect one of the Projects already linked to an assigned '
                        'repository.',
              icon: LucideIcons.columns3,
            )
          else
            for (final project in projects) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  LucideIcons.columns3,
                  size: IiOsIconSize.md,
                ),
                title: Text(project.title),
                subtitle: Text('${project.owner} · Project #${project.number}'),
                trailing: IconButton(
                  tooltip: 'Disconnect ${project.title}',
                  onPressed: () => onChanged([...projects]..remove(project)),
                  icon: const Icon(LucideIcons.trash2, size: IiOsIconSize.sm),
                ),
              ),
              if (project != projects.last) const Divider(),
            ],
        ],
      ),
    ),
  );

  Future<void> _add(BuildContext context) async {
    final project = await showGitHubProjectPickerDialog(
      context,
      workspaceId: workspaceId,
      repositories: repositories,
      connectedProjectIds: projects.map((project) => project.id).toSet(),
      repository: repository,
    );
    if (project != null) onChanged([...projects, project]);
  }
}
