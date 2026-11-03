import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/fleet_snapshot.dart';
import 'package:test/test.dart';

Map<String, Object?> _host(
  String id, {
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'health': 'ok',
  'capabilities': ['runtime-docker'],
  ...extra,
};

Map<String, Object?> _report({
  List<Object?>? hosts,
  List<Object?>? activity,
  Object? observedAt = '2026-08-20T21:14:22.000Z',
}) => {
  'observedAt': observedAt,
  'controlPlaneId': 'primary',
  'hosts': hosts ?? [_host('mac-host-1')],
  'activity': activity ?? const <Object?>[],
};

void main() {
  test('parses a machine and keeps its measurements', () {
    final snapshot = FleetSnapshot.fromJson(
      _report(
        hosts: [
          _host(
            'mac-host-1',
            extra: {
              'drain': false,
              'runnerKinds': ['direct-command', 'github-actions'],
              'pools': ['personal-alice', 'shared-coders'],
              'os': 'darwin',
              'hardwareModel': 'Mac14,3',
              'maxRamMb': 20480,
              'freeRamMb': 16384,
              'maxCpu': 7,
              'freeCpu': 5,
              'loadPerCpu': 0.4,
              'diskUsedPct': 87.9,
            },
          ),
        ],
      ),
    );

    final host = snapshot.hosts.single;
    expect(host.id, 'mac-host-1');
    expect(host.health, 'ok');
    expect(host.runnerKinds, ['direct-command', 'github-actions']);
    expect(host.toJson()['pools'], ['personal-alice', 'shared-coders']);
    expect(host.maxRamMb, 20480);
    expect(host.freeRamMb, 16384);
    expect(host.loadPerCpu, closeTo(0.4, 0.0001));
    expect(snapshot.controlPlaneId, 'primary');
  });

  test('normalizes health to the values the page knows how to render', () {
    String healthOf(Object? value) => FleetSnapshot.fromJson(
      _report(
        hosts: [
          _host('h', extra: {'health': value}),
        ],
      ),
    ).hosts.single.health;

    expect(healthOf('ok'), 'ok');
    expect(healthOf('HEALTHY'), 'ok');
    // Fleet's own third value survives: a degraded machine is still talking to
    // us, and collapsing it into unhealthy would send someone hunting a fault
    // in the wrong place.
    expect(healthOf('degraded'), 'degraded');
    expect(healthOf('unhealthy'), 'unhealthy');
    expect(healthOf('unreachable'), 'unhealthy');
    expect(healthOf('something-a-reporter-invented'), 'unknown');
    expect(healthOf(null), 'unknown');
  });

  test('refuses a report with more machines than the bound allows', () {
    expect(
      () => FleetSnapshot.fromJson(
        _report(
          hosts: List.generate(
            FleetBounds.maxHosts + 1,
            (index) => _host('host-$index'),
          ),
        ),
      ),
      throwsA(
        isA<ApiError>()
            .having((error) => error.status, 'status', 413)
            .having((error) => error.code, 'code', 'fleet_snapshot_too_large'),
      ),
    );
  });

  test('refuses a report with more activity than the bound allows', () {
    expect(
      () => FleetSnapshot.fromJson(
        _report(
          activity: List.generate(
            FleetBounds.maxActivity + 1,
            (index) => {
              'leaseId': 'lease-$index',
              'hostId': 'mac-host-1',
              'jobId': 'job',
              'state': 'running',
            },
          ),
        ),
      ),
      throwsA(isA<ApiError>().having((error) => error.status, 'status', 413)),
    );
  });

  test('refuses a report that names the same machine twice', () {
    expect(
      () => FleetSnapshot.fromJson(
        _report(hosts: [_host('mac-host-1'), _host('mac-host-1')]),
      ),
      throwsA(isA<ApiError>().having((error) => error.status, 'status', 400)),
    );
  });

  test('refuses a report with no observation time', () {
    expect(
      () => FleetSnapshot.fromJson(_report(observedAt: null)),
      throwsA(isA<ApiError>().having((error) => error.status, 'status', 400)),
    );
  });

  test('refuses a machine with no usable id', () {
    expect(
      () => FleetSnapshot.fromJson(_report(hosts: [_host('   ')])),
      throwsA(isA<ApiError>().having((error) => error.status, 'status', 400)),
    );
    expect(
      () => FleetSnapshot.fromJson(
        _report(hosts: [_host('x' * (FleetBounds.maxIdLength + 1))]),
      ),
      throwsA(isA<ApiError>().having((error) => error.status, 'status', 400)),
    );
  });

  test('truncates labels and caps capability lists', () {
    final snapshot = FleetSnapshot.fromJson(
      _report(
        hosts: [
          _host(
            'mac-host-1',
            extra: {
              'os': 'o' * 500,
              'capabilities': List.generate(
                FleetBounds.maxCapabilities + 20,
                (index) => 'capability-$index',
              ),
              'pools': List.generate(
                FleetBounds.maxPools + 20,
                (index) => 'pool-$index',
              ),
            },
          ),
        ],
      ),
    );

    final host = snapshot.hosts.single;
    expect(host.os, hasLength(FleetBounds.maxLabelLength));
    expect(host.capabilities, hasLength(FleetBounds.maxCapabilities));
    expect(host.toJson()['pools'], hasLength(FleetBounds.maxPools));
  });

  test('drops measurements that are negative or unparseable', () {
    final host = FleetSnapshot.fromJson(
      _report(
        hosts: [
          _host(
            'mac-host-1',
            extra: {
              'freeRamMb': -5,
              'maxCpu': 'not a number',
              'loadPerCpu': double.nan,
              'processCount': 425,
            },
          ),
        ],
      ),
    ).hosts.single;

    expect(host.freeRamMb, isNull);
    expect(host.maxCpu, isNull);
    expect(host.loadPerCpu, isNull);
    expect(host.processCount, 425);
  });

  test('round-trips through json without losing a field', () {
    final snapshot = FleetSnapshot.fromJson(
      _report(
        hosts: [
          _host('mac-host-1', extra: {'freeRamMb': 1024, 'os': 'darwin'}),
        ],
        activity: [
          {
            'leaseId': 'lease-1',
            'hostId': 'mac-host-1',
            'jobId': 'github:1:1:ii-os-deploy',
            'state': 'running',
            'startedAt': '2026-08-20T21:00:00.000Z',
            'reservedRamMb': 4096,
          },
        ],
      ),
    );

    final restored = FleetSnapshot.fromJson(snapshot.toJson());
    expect(restored.hosts.single.freeRamMb, 1024);
    expect(restored.hosts.single.os, 'darwin');
    expect(restored.activity.single.jobId, 'github:1:1:ii-os-deploy');
    expect(restored.activity.single.reservedRamMb, 4096);
    expect(restored.observedAt, snapshot.observedAt);
  });
}
