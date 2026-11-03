import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/fleet_repository.dart';

JsonMap _machine(
  String id, {
  String health = 'ok',
  bool drain = false,
  int active = 0,
  List<String> capabilities = const ['runtime-docker'],
  int? maxRam,
  int? freeRam,
}) => {
  'id': id,
  'health': health,
  'drain': drain,
  'activeRuntimes': active,
  'capabilities': capabilities,
  'maxRamMb': maxRam,
  'freeRamMb': freeRam,
};

void main() {
  test('a machine is unreachable before it is anything else', () {
    // Drain and active runtimes are what the machine last claimed; if it is not
    // reporting, none of that is current, and saying "working" would be a lie.
    final machine = FleetMachine.fromJson(
      _machine('m', health: 'unhealthy', drain: true, active: 3),
    );
    expect(machine.state, FleetMachineState.unreachable);
  });

  test('draining outranks working, because it is why work is not arriving', () {
    final machine = FleetMachine.fromJson(
      _machine('m', drain: true, active: 2),
    );
    expect(machine.state, FleetMachineState.draining);
  });

  test('a healthy machine with runtimes is working, without them ready', () {
    expect(
      FleetMachine.fromJson(_machine('m', active: 1)).state,
      FleetMachineState.working,
    );
    expect(FleetMachine.fromJson(_machine('m')).state, FleetMachineState.ready);
  });

  test('unreported capacity is null, which is not the same as idle', () {
    final unreported = FleetMachine.fromJson(_machine('m'));
    expect(unreported.ramUsedFraction, isNull);

    final reported = FleetMachine.fromJson(
      _machine('m', maxRam: 8192, freeRam: 8192),
    );
    expect(reported.ramUsedFraction, 0);
  });

  test('capacity held by a machine out of contact is called out', () {
    final stranded = FleetMachine.fromJson(
      _machine('m', health: 'unhealthy', maxRam: 8192, freeRam: 0),
    );
    expect(stranded.holdsStrandedCapacity, isTrue);

    final idleAndGone = FleetMachine.fromJson(
      _machine('m', health: 'unhealthy', maxRam: 8192, freeRam: 8192),
    );
    expect(idleAndGone.holdsStrandedCapacity, isFalse);
  });

  test('work is named by its readable tail, not its full identifier', () {
    FleetWork work(String jobId) =>
        FleetWork.fromJson({'jobId': jobId, 'hostId': 'm', 'leaseId': 'l'});

    expect(work('github:123456789:1:example-job').name, 'example-job');
    expect(
      work('direct:github-123456791-1-release:host-agent-build').name,
      'host-agent-build',
    );
    expect(work('').name, 'Work');
  });

  test('capability coverage leads with what nothing can serve', () {
    final report = FleetReport.fromJson({
      'stale': false,
      'hosts': [
        _machine('a', capabilities: ['docker', 'tart']),
        _machine('b', capabilities: ['docker']),
        _machine('c', health: 'unhealthy', capabilities: ['cuda']),
        _machine('d', health: 'unhealthy', capabilities: ['docker']),
      ],
      'activity': const <Object?>[],
    });

    final coverage = report.capabilityCoverage;

    // cuda's only machine is silent, so it is unserved and comes first. It
    // must still appear at all: counting only reachable machines would drop it
    // at exactly the moment it started mattering.
    expect(coverage.first.name, 'cuda');
    expect(coverage.first.available, 0);
    expect(coverage.first.total, 1);

    final byName = {for (final entry in coverage) entry.name: entry};
    expect(byName['tart']!.available, 1);
    expect(byName['tart']!.total, 1);
    // Three machines claim docker; one of them is not answering.
    expect(byName['docker']!.available, 2);
    expect(byName['docker']!.total, 3);
    // Scarcest served capability sorts above the better-covered one.
    expect(coverage.map((entry) => entry.name).toList(), [
      'cuda',
      'tart',
      'docker',
    ]);
  });

  test('active work excludes what has already been cleaned up', () {
    final report = FleetReport.fromJson({
      'stale': false,
      'hosts': [_machine('a')],
      'activity': [
        {
          'leaseId': '1',
          'hostId': 'a',
          'jobId': 'x:running',
          'state': 'running',
        },
        {'leaseId': '2', 'hostId': 'a', 'jobId': 'x:done', 'state': 'cleaned'},
      ],
    });

    expect(report.activeWork.map((entry) => entry.name), ['running']);
    expect(report.recentWork, hasLength(2));
    expect(report.workOn('a').map((entry) => entry.name), ['running']);
  });

  test('a fleet that was never connected parses as no report at all', () {
    expect(parseFleetReport(const {'fleet': null}), isNull);
    expect(parseFleetReport(const {}), isNull);
    expect(
      parseFleetReport(const {
        'fleet': {
          'stale': false,
          'hosts': <Object?>[],
          'activity': <Object?>[],
        },
      })?.machines,
      isEmpty,
    );
  });

  test('degraded is its own state, not silence', () {
    // A degraded machine is reporting a problem; an unreachable one is not
    // reporting at all. Rendering the first as the second sends someone
    // looking for a dead host that is in fact answering.
    final degraded = FleetMachine.fromJson(
      _machine('m', health: 'degraded', active: 1),
    );
    expect(degraded.state, FleetMachineState.degraded);
    expect(degraded.holdsStrandedCapacity, isFalse);
  });

  test('a health value nobody recognises is treated as silence', () {
    expect(
      FleetMachine.fromJson(_machine('m', health: 'unknown')).state,
      FleetMachineState.unreachable,
    );
  });

  test('needs-attention folds draining and degraded into one figure', () {
    final report = FleetReport.fromJson({
      'stale': false,
      'hosts': [
        _machine('a', drain: true),
        _machine('b', health: 'degraded'),
        _machine('c'),
        _machine('d', health: 'unhealthy'),
      ],
      'activity': const <Object?>[],
    });

    expect(report.needsAttentionCount, 2);
    expect(report.countOf(FleetMachineState.ready), 1);
    expect(report.countOf(FleetMachineState.unreachable), 1);
  });

  test('machines sort by how much attention they need', () {
    final report = FleetReport.fromJson({
      'stale': false,
      'hosts': [
        _machine('ready'),
        _machine('gone', health: 'unhealthy'),
        _machine('busy', active: 1),
        _machine('degraded', health: 'degraded'),
        _machine('draining', drain: true),
      ],
      'activity': const <Object?>[],
    });

    final ordered = [...report.machines]
      ..sort((left, right) => right.state.index.compareTo(left.state.index));
    expect(ordered.map((machine) => machine.id), [
      'gone',
      'degraded',
      'draining',
      'busy',
      'ready',
    ]);
  });
}
