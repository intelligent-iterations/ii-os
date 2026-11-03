part of 'project_admin_screen.dart';

class _WorkspaceSetupOverview extends StatelessWidget {
  const _WorkspaceSetupOverview({
    required this.onManageOrganizationResources,
    required this.onManageWorkspaceAccess,
  });

  final VoidCallback? onManageOrganizationResources;
  final VoidCallback? onManageWorkspaceAccess;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Set up this workspace in three steps'),
          IiOsGap.vXs,
          const _WorkspaceSetupStep(
            number: '1',
            title: 'Organization resources',
            message:
                'Connect cloud, GitHub, and runner resources once for the organization.',
          ),
          const _WorkspaceSetupStep(
            number: '2',
            title: 'Workspace access',
            message:
                'Choose the repositories, permissions, and compute this workspace may use.',
          ),
          const _WorkspaceSetupStep(
            number: '3',
            title: 'Enable workflows',
            message:
                'Resource access does not enable workflows automatically. Discover and enable them below.',
          ),
          if (onManageOrganizationResources != null ||
              onManageWorkspaceAccess != null) ...[
            IiOsGap.vXs,
            Wrap(
              spacing: IiOsSpacing.xs,
              runSpacing: IiOsSpacing.xs,
              children: [
                if (onManageOrganizationResources != null)
                  TextButton.icon(
                    onPressed: onManageOrganizationResources,
                    icon: const Icon(
                      LucideIcons.building2,
                      size: IiOsIconSize.sm,
                    ),
                    label: const Text('Manage organization resources'),
                  ),
                if (onManageWorkspaceAccess != null)
                  TextButton.icon(
                    onPressed: onManageWorkspaceAccess,
                    icon: const Icon(
                      LucideIcons.shieldCheck,
                      size: IiOsIconSize.sm,
                    ),
                    label: const Text('Manage workspace access'),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _WorkspaceSetupStep extends StatelessWidget {
  const _WorkspaceSetupStep({
    required this.number,
    required this.title,
    required this.message,
  });

  final String number;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(radius: IiOsIconSize.md, child: Text(number)),
    title: Text(title),
    subtitle: Text(message),
  );
}

class _LegacyGitHubConnection extends StatelessWidget {
  const _LegacyGitHubConnection({
    required this.repositories,
    required this.onOpenGitHubSetup,
  });

  final List<String> repositories;
  final VoidCallback? onOpenGitHubSetup;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Legacy GitHub connection'),
          IiOsGap.vXxs,
          Text(
            repositories.isEmpty
                ? 'No repository is connected yet. Use the guided GitHub '
                      'check to select and verify one.'
                : 'Connected repositories: ${repositories.join(', ')}. Use '
                      'the guided GitHub check to change or verify them.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IiOsGap.vSm,
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onOpenGitHubSetup,
              icon: const Icon(LucideIcons.gitFork, size: IiOsIconSize.sm),
              label: const Text('Review GitHub connection'),
            ),
          ),
        ],
      ),
    ),
  );
}
