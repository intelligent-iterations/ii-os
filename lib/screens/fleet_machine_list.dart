part of 'fleet_screen.dart';

/// The machines, live ones first.
///
/// Out-of-contact machines are collected at the bottom rather than sorted in.
/// A fleet can accumulate ephemeral registrations that never deregister, and
/// leading with them buries the machines actually carrying work behind a wall
/// of things that are simply gone. They still have to be visible: one of them
/// may be holding capacity it cannot be using, and that is worth finding. So
/// they are kept, quietly.
class _MachineGrid extends StatelessWidget {
  const _MachineGrid({
    required this.report,
    required this.selectedId,
    required this.onSelect,
  });

  final FleetReport report;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final live =
        report.machines
            .where((m) => m.state != FleetMachineState.unreachable)
            .toList()
          ..sort(_byLivelinessThenName);
    final absent =
        report.machines
            .where((m) => m.state == FleetMachineState.unreachable)
            .toList()
          ..sort(_strandedFirstThenName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Machines', style: Theme.of(context).textTheme.titleMedium),
        IiOsGap.vSm,
        if (live.isEmpty)
          const _NoLiveMachines()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= IiOsBreakpoints.pairedFields
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * IiOsSpacing.sm) /
                  columns;
              return Wrap(
                spacing: IiOsSpacing.sm,
                runSpacing: IiOsSpacing.sm,
                children: [
                  for (final machine in live)
                    SizedBox(
                      width: width,
                      child: _MachineCard(
                        machine: machine,
                        work: report.workOn(machine.id),
                        selected: machine.id == selectedId,
                        onTap: () => onSelect(machine.id),
                      ),
                    ),
                ],
              );
            },
          ),
        if (absent.isNotEmpty) ...[
          IiOsGap.vXl,
          _OutOfContactGroup(
            machines: absent,
            selectedId: selectedId,
            onSelect: onSelect,
          ),
        ],
      ],
    );
  }
}

class _NoLiveMachines extends StatelessWidget {
  const _NoLiveMachines();

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(IiOsSpacing.md),
      decoration: BoxDecoration(
        color: palette.danger.container,
        borderRadius: IiOsRadii.mdAll,
      ),
      child: Text(
        'Nothing in this fleet is reporting. No work can be placed until a '
        'machine comes back.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.danger.text),
      ),
    );
  }
}

/// Machines that have stopped reporting, kept together and kept quiet.
class _OutOfContactGroup extends StatelessWidget {
  const _OutOfContactGroup({
    required this.machines,
    required this.selectedId,
    required this.onSelect,
  });

  final List<FleetMachine> machines;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    final stranded = machines.where((m) => m.holdsStrandedCapacity).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Out of contact', style: text.titleSmall),
            IiOsGap.hXs,
            Text(
              '${machines.length}',
              style: text.titleSmall?.copyWith(color: palette.muted),
            ),
          ],
        ),
        IiOsGap.vXxs,
        Text(
          stranded == 0
              ? 'Last heard from too long ago to believe. Nothing here is '
                    'holding capacity.'
              : stranded == 1
              ? 'One of these is still holding capacity it cannot be using.'
              : '$stranded of these are still holding capacity they cannot be '
                    'using.',
          style: text.bodySmall?.copyWith(
            color: stranded == 0 ? palette.muted : palette.danger.text,
          ),
        ),
        IiOsGap.vSm,
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IiOsSpacing.md,
              vertical: IiOsSpacing.xs,
            ),
            child: Column(
              children: [
                for (final machine in machines)
                  _OutOfContactRow(
                    machine: machine,
                    selected: machine.id == selectedId,
                    onTap: () => onSelect(machine.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One absent machine, on one line.
class _OutOfContactRow extends StatelessWidget {
  const _OutOfContactRow({
    required this.machine,
    required this.selected,
    required this.onTap,
  });

  final FleetMachine machine;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    final stranded = machine.holdsStrandedCapacity;
    return InkWell(
      onTap: onTap,
      borderRadius: IiOsRadii.smAll,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${machine.id}, out of contact',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xs),
            child: Row(
              children: [
                Icon(
                  stranded
                      ? LucideIcons.triangleAlert
                      : LucideIcons.circleSlash,
                  size: IiOsIconSize.xs,
                  color: stranded ? palette.danger.text : palette.muted,
                ),
                IiOsGap.hXs,
                Expanded(
                  child: Text(
                    machine.id,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: stranded ? palette.ink : palette.muted,
                    ),
                  ),
                ),
                IiOsGap.hSm,
                Text(
                  stranded
                      ? _strandedSummary(machine)
                      : _lastSeen(machine.lastHeartbeat),
                  style: text.labelSmall?.copyWith(
                    color: stranded ? palette.danger.text : palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
