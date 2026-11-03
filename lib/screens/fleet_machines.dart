part of 'fleet_screen.dart';

/// The fleet at a glance, counted by what each machine is doing.
class _FleetSummary extends StatelessWidget {
  const _FleetSummary({required this.report});

  final FleetReport report;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= IiOsBreakpoints.medium
            ? 4
            : constraints.maxWidth >= IiOsBreakpoints.pairedFields
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * IiOsSpacing.sm) / columns;
        final absent = report.countOf(FleetMachineState.unreachable);
        final cards = [
          KpiCard(
            label: 'Running work',
            value: '${report.workingCount}',
            hue: palette.info,
            caption: report.workingCount == 1
                ? 'machine busy'
                : 'machines busy',
          ),
          KpiCard(
            label: 'Ready',
            value: '${report.countOf(FleetMachineState.ready)}',
            hue: palette.brand,
            caption: 'free to take work',
          ),
          KpiCard(
            label: 'Needs attention',
            value: '${report.needsAttentionCount}',
            hue: palette.warning,
            caption: 'draining or degraded',
          ),
          KpiCard(
            label: 'Not reporting',
            value: '$absent',
            hue: palette.danger,
            caption: 'out of contact',
            // The one figure worth interrupting a scan for.
            emphasised: absent > 0,
          ),
        ];
        return Wrap(
          spacing: IiOsSpacing.sm,
          runSpacing: IiOsSpacing.sm,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

/// One machine: what it is, how loaded it is, and what it is doing.
class _MachineCard extends StatelessWidget {
  const _MachineCard({
    required this.machine,
    required this.work,
    required this.selected,
    required this.onTap,
  });

  final FleetMachine machine;
  final List<FleetWork> work;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final hue = _hueFor(palette, machine.state);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: IiOsRadii.lgAll,
        child: Semantics(
          button: true,
          selected: selected,
          label: '${machine.id}, ${_stateLabel(machine.state)}',
          child: ExcludeSemantics(
            // The spine stretches to the card's height, and the card's height
            // comes from its content -- so the Row has to be measured before it
            // can be stretched, or it asks for infinite height and nothing
            // renders at all.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StateSpine(color: hue.fill, emphasised: selected),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(IiOsSpacing.md),
                      child: _MachineCardBody(machine: machine, work: work),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The coloured edge that carries a machine's state before any words do.
class _StateSpine extends StatelessWidget {
  const _StateSpine({required this.color, required this.emphasised});

  final Color color;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: IiOsMotion.quick,
      width: emphasised ? IiOsSpacing.xs : IiOsSpacing.xxs,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadiusDirectional.horizontal(
          start: Radius.circular(IiOsRadii.lg),
        ),
      ),
    );
  }
}

class _MachineCardBody extends StatelessWidget {
  const _MachineCardBody({required this.machine, required this.work});

  final FleetMachine machine;
  final List<FleetWork> work;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: IiOsSpacing.xxs),
              child: _StateDot(state: machine.state),
            ),
            IiOsGap.hXs,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    machine.id,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  Text(
                    _describeHardware(machine),
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
            IiOsGap.hXs,
            _StateBadge(state: machine.state),
          ],
        ),
        IiOsGap.vMd,
        _CapacityMeter(
          label: 'Memory',
          fraction: machine.ramUsedFraction,
          detail: _memoryDetail(machine),
          color: _meterColour(palette, machine, machine.ramUsedFraction),
        ),
        IiOsGap.vXs,
        _CapacityMeter(
          label: 'Cores',
          fraction: machine.cpuUsedFraction,
          detail: _coreDetail(machine),
          color: _meterColour(palette, machine, machine.cpuUsedFraction),
        ),
        IiOsGap.vSm,
        _WorkSummary(machine: machine, work: work),
      ],
    );
  }
}

/// The state, before any words carry it.
///
/// A ring rather than a filled dot for anything idle, so a card that is simply
/// available reads as quieter than one doing work -- colour alone is never the
/// only thing separating them, which is also what keeps it legible to someone
/// who cannot tell the hues apart.
class _StateDot extends StatelessWidget {
  const _StateDot({required this.state});

  final FleetMachineState state;

  @override
  Widget build(BuildContext context) {
    final hue = _hueFor(IiOsPalette.of(context), state);
    final filled = state == FleetMachineState.working;
    return Container(
      width: IiOsSpacing.xs,
      height: IiOsSpacing.xs,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? hue.fill : null,
        border: filled ? null : Border.all(color: hue.fill),
      ),
    );
  }
}

/// A committed-capacity bar.
///
/// A null fraction is drawn as an empty track rather than as zero: a machine
/// that did not report its ledger has not told us it is idle.
class _CapacityMeter extends StatelessWidget {
  const _CapacityMeter({
    required this.label,
    required this.fraction,
    required this.detail,
    required this.color,
  });

  final String label;
  final double? fraction;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: text.labelSmall?.copyWith(color: palette.muted)),
            const Spacer(),
            Text(detail, style: text.labelSmall?.copyWith(color: palette.ink)),
          ],
        ),
        IiOsGap.vXxs,
        ClipRRect(
          borderRadius: IiOsRadii.pillAll,
          child: SizedBox(
            height: IiOsSpacing.xs,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: palette.neutralTint),
                if (fraction != null)
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: fraction!.clamp(0, 1),
                    child: ColoredBox(color: color),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What the machine is working on, or why it is not.
class _WorkSummary extends StatelessWidget {
  const _WorkSummary({required this.machine, required this.work});

  final FleetMachine machine;
  final List<FleetWork> work;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    if (machine.holdsStrandedCapacity) {
      return _InlineNote(
        icon: LucideIcons.triangleAlert,
        message: 'Holding capacity while out of contact',
        color: palette.danger.text,
      );
    }
    if (work.isEmpty) {
      return _InlineNote(
        icon: _idleIcon(machine.state),
        message: _idleMessage(machine.state),
        color: palette.muted,
      );
    }
    return Wrap(
      spacing: IiOsSpacing.xxs,
      runSpacing: IiOsSpacing.xxs,
      children: [
        for (final entry in work)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: IiOsSpacing.xs,
              vertical: IiOsSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: palette.info.container,
              borderRadius: IiOsRadii.pillAll,
            ),
            child: Text(
              entry.name,
              style: text.labelSmall?.copyWith(color: palette.info.text),
            ),
          ),
      ],
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: IiOsIconSize.xs, color: color),
        IiOsGap.hXxs,
        Expanded(
          child: Text(message, style: text.labelSmall?.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final FleetMachineState state;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final hue = _hueFor(palette, state);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IiOsSpacing.xs,
        vertical: IiOsSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: hue.container,
        borderRadius: IiOsRadii.pillAll,
      ),
      child: Text(
        _stateLabel(state),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: hue.text),
      ),
    );
  }
}
