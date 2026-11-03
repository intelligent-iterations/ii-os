part of 'fleet_screen.dart';

class _FleetSidePanels extends StatelessWidget {
  const _FleetSidePanels({required this.report});

  final FleetReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CapabilityCoverage(report: report),
        IiOsGap.vXl,
        _ActivityFeed(work: report.recentWork),
      ],
    );
  }
}

/// What the fleet can do, scarcest first.
///
/// Ordered by how few machines offer each capability, because the capability
/// one machine serves is the one that stops work when that machine goes -- and
/// it would otherwise sit at the bottom of an alphabetical list.
class _CapabilityCoverage extends StatelessWidget {
  const _CapabilityCoverage({required this.report});

  final FleetReport report;

  @override
  Widget build(BuildContext context) {
    final coverage = report.capabilityCoverage;
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What this fleet can do', style: text.titleMedium),
        IiOsGap.vXxs,
        Text(
          'Anything nothing can serve right now comes first, then whatever the '
          'fewest machines offer.',
          style: text.bodySmall?.copyWith(color: palette.muted),
        ),
        IiOsGap.vSm,
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.md),
            child: coverage.isEmpty
                ? Text(
                    'No machine is currently reporting a capability.',
                    style: text.bodySmall?.copyWith(color: palette.muted),
                  )
                : Column(
                    children: [
                      for (final entry in coverage)
                        _CapabilityRow(
                          name: entry.name,
                          available: entry.available,
                          total: entry.total,
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.name,
    required this.available,
    required this.total,
  });

  final String name;
  final int available;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    // The alarm is reserved for a capability nothing can serve. Most fleets
    // have a long tail of one-machine capabilities, so warning on every one of
    // those would put a triangle beside almost every row and mean nothing.
    final unserved = available == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
      child: Row(
        children: [
          if (unserved) ...[
            Icon(
              LucideIcons.triangleAlert,
              size: IiOsIconSize.xs,
              color: palette.danger.text,
            ),
            IiOsGap.hXxs,
          ],
          Expanded(child: Text(name, style: text.bodySmall)),
          IiOsGap.hSm,
          Text(
            _coverageLabel(available, total),
            style: text.labelSmall?.copyWith(
              color: unserved
                  ? palette.danger.text
                  : available < total
                  ? palette.warning.text
                  : palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The work the fleet has placed recently, newest first.
class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({required this.work});

  final List<FleetWork> work;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recent work', style: text.titleMedium),
        IiOsGap.vSm,
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(IiOsSpacing.md),
            child: work.isEmpty
                ? Text(
                    'No work has run on this fleet yet.',
                    style: text.bodySmall?.copyWith(color: palette.muted),
                  )
                : Column(
                    children: [
                      for (final entry in work.take(_recentWorkShown))
                        _ActivityRow(entry: entry),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final FleetWork entry;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    final hue = entry.isFailed
        ? palette.danger
        : entry.isFinished
        ? palette.brand
        : palette.info;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: IiOsSpacing.xxs),
            child: Icon(
              entry.isFailed
                  ? LucideIcons.circleX
                  : entry.isFinished
                  ? LucideIcons.circleCheck
                  : LucideIcons.loaderCircle,
              size: IiOsIconSize.xs,
              color: hue.text,
            ),
          ),
          IiOsGap.hXs,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: text.bodySmall),
                Text(
                  entry.machineId,
                  style: text.labelSmall?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The last picture, marked as old rather than removed.
class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.observedAt});

  final DateTime? observedAt;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      decoration: BoxDecoration(
        color: palette.warning.container,
        borderRadius: IiOsRadii.mdAll,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.clock,
            size: IiOsIconSize.sm,
            color: palette.warning.text,
          ),
          IiOsGap.hXs,
          Expanded(
            child: Text(
              observedAt == null
                  ? 'This fleet has stopped reporting. What follows is the last '
                        'picture it sent.'
                  : 'This fleet stopped reporting ${_ago(observedAt!)}. What '
                        'follows is the last picture it sent.',
              style: text.bodySmall?.copyWith(color: palette.warning.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ordinary state for an organization that runs its work elsewhere.
class _NoFleetConnected extends StatelessWidget {
  const _NoFleetConnected({required this.canConnect});

  final bool canConnect;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.server,
      title: 'No fleet connected',
      message: canConnect
          ? 'Connect an execution fleet and its machines will appear here with '
                'what each one is working on.'
          : 'Nobody has connected an execution fleet to this organization yet. '
                'An owner can set one up.',
    );
  }
}

/// Everything about one machine, including the parts written for an operator
/// rather than for a reader.
class _MachineDetail extends StatelessWidget {
  const _MachineDetail({
    required this.machine,
    required this.work,
    required this.onClose,
  });

  final FleetMachine machine;
  final List<FleetWork> work;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(machine.id, style: text.titleMedium)),
                IconButton(
                  tooltip: 'Close machine details',
                  onPressed: onClose,
                  icon: const Icon(LucideIcons.x, size: IiOsIconSize.md),
                ),
              ],
            ),
            Text(
              _describeHardware(machine),
              style: text.bodySmall?.copyWith(color: palette.muted),
            ),
            IiOsGap.vMd,
            Text('Capabilities', style: text.labelLarge),
            IiOsGap.vXs,
            Wrap(
              spacing: IiOsSpacing.xxs,
              runSpacing: IiOsSpacing.xxs,
              children: [
                for (final capability in machine.capabilities)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: IiOsSpacing.xs,
                      vertical: IiOsSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent.container,
                      borderRadius: IiOsRadii.pillAll,
                    ),
                    child: Text(
                      capability,
                      style: text.labelSmall?.copyWith(
                        color: palette.accent.text,
                      ),
                    ),
                  ),
              ],
            ),
            IiOsGap.vMd,
            _MachineTechnicalDisclosure(machine: machine, work: work),
          ],
        ),
      ),
    );
  }
}

/// Identifiers and mechanism, behind a disclosure that says what it is.
class _MachineTechnicalDisclosure extends StatelessWidget {
  const _MachineTechnicalDisclosure({
    required this.machine,
    required this.work,
  });

  final FleetMachine machine;
  final List<FleetWork> work;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text('Technical details', style: text.labelLarge),
      subtitle: Text(
        'Identifiers and scheduler state, as the fleet reported them.',
        style: text.labelSmall?.copyWith(color: palette.muted),
      ),
      children: [
        for (final line in _technicalLines(machine, work))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
              child: Text(line, style: text.labelSmall),
            ),
          ),
      ],
    );
  }
}

/// Reached only if the tenant tier is not yet in this session, which a
/// deployment that has not migrated to organizations can still be.
class _NoOrganization extends StatelessWidget {
  const _NoOrganization();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: LucideIcons.server,
      title: 'No organization',
      message:
          'Infrastructure is owned by an organization, and this project is not '
          'in one yet.',
    );
  }
}
