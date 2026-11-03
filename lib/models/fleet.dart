import 'models.dart';

/// What a machine is doing, in the order a reader cares about it.
///
/// Derived here rather than reported, so the page never has to trust a fleet to
/// agree with itself about what "busy" means.
enum FleetMachineState {
  /// Heard from, healthy, and free to take work.
  ready,

  /// Heard from, and running work right now.
  working,

  /// Deliberately being emptied -- it finishes what it has and takes no more.
  draining,

  /// Still reporting, but reporting a problem. Distinct from unreachable on
  /// purpose: a degraded machine is talking to us, and calling it silent would
  /// send someone looking for the wrong fault.
  degraded,

  /// Not heard from recently enough to believe anything it last said.
  unreachable,
}

/// One machine in an organization's fleet.
final class FleetMachine {
  const FleetMachine({
    required this.id,
    required this.state,
    required this.capabilities,
    required this.runnerKinds,
    this.os,
    this.hardwareModel,
    this.lastHeartbeat,
    this.totalRamMb,
    this.freeRamMb,
    this.totalCpu,
    this.freeCpu,
    this.activeRuntimes = 0,
    this.loadPerCpu,
    this.diskUsedPct,
  });

  factory FleetMachine.fromJson(JsonMap json) {
    final health = json['health']?.toString() ?? 'unknown';
    final draining = json['drain'] == true;
    final active = _int(json['activeRuntimes']) ?? 0;
    return FleetMachine(
      id: json['id']?.toString() ?? '',
      // Ordered by what supersedes what. Not reporting comes first because
      // drain state and runtime counts are what the machine last claimed, and
      // none of it is current once it stops talking.
      state: switch ((health, draining, active)) {
        ('unhealthy' || 'unknown', _, _) => FleetMachineState.unreachable,
        ('degraded', _, _) => FleetMachineState.degraded,
        (_, true, _) => FleetMachineState.draining,
        (_, _, final active) when active > 0 => FleetMachineState.working,
        _ => FleetMachineState.ready,
      },
      capabilities: _strings(json['capabilities']),
      runnerKinds: _strings(json['runnerKinds']),
      os: json['os']?.toString(),
      hardwareModel: json['hardwareModel']?.toString(),
      lastHeartbeat: _time(json['lastHeartbeat']),
      totalRamMb: _int(json['maxRamMb']),
      freeRamMb: _int(json['freeRamMb']),
      totalCpu: _int(json['maxCpu']),
      freeCpu: _int(json['freeCpu']),
      activeRuntimes: active,
      loadPerCpu: _double(json['loadPerCpu']),
      diskUsedPct: _double(json['diskUsedPct']),
    );
  }

  final String id;
  final FleetMachineState state;
  final List<String> capabilities;
  final List<String> runnerKinds;
  final String? os;
  final String? hardwareModel;
  final DateTime? lastHeartbeat;
  final int? totalRamMb;
  final int? freeRamMb;
  final int? totalCpu;
  final int? freeCpu;
  final int activeRuntimes;
  final double? loadPerCpu;
  final double? diskUsedPct;

  /// Fraction of reservable memory currently committed, or null when the
  /// machine did not say. Null and zero are different facts and the meters
  /// render them differently.
  double? get ramUsedFraction => _usedFraction(totalRamMb, freeRamMb);

  double? get cpuUsedFraction => _usedFraction(totalCpu, freeCpu);

  /// A machine holding capacity it cannot be using, which is what a leaked
  /// ledger row looks like from outside: unreachable, yet still reserved.
  bool get holdsStrandedCapacity =>
      state == FleetMachineState.unreachable &&
      ((ramUsedFraction ?? 0) > 0 || activeRuntimes > 0);
}

/// One unit of work the fleet placed on a machine.
final class FleetWork {
  const FleetWork({
    required this.id,
    required this.machineId,
    required this.name,
    required this.state,
    this.startedAt,
    this.reservedRamMb,
    this.failReason,
  });

  factory FleetWork.fromJson(JsonMap json) => FleetWork(
    id: json['leaseId']?.toString() ?? '',
    machineId: json['hostId']?.toString() ?? '',
    name: _workName(json['jobId']?.toString() ?? ''),
    state: json['state']?.toString() ?? 'unknown',
    startedAt: _time(json['startedAt']),
    reservedRamMb: _int(json['reservedRamMb']),
    failReason: json['failReason']?.toString(),
  );

  final String id;
  final String machineId;

  /// The readable tail of the job identifier -- `example-job` rather than
  /// `github:123456789:1:example-job`. The full identifier is a mechanism
  /// detail and belongs in the technical disclosure, not on the card.
  final String name;
  final String state;
  final DateTime? startedAt;
  final int? reservedRamMb;
  final String? failReason;

  bool get isFinished =>
      const {'cleaned', 'finished', 'failed', 'rejected'}.contains(state);

  bool get isFailed =>
      failReason != null || const {'failed', 'rejected'}.contains(state);
}

/// An organization's fleet as the control plane last heard it.
final class FleetReport {
  const FleetReport({
    required this.machines,
    required this.work,
    required this.stale,
    this.observedAt,
    this.receivedAt,
  });

  factory FleetReport.fromJson(JsonMap json) => FleetReport(
    machines: _maps(json['hosts']).map(FleetMachine.fromJson).toList(),
    work: _maps(json['activity']).map(FleetWork.fromJson).toList(),
    stale: json['stale'] == true,
    observedAt: _time(json['observedAt']),
    receivedAt: _time(json['receivedAt']),
  );

  final List<FleetMachine> machines;
  final List<FleetWork> work;

  /// The fleet has not reported recently enough to be believed. The page keeps
  /// showing the last picture and says plainly that it is old, because a fleet
  /// that stopped reporting is itself the thing worth seeing.
  final bool stale;
  final DateTime? observedAt;
  final DateTime? receivedAt;

  int countOf(FleetMachineState state) =>
      machines.where((machine) => machine.state == state).length;

  int get workingCount => countOf(FleetMachineState.working);

  int get reachableCount =>
      machines.where((m) => m.state != FleetMachineState.unreachable).length;

  /// Machines that are up but not simply fine -- draining or degraded.
  int get needsAttentionCount =>
      countOf(FleetMachineState.draining) + countOf(FleetMachineState.degraded);

  /// Work still in flight, newest first.
  List<FleetWork> get activeWork {
    final active = work.where((entry) => !entry.isFinished).toList()
      ..sort((left, right) => _descending(left.startedAt, right.startedAt));
    return active;
  }

  List<FleetWork> get recentWork {
    final recent = [...work]
      ..sort((left, right) => _descending(left.startedAt, right.startedAt));
    return recent;
  }

  /// Every capability the fleet advertises, with how many machines can serve
  /// it now and how many claim it at all.
  ///
  /// Counted across every machine, not only the reachable ones. Counting only
  /// what is up would make a capability vanish from the list at the exact
  /// moment its last machine went silent -- the one moment somebody needs to
  /// see it. Unserved capabilities sort to the top; after that, scarcest
  /// first, because a capability one machine serves is one failure from
  /// unserved.
  List<({String name, int available, int total})> get capabilityCoverage {
    final available = <String, int>{};
    final total = <String, int>{};
    for (final machine in machines) {
      final reachable = machine.state != FleetMachineState.unreachable;
      for (final capability in machine.capabilities) {
        total[capability] = (total[capability] ?? 0) + 1;
        if (reachable) {
          available[capability] = (available[capability] ?? 0) + 1;
        }
      }
    }
    final entries =
        total.entries
            .map(
              (entry) => (
                name: entry.key,
                available: available[entry.key] ?? 0,
                total: entry.value,
              ),
            )
            .toList()
          ..sort((left, right) {
            final byAvailable = left.available.compareTo(right.available);
            if (byAvailable != 0) return byAvailable;
            return left.name.compareTo(right.name);
          });
    return entries;
  }

  List<FleetWork> workOn(String machineId) =>
      activeWork.where((entry) => entry.machineId == machineId).toList();
}

int _descending(DateTime? left, DateTime? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return right.compareTo(left);
}

double? _usedFraction(int? total, int? free) {
  if (total == null || free == null || total <= 0) return null;
  final used = (total - free).clamp(0, total);
  return used / total;
}

String _workName(String jobId) {
  if (jobId.isEmpty) return 'Work';
  final tail = jobId.split(':').last.trim();
  return tail.isEmpty ? jobId : tail;
}

List<String> _strings(Object? value) => value is List
    ? value.map((entry) => '$entry').where((entry) => entry.isNotEmpty).toList()
    : const [];

List<JsonMap> _maps(Object? value) => value is List
    ? value.whereType<Map<Object?, Object?>>().map(asJsonMap).toList()
    : const [];

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}');

double? _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
