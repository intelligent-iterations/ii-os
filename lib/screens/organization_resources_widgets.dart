part of 'organization_resources_screen.dart';

class _OrganizationResourcesPage extends StatelessWidget {
  const _OrganizationResourcesPage({
    required this.organization,
    required this.model,
    required this.embedded,
    required this.onAddGcp,
    required this.onSyncRunner,
    required this.onPromoteLegacy,
  });

  final OrganizationAccess organization;
  final OrganizationResourcesViewModel model;
  final bool embedded;
  final VoidCallback onAddGcp;
  final Future<bool> Function() onSyncRunner;
  final Future<bool> Function() onPromoteLegacy;

  @override
  Widget build(BuildContext context) {
    final page = PageFrame(
      title: 'Organization resources',
      subtitle: '${organization.name} · Shared by its workspaces',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connect cloud, code, and compute once. Each workspace receives '
            'only the resources and permissions you choose.',
          ),
          InlineFormError(message: model.errorMessage),
          if (model.validation case final validation?) ...[
            IiOsGap.vMd,
            _GcpBootstrapChecks(validation: validation),
          ],
          if (model.canPromoteLegacySetup) ...[
            IiOsGap.vMd,
            _LegacySetupPromotion(
              busy: model.isBusy,
              refresh: model.refreshingLegacySetup,
              onPressed: onPromoteLegacy,
            ),
          ],
          IiOsGap.vMd,
          _OrganizationResourcePools(
            organization: organization,
            busy: model.isBusy,
            onAddGcp: onAddGcp,
            onSyncRunner: onSyncRunner,
          ),
        ],
      ),
    );
    return embedded
        ? page
        : Scaffold(
            appBar: AppBar(title: const Text('ii-os')),
            body: page,
          );
  }
}

class _GcpBootstrapChecks extends StatelessWidget {
  const _GcpBootstrapChecks({required this.validation});

  final DataPlaneValidationModel validation;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Setup checks'),
          IiOsGap.vSm,
          const Text(
            'Fix the items marked Action required, then run discovery again.',
          ),
          IiOsGap.vSm,
          DataPlaneCheckList(validation: validation),
        ],
      ),
    ),
  );
}

class _LegacySetupPromotion extends StatelessWidget {
  const _LegacySetupPromotion({
    required this.busy,
    required this.refresh,
    required this.onPressed,
  });

  final bool busy;
  final bool refresh;
  final Future<bool> Function() onPressed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.link),
              IiOsGap.hSm,
              Expanded(
                child: Text(
                  refresh
                      ? 'Refresh the attached GitHub App repositories and '
                            'accepted permissions from GitHub. No credential '
                            'is copied or rotated.'
                      : 'Your existing ii-os setup has not been attached to '
                            'this organization yet. Reuse it without entering '
                            'cloud or GitHub credentials again.',
                ),
              ),
            ],
          ),
          IiOsGap.vSm,
          FilledButton(
            onPressed: busy ? null : onPressed,
            child: Text(
              refresh ? 'Refresh GitHub permissions' : 'Use existing setup',
            ),
          ),
        ],
      ),
    ),
  );
}

class _OrganizationResourcePools extends StatelessWidget {
  const _OrganizationResourcePools({
    required this.organization,
    required this.busy,
    required this.onAddGcp,
    required this.onSyncRunner,
  });

  final OrganizationAccess organization;
  final bool busy;
  final VoidCallback onAddGcp;
  final Future<bool> Function() onSyncRunner;

  @override
  Widget build(BuildContext context) {
    final resources = organization.resources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PoolCard(
          title: 'GCP projects',
          icon: LucideIcons.cloud,
          empty: 'No shared GCP projects yet.',
          items: [
            for (final item in resources.gcp)
              _ResourceTile(
                title: item.name,
                subtitle:
                    '${item.connection.projectId} · ${item.permissions.length} permissions',
                active: item.active,
              ),
          ],
          action: organization.can('org.integrations.manage')
              ? _AddResourceButton(
                  label: resources.gcp.isEmpty
                      ? 'Connect GCP project'
                      : 'Add another GCP project',
                  enabled: !busy,
                  onPressed: onAddGcp,
                )
              : null,
        ),
        IiOsGap.vMd,
        _PoolCard(
          title: 'GitHub Apps',
          icon: LucideIcons.gitFork,
          empty: resources.gcp.isEmpty
              ? 'Connect the GCP project holding the App secret first.'
              : 'No labelled GitHub App secrets were discovered. Label the '
                    'secrets, then refresh their GCP project.',
          items: [
            for (final item in resources.github)
              _ResourceTile(
                title: item.name,
                subtitle:
                    'Installation ${item.installationId} · ${item.repositories.length} repositories',
                active: item.active,
              ),
          ],
          action: null,
        ),
        IiOsGap.vMd,
        _PoolCard(
          title: 'Runner pools',
          icon: LucideIcons.server,
          empty: 'No shared runner pools yet.',
          items: [
            for (final item in resources.runners)
              _ResourceTile(
                title: item.name,
                subtitle:
                    '${item.provider} · ${item.providerPoolId} · ${item.maxCpu} CPU · ${item.maxRamMiB} MiB RAM',
                active: item.active,
              ),
          ],
          action: organization.can('org.runners.manage')
              ? _AddResourceButton(
                  label: 'Sync Fleet capacity',
                  enabled: !busy,
                  onPressed: onSyncRunner,
                )
              : null,
        ),
        IiOsGap.vSm,
        Text(
          'GitHub-hosted runners are not enabled here. Fleet sync reads the '
          'organization\u2019s current provider report and never creates a host.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _AddResourceButton extends StatelessWidget {
  const _AddResourceButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: const Icon(LucideIcons.plus, size: IiOsIconSize.md),
    label: Text(label),
  );
}

class _PoolCard extends StatelessWidget {
  const _PoolCard({
    required this.title,
    required this.icon,
    required this.empty,
    required this.items,
    required this.action,
  });

  final String title;
  final IconData icon;
  final String empty;
  final List<Widget> items;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: IiOsIconSize.md),
              IiOsGap.hXs,
              Expanded(child: SectionTitle(title)),
              ?action,
            ],
          ),
          IiOsGap.vSm,
          if (items.isEmpty)
            Text(empty, style: Theme.of(context).textTheme.bodySmall)
          else
            ...items,
        ],
      ),
    ),
  );
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: StatusPill(active ? 'connected' : 'disabled'),
  );
}
