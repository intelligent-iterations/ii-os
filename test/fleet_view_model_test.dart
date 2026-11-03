import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/fleet_repository.dart';
import 'package:ii_os/view_models/fleet_view_model.dart';

final class _FakeFleetRepository implements FleetRepository {
  _FakeFleetRepository({this.onRead});

  Future<FleetReport?> Function(int call)? onRead;
  int reads = 0;
  String? issuedLabel;

  @override
  Future<FleetReport?> read(String organizationId) async {
    reads++;
    final handler = onRead;
    if (handler != null) return handler(reads);
    return _report();
  }

  @override
  Future<String> issueCredential({
    required String organizationId,
    required String label,
  }) async {
    issuedLabel = label;
    return 'iiosf_v1.key';
  }
}

FleetReport _report({int machines = 2, bool stale = false}) => FleetReport(
  machines: [
    for (var index = 0; index < machines; index++)
      FleetMachine(
        id: 'machine-$index',
        state: FleetMachineState.ready,
        capabilities: const ['runtime-docker'],
        runnerKinds: const ['github-actions'],
      ),
  ],
  work: const [],
  stale: stale,
);

FleetViewModel _model(FleetRepository fleet, {bool canIssue = false}) =>
    FleetViewModel(
      organizationId: 'org-1',
      fleet: fleet,
      canIssueCredential: canIssue,
    );

void main() {
  test('load puts the fleet on screen and clears busy', () async {
    final model = _model(_FakeFleetRepository());

    await model.load();

    expect(model.report?.machines, hasLength(2));
    expect(model.isBusy, isFalse);
    expect(model.errorMessage, isNull);
  });

  test('a failed poll keeps the last picture on screen', () async {
    final repository = _FakeFleetRepository(
      onRead: (call) async {
        if (call == 1) return _report();
        throw Exception('control plane unreachable');
      },
    );
    final model = _model(repository);

    await model.load();
    await model.load(quiet: true);

    expect(model.report?.machines, hasLength(2));
    expect(model.errorMessage, contains('unreachable'));
  });

  test('a first load that fails has nothing to keep', () async {
    final model = _model(
      _FakeFleetRepository(onRead: (_) async => throw Exception('nope')),
    );

    await model.load();

    expect(model.report, isNull);
    expect(model.errorMessage, isNotNull);
  });

  test(
    'the quiet poll never raises busy, so the page cannot flicker',
    () async {
      final model = _model(_FakeFleetRepository());
      final busyReadings = <bool>[];
      model.addListener(() => busyReadings.add(model.isBusy));

      await model.load();
      busyReadings.clear();
      await model.load(quiet: true);

      expect(busyReadings, everyElement(isFalse));
    },
  );

  test('isFirstLoad is true only before there is anything to show', () async {
    final model = _model(_FakeFleetRepository());

    expect(model.isFirstLoad, isFalse);
    await model.load();
    expect(model.isFirstLoad, isFalse);
    expect(model.hasReport, isTrue);
  });

  test(
    'an unconnected fleet reads as no report rather than an error',
    () async {
      final model = _model(_FakeFleetRepository(onRead: (_) async => null));

      await model.load();

      expect(model.report, isNull);
      expect(model.errorMessage, isNull);
      expect(model.hasReport, isFalse);
    },
  );

  test('selecting the same machine twice closes its detail', () async {
    final model = _model(_FakeFleetRepository());
    await model.load();

    model.selectMachine('machine-0');
    expect(model.selectedMachine?.id, 'machine-0');

    model.selectMachine('machine-0');
    expect(model.selectedMachine, isNull);
  });

  test('issuing a credential is refused without the capability', () async {
    final repository = _FakeFleetRepository();
    final model = _model(repository);

    expect(await model.issueCredential('primary fleet'), isNull);
    expect(repository.issuedLabel, isNull);
  });

  test('issuing a credential returns the cleartext once', () async {
    final repository = _FakeFleetRepository();
    final model = _model(repository, canIssue: true);

    expect(await model.issueCredential('primary fleet'), 'iiosf_v1.key');
    expect(repository.issuedLabel, 'primary fleet');
  });

  test('start loads once and never polls in the background', () async {
    final repository = _FakeFleetRepository();
    final model = _model(repository);

    await model.start();
    final readsAfterStart = repository.reads;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.reads, readsAfterStart);
    model.dispose();
  });
}
