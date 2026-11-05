import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';

void main() {
  group('customerRunnerPoolId', () {
    test('derives a catalog id from the name a person typed', () {
      expect(
        customerRunnerPoolId('GPU runners', const []),
        'runner_gpu_runners',
      );
      expect(
        customerRunnerPoolId('  Render farm #2 ', const []),
        'runner_render_farm_2',
      );
    });

    test('never reuses an id the organization already holds', () {
      expect(
        customerRunnerPoolId('GPU', const ['runner_gpu', 'runner_gpu_2']),
        'runner_gpu_3',
      );
    });

    test('a name with no letters or digits still yields a valid id', () {
      expect(customerRunnerPoolId('***', const []), 'runner_pool');
    });

    test('stays within the 64-character catalog id limit', () {
      final id = customerRunnerPoolId('a' * 200, const []);
      final taken = customerRunnerPoolId('a' * 200, [id]);

      final valid = RegExp(r'^[a-z][a-z0-9_]{2,63}$');
      expect(valid.hasMatch(id), isTrue, reason: id);
      expect(valid.hasMatch(taken), isTrue, reason: taken);
      expect(taken, isNot(id));
    });
  });

  test('capabilities are trimmed, lower-cased, and de-duplicated', () {
    expect(parseRunnerCapabilities(' runtime-docker, GPU.nvidia,,docker '), {
      'runtime-docker',
      'gpu.nvidia',
      'docker',
    });
    expect(parseRunnerCapabilities(' , '), isEmpty);
  });

  test('your runners become a customer pool that keeps its on/off state', () {
    const input = CustomerRunnerPoolInput(
      name: 'GPU runners',
      runnerGroup: 'gpu-runners',
      capabilities: {'runtime-docker', 'gpu.nvidia'},
      maxCpu: 16,
      maxRamMiB: 65536,
      maxConcurrent: 2,
      active: false,
    );

    expect(input.toDraft('runner_gpu_runners').toJson(), {
      'name': 'GPU runners',
      'provider': 'customer',
      'capabilities': ['gpu.nvidia', 'runtime-docker'],
      'maxCpu': 16,
      'maxRamMiB': 65536,
      'maxConcurrent': 2,
      'providerPoolId': 'gpu-runners',
      'active': false,
    });
  });

  test('only customer pools are kept by hand', () {
    OrganizationRunnerPoolModel pool(String provider) =>
        OrganizationRunnerPoolModel(
          id: 'runner_gpu',
          name: 'GPU',
          provider: provider,
          capabilities: const {'gpu.nvidia'},
          maxCpu: 8,
          maxRamMiB: 16384,
          maxConcurrent: 1,
          active: true,
        );

    expect(pool('customer').keptByHand, isTrue);
    expect(pool('fleet').keptByHand, isFalse);
  });
}
