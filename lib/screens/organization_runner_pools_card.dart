part of 'organization_resources_screen.dart';

/// The organization's runner pools: runners the organization describes by
/// hand, plus any a capacity report produced.
///
/// Adding your runners is the primary action because it works on every
/// deployment. Syncing a capacity report is secondary: a deployment without a
/// runner control plane has no report, and the sync then says so and points
/// back here.
class _RunnerPoolsCard extends StatelessWidget {
  const _RunnerPoolsCard({
    required this.runners,
    required this.blockedReason,
    required this.error,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onSync,
  });

  final List<OrganizationRunnerPoolModel> runners;

  /// Why the viewer cannot change runners, or null when they can.
  final String? blockedReason;

  /// Why the last runner change failed, beside the actions that caused it.
  final String? error;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<OrganizationRunnerPoolModel> onEdit;
  final Future<bool> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final enabled = blockedReason == null && !busy;
    return _PoolCard(
      title: 'Runner pools',
      icon: LucideIcons.server,
      empty:
          'No runners yet. Add the runners you run so your workspaces can '
          'start workflows on them.',
      notice: blockedReason,
      items: [
        for (final pool in runners)
          _RunnerPoolTile(
            pool: pool,
            enabled: enabled,
            onEdit: () => onEdit(pool),
          ),
      ],
      action: _AddResourceButton(
        label: 'Add your runners',
        enabled: enabled,
        onPressed: onAdd,
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: enabled ? onSync : null,
            icon: const Icon(LucideIcons.refreshCw, size: IiOsIconSize.md),
            label: const Text('Sync reported capacity'),
          ),
          InlineFormError(message: error),
        ],
      ),
    );
  }
}

class _RunnerPoolTile extends StatelessWidget {
  const _RunnerPoolTile({
    required this.pool,
    required this.enabled,
    required this.onEdit,
  });

  final OrganizationRunnerPoolModel pool;
  final bool enabled;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(pool.name),
    subtitle: Text(_runnerPoolSummary(pool)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusPill(pool.active ? 'available' : 'turned off'),
        if (pool.keptByHand) ...[
          IiOsGap.hXs,
          IconButton(
            tooltip: 'Edit ${pool.name}',
            onPressed: enabled ? onEdit : null,
            icon: const Icon(LucideIcons.pencil, size: IiOsIconSize.md),
          ),
        ],
      ],
    ),
  );
}

/// Where the pool came from, then its limits, in the person's terms.
String _runnerPoolSummary(OrganizationRunnerPoolModel pool) => [
  pool.keptByHand ? 'Your runners' : 'From your capacity report',
  if (pool.providerPoolId.isNotEmpty) pool.providerPoolId,
  '${pool.maxCpu} CPU',
  '${pool.maxRamMiB} MiB RAM',
  '${pool.maxConcurrent} at once',
].join(' · ');
