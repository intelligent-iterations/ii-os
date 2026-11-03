import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/fleet_repository.dart';
import 'package:ii_os/screens/fleet_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

/// A synthetic fleet: a few machines carrying the work, a GPU machine nobody
/// else can replace, one draining, one degraded, and two registrations that
/// stopped reporting -- one of them still holding capacity it cannot be using.
FleetReport _fleet() => FleetReport.fromJson({
  'stale': false,
  'observedAt': DateTime.now().toUtc().toIso8601String(),
  'hosts': [
    _host(
      'runner-1',
      capabilities: ['containers', 'vm', 'mobile-build', 'web-build'],
      maxRam: 16384,
      freeRam: 12288,
      maxCpu: 8,
      freeCpu: 6,
      active: 1,
      model: 'Workstation',
      os: 'darwin',
      load: 0.4,
      disk: 50.0,
    ),
    _host(
      'runner-2',
      capabilities: ['containers', 'gpu', 'large-gpu'],
      maxRam: 16384,
      freeRam: 16384,
      maxCpu: 8,
      freeCpu: 8,
      model: 'GPU workstation',
      os: 'linux',
      load: 0.05,
      disk: 40.0,
    ),
    _host(
      'runner-3',
      capabilities: ['containers', 'gpu'],
      maxRam: 8192,
      freeRam: 2048,
      maxCpu: 4,
      freeCpu: 1,
      active: 1,
      model: 'GPU worker',
      os: 'linux',
      load: 0.9,
      disk: 60.0,
    ),
    _host(
      'runner-4',
      capabilities: ['containers'],
      maxRam: 8192,
      freeRam: 6144,
      maxCpu: 4,
      freeCpu: 2,
      active: 1,
      model: 'Small server',
      os: 'linux',
      load: 0.3,
      disk: 70.0,
    ),
    _host(
      'runner-5',
      capabilities: ['containers', 'scratch-disk'],
      maxRam: 4096,
      freeRam: 4096,
      maxCpu: 2,
      freeCpu: 2,
      model: 'Small server',
      os: 'linux',
      load: 0.1,
      disk: 80.0,
    ),
    _host(
      'runner-6',
      capabilities: ['containers'],
      maxRam: 4096,
      freeRam: 4096,
      maxCpu: 4,
      freeCpu: 4,
      drain: true,
      model: 'Small server',
      os: 'linux',
    ),
    _host(
      'runner-7',
      health: 'degraded',
      capabilities: ['containers', 'vm'],
      maxRam: 8192,
      freeRam: 8192,
      maxCpu: 6,
      freeCpu: 6,
      model: 'Laptop',
      os: 'darwin',
      load: 1.6,
      disk: 45.0,
    ),
    // Unreachable, and still holding every megabyte it reserved.
    _host(
      'runner-8',
      health: 'unhealthy',
      capabilities: ['containers', 'browser-sandbox'],
      maxRam: 8192,
      freeRam: 0,
      maxCpu: 2,
      freeCpu: 0,
      active: 1,
      model: 'Small server',
      os: 'linux',
    ),
    _host(
      'runner-9',
      health: 'unhealthy',
      capabilities: ['containers'],
      maxRam: 4096,
      freeRam: 4096,
      maxCpu: 4,
      freeCpu: 4,
      model: 'Small server',
      os: 'linux',
    ),
  ],
  'activity': [
    _work('lease-1', 'runner-3', 'github:1001:1:example-job', 'running'),
    _work('lease-2', 'runner-4', 'github:1002:1:nightly-report', 'running'),
    _work('lease-3', 'runner-1', 'direct:example-build', 'running'),
    _work('lease-4', 'runner-1', 'github:1003:1:web-build', 'cleaning'),
    _work(
      'lease-5',
      'runner-8',
      'github:1004:1:browser-proof',
      'failed',
      failReason: 'host_lost',
    ),
  ],
});

Map<String, Object?> _host(
  String id, {
  String health = 'ok',
  List<String> capabilities = const [],
  int? maxRam,
  int? freeRam,
  int? maxCpu,
  int? freeCpu,
  int active = 0,
  bool drain = false,
  String? model,
  String? os,
  double? load,
  double? disk,
}) => {
  'id': id,
  'health': health,
  'drain': drain,
  'capabilities': capabilities,
  'runnerKinds': const ['github-actions'],
  'maxRamMb': maxRam,
  'freeRamMb': freeRam,
  'maxCpu': maxCpu,
  'freeCpu': freeCpu,
  'activeRuntimes': active,
  'hardwareModel': model,
  'os': os,
  'loadPerCpu': load,
  'diskUsedPct': disk,
};

Map<String, Object?> _work(
  String id,
  String host,
  String job,
  String state, {
  String? failReason,
}) => {
  'leaseId': id,
  'hostId': host,
  'jobId': job,
  'state': state,
  'startedAt': DateTime.now().toUtc().toIso8601String(),
  'failReason': failReason,
};

final class _StaticFleetRepository implements FleetRepository {
  const _StaticFleetRepository(this.report);

  final FleetReport? report;

  @override
  Future<FleetReport?> read(String organizationId) async => report;

  @override
  Future<String> issueCredential({
    required String organizationId,
    required String label,
  }) async => '';
}

AppController _controller() {
  return AppController()
    ..session = SessionModel.fromJson({
      'user': {'uid': 'u1', 'email': 'admin@example.com'},
      'organizations': [
        {
          'organization': {'id': 'org-1', 'name': 'Acme Co'},
          'membership': {
            'roleLabel': 'Admin',
            'effectiveCapabilities': ['org.read', 'org.audit.read'],
          },
        },
      ],
      'workspaces': [
        {
          'workspace': {
            'id': 'ws-1',
            'name': 'Engineering',
            'organizationId': 'org-1',
          },
          'membership': {'role': 'admin', 'effectiveCapabilities': <String>[]},
        },
      ],
    })
    ..selectedAccess = WorkspaceAccess.fromJson({
      'workspace': {
        'id': 'ws-1',
        'name': 'Engineering',
        'organizationId': 'org-1',
      },
      'membership': {'role': 'admin', 'effectiveCapabilities': <String>[]},
    });
}

Future<void> _render(
  WidgetTester tester, {
  required ThemeData theme,
  required FleetReport? report,
}) async {
  tester.view.physicalSize = const Size(1500, 2100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: FleetScreen(
        controller: _controller(),
        repository: _StaticFleetRepository(report),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Unmounts the page so the ViewModel cancels its poll timer before the test
/// ends, and reports any layout exception the render produced.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('a fleet lays out without forcing an unbounded height', (
    tester,
  ) async {
    // The machine card stretches a coloured spine to the card's own height
    // inside a scrolling column. Without measuring the row first that asks for
    // infinite height and the whole page fails to render, which no unit test
    // on the models would ever notice.
    await _render(tester, theme: IiOsTheme.light(), report: _fleet());

    expect(find.text('runner-1'), findsWidgets);
    expect(find.text('runner-2'), findsWidgets);
    expect(find.text('Infrastructure'), findsWidgets);
    await _settle(tester);
  });

  testWidgets('the same fleet lays out in dark mode', (tester) async {
    await _render(tester, theme: IiOsTheme.dark(), report: _fleet());

    expect(find.text('runner-1'), findsWidgets);
    await _settle(tester);
  });

  testWidgets('every machine state reaches the page', (tester) async {
    await _render(tester, theme: IiOsTheme.light(), report: _fleet());

    expect(find.text('Working'), findsWidgets);
    expect(find.text('Ready'), findsWidgets);
    expect(find.text('Draining'), findsWidgets);
    expect(find.text('Degraded'), findsWidgets);
    expect(find.text('Not reporting'), findsWidgets);
    await _settle(tester);
  });

  testWidgets('a machine holding capacity while silent is called out', (
    tester,
  ) async {
    await _render(tester, theme: IiOsTheme.light(), report: _fleet());

    // It sits in the out-of-contact group rather than among the live machines,
    // but it still says what it is holding -- that is the one thing in that
    // group anybody can act on.
    expect(find.text('8 GB still reserved'), findsOneWidget);
    expect(
      find.textContaining('holding capacity it cannot be using'),
      findsOneWidget,
    );
    await _settle(tester);
  });

  testWidgets('machines that stopped reporting sort below the live fleet', (
    tester,
  ) async {
    await _render(tester, theme: IiOsTheme.light(), report: _fleet());

    // A fleet can hold ephemeral registrations that never deregistered.
    // Ordering by how broken a machine is would put a wall of long-gone
    // machines above the machines actually running the work.
    //
    // Anchored on text unique to each region: a machine name alone is not,
    // because the activity feed names machines too.
    final heading = tester.getTopLeft(find.text('Out of contact')).dy;
    expect(
      tester.getTopLeft(find.text('Working').first).dy,
      lessThan(heading),
      reason: 'a busy machine belongs above the ones that are gone',
    );
    expect(
      tester.getTopLeft(find.text('8 GB still reserved')).dy,
      greaterThan(heading),
      reason: 'an absent machine belongs below',
    );
    await _settle(tester);
  });

  testWidgets('an unserved capability names the machines that are gone', (
    tester,
  ) async {
    await _render(tester, theme: IiOsTheme.light(), report: _fleet());

    // browser-sandbox lives only on the machine that stopped reporting.
    expect(find.text('no machine (1 offline)'), findsWidgets);
    await _settle(tester);
  });

  testWidgets('an unconnected organization is told so, not shown an error', (
    tester,
  ) async {
    await _render(tester, theme: IiOsTheme.light(), report: null);

    expect(find.text('No fleet connected'), findsWidgets);
    await _settle(tester);
  });
}
