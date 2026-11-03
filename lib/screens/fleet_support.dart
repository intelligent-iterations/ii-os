part of 'fleet_screen.dart';

const _recentWorkShown = 12;

IiOsHue _hueFor(IiOsPalette palette, FleetMachineState state) =>
    switch (state) {
      FleetMachineState.working => palette.info,
      FleetMachineState.ready => palette.brand,
      FleetMachineState.draining => palette.warning,
      FleetMachineState.degraded => palette.warning,
      FleetMachineState.unreachable => palette.danger,
    };

String _stateLabel(FleetMachineState state) => switch (state) {
  FleetMachineState.working => 'Working',
  FleetMachineState.ready => 'Ready',
  FleetMachineState.draining => 'Draining',
  FleetMachineState.degraded => 'Degraded',
  FleetMachineState.unreachable => 'Not reporting',
};

IconData _idleIcon(FleetMachineState state) => switch (state) {
  FleetMachineState.unreachable => LucideIcons.circleAlert,
  FleetMachineState.draining => LucideIcons.circleArrowDown,
  FleetMachineState.degraded => LucideIcons.triangleAlert,
  _ => LucideIcons.circleCheck,
};

String _idleMessage(FleetMachineState state) => switch (state) {
  FleetMachineState.unreachable => 'Out of contact',
  FleetMachineState.draining => 'Finishing up, taking no new work',
  FleetMachineState.degraded => 'Reporting a problem',
  _ => 'Ready for work',
};

Color _meterColour(
  IiOsPalette palette,
  FleetMachine machine,
  double? fraction,
) {
  if (machine.state == FleetMachineState.unreachable) {
    return palette.danger.fill;
  }
  if ((fraction ?? 0) >= _nearlyFull) return palette.warning.fill;
  return palette.info.fill;
}

const _nearlyFull = 0.9;

String _describeHardware(FleetMachine machine) {
  final parts = [
    ?machine.hardwareModel,
    ?machine.os,
    if (machine.totalCpu != null) '${machine.totalCpu} cores reservable',
  ];
  return parts.isEmpty ? 'Hardware not reported' : parts.join(' · ');
}

String _memoryDetail(FleetMachine machine) {
  final total = machine.totalRamMb;
  final free = machine.freeRamMb;
  if (total == null || free == null) return 'not reported';
  return '${_gb(total - free)} of ${_gb(total)} committed';
}

String _coreDetail(FleetMachine machine) {
  final total = machine.totalCpu;
  final free = machine.freeCpu;
  if (total == null || free == null) return 'not reported';
  return '${total - free} of $total committed';
}

String _gb(int megabytes) {
  final gigabytes = megabytes / 1024;
  return gigabytes >= 10 || gigabytes == gigabytes.roundToDouble()
      ? '${gigabytes.round()} GB'
      : '${gigabytes.toStringAsFixed(1)} GB';
}

List<String> _technicalLines(FleetMachine machine, List<FleetWork> work) => [
  'host_id: ${machine.id}',
  'runner kinds: ${machine.runnerKinds.isEmpty ? 'none' : machine.runnerKinds.join(', ')}',
  'active runtimes: ${machine.activeRuntimes}',
  if (machine.loadPerCpu != null)
    'load per core: ${machine.loadPerCpu!.toStringAsFixed(2)}',
  if (machine.diskUsedPct != null)
    'disk used: ${machine.diskUsedPct!.toStringAsFixed(1)}%',
  if (machine.lastHeartbeat != null)
    'last heartbeat: ${machine.lastHeartbeat!.toIso8601String()}',
  for (final entry in work)
    'lease ${entry.id}: ${entry.state} \u2014 ${entry.name}',
];

/// Where a machine sits in the list: busy first, gone last.
///
/// Deliberately not "most broken first". A fleet can collect ephemeral
/// registrations that never deregister, so attention-first ordering would put
/// a wall of long-gone machines above the machines actually running the work.
int _displayRank(FleetMachineState state) => switch (state) {
  FleetMachineState.working => 0,
  FleetMachineState.ready => 1,
  FleetMachineState.draining => 2,
  FleetMachineState.degraded => 3,
  FleetMachineState.unreachable => 4,
};

int _byLivelinessThenName(FleetMachine left, FleetMachine right) {
  final byState = _displayRank(left.state).compareTo(_displayRank(right.state));
  return byState != 0 ? byState : left.id.compareTo(right.id);
}

/// Among the absent, the ones still holding capacity come first: that is the
/// only thing in this group anybody can act on.
int _strandedFirstThenName(FleetMachine left, FleetMachine right) {
  if (left.holdsStrandedCapacity != right.holdsStrandedCapacity) {
    return left.holdsStrandedCapacity ? -1 : 1;
  }
  return left.id.compareTo(right.id);
}

String _lastSeen(DateTime? heartbeat) =>
    heartbeat == null ? 'never reported' : 'last seen ${_ago(heartbeat)}';

/// What an absent machine is still holding, in the units the meters use.
String _strandedSummary(FleetMachine machine) {
  final total = machine.totalRamMb;
  final free = machine.freeRamMb;
  if (total == null || free == null || total <= free) {
    return '${machine.activeRuntimes} runtime still reserved';
  }
  return '${_gb(total - free)} still reserved';
}

String _ago(DateTime moment) {
  final elapsed = DateTime.now().difference(moment);
  if (elapsed.inMinutes < 1) return 'moments ago';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} minutes ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} hours ago';
  return '${elapsed.inDays} days ago';
}

/// How much of a capability is actually available, said in machines.
///
/// When every machine that claims it is up, the total alone is the whole story
/// and a second number would only be noise.
String _coverageLabel(int available, int total) {
  if (available == 0) {
    return total == 1
        ? 'no machine (1 offline)'
        : 'no machine ($total offline)';
  }
  if (available == total) {
    return available == 1 ? '1 machine' : '$available machines';
  }
  return '$available of $total machines';
}
