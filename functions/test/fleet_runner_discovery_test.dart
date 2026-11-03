import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/fleet_runner_discovery.dart';
import 'package:test/test.dart';

void main() {
  test('derives one conservative resource for each attested Fleet pool', () {
    final pools = discoverFleetRunnerPools({
      'stale': false,
      'hosts': [
        {
          'id': 'host-a',
          'health': 'ok',
          'drain': false,
          'capabilities': ['comfyui', 'gpu.nvidia'],
          'pools': ['personal-alice', 'shared-coders'],
          'maxCpu': 8,
          'maxRamMb': 32768,
        },
        {
          'id': 'host-b',
          'health': 'degraded',
          'drain': false,
          'capabilities': ['build.linux'],
          'pools': ['shared-coders'],
          'maxCpu': 16,
          'maxRamMb': 65536,
        },
        {
          'id': 'host-c',
          'health': 'ok',
          'drain': true,
          'capabilities': ['must.not.appear'],
          'pools': ['personal-alice'],
          'maxCpu': 64,
          'maxRamMb': 262144,
        },
      ],
    });

    expect(pools, hasLength(2));
    final personal = pools.singleWhere(
      (pool) => pool.toJson()['providerPoolId'] == 'personal-alice',
    );
    expect(personal.provider, 'fleet');
    expect(personal.capabilities, {'comfyui', 'gpu.nvidia'});
    expect(personal.maxCpu, 8);
    expect(personal.maxRamMiB, 32768);
    expect(personal.maxConcurrent, 1);
    final shared = pools.singleWhere(
      (pool) => pool.toJson()['providerPoolId'] == 'shared-coders',
    );
    expect(shared.capabilities, {'build.linux', 'comfyui', 'gpu.nvidia'});
    expect(shared.maxConcurrent, 2);
  });

  test('refuses stale Fleet state', () {
    expect(
      () => discoverFleetRunnerPools({'stale': true, 'hosts': const []}),
      throwsA(
        isA<ApiError>().having((error) => error.code, 'code', 'fleet_stale'),
      ),
    );
  });

  test('refuses a fresh report that has no enforceable pool membership', () {
    expect(
      () => discoverFleetRunnerPools({
        'stale': false,
        'hosts': [
          {
            'id': 'legacy-host',
            'health': 'ok',
            'drain': false,
            'capabilities': ['runtime-docker'],
            'maxCpu': 4,
            'maxRamMb': 8192,
          },
        ],
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'fleet_pool_unavailable',
        ),
      ),
    );
  });
}
