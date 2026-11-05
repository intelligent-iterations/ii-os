import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/organization_repository.dart';
import 'package:ii_os/services/api_client.dart';

void main() {
  test('your runners are saved by id with the customer provider', () async {
    final requests = <http.Request>[];
    final repository = _repository((request) async {
      requests.add(request);
      return _json({'data': <String, Object?>{}}, 200);
    });

    await repository.saveRunnerPool(
      organizationId: 'org-1',
      resource: const CustomerRunnerPoolInput(
        name: 'GPU runners',
        runnerGroup: 'gpu-runners',
        capabilities: {'gpu.nvidia'},
        maxCpu: 16,
        maxRamMiB: 65536,
        maxConcurrent: 2,
      ).toDraft('runner_gpu_runners'),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'PUT');
    expect(
      requests.single.url.queryParameters['route'],
      'v1/organizations/org-1/resources/runners/runner_gpu_runners',
    );
    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect(body['provider'], 'customer');
    expect(body['providerPoolId'], 'gpu-runners');
    expect(body['active'], isTrue);
  });

  // Each row is the error envelope the server actually sends, so the mapping
  // is proven against the shape the client receives, not a thrown Dart object.
  final syncCases = <String, RunnerPoolFailureKind>{
    'fleet_not_connected': RunnerPoolFailureKind.notReported,
    'fleet_stale': RunnerPoolFailureKind.staleReport,
    'fleet_report_invalid': RunnerPoolFailureKind.noReportedCapacity,
    'fleet_capacity_unavailable': RunnerPoolFailureKind.noReportedCapacity,
    'fleet_pool_unavailable': RunnerPoolFailureKind.noReportedCapacity,
    'fleet_pool_limit': RunnerPoolFailureKind.limitReached,
  };
  for (final entry in syncCases.entries) {
    test('sync refusal ${entry.key} maps to ${entry.value.name}', () async {
      final repository = _repository((_) async => _error(409, entry.key));

      await expectLater(
        repository.syncFleetRunnerPool(organizationId: 'org-1'),
        throwsA(
          isA<RunnerPoolFailure>().having(
            (failure) => failure.kind,
            'kind',
            entry.value,
          ),
        ),
      );
    });
  }

  final saveCases = <String, (int, String, Object?, RunnerPoolFailureKind)>{
    'pool limit': (
      400,
      'invalid_organization_resources',
      {
        'errors': ['too_many_runner_pools'],
      },
      RunnerPoolFailureKind.limitReached,
    ),
    'invalid values': (
      400,
      'invalid_organization_resources',
      {
        'errors': ['invalid_runner_pool'],
      },
      RunnerPoolFailureKind.invalid,
    ),
    'reported pool': (
      409,
      'runner_pool_reported',
      null,
      RunnerPoolFailureKind.reportedPool,
    ),
    'role refusal': (403, 'forbidden', null, RunnerPoolFailureKind.forbidden),
    'server failure': (500, 'internal', null, RunnerPoolFailureKind.unknown),
  };
  for (final entry in saveCases.entries) {
    test('save refusal for ${entry.key} names its cause', () async {
      final (status, code, details, kind) = entry.value;
      final repository = _repository(
        (_) async => _error(status, code, details: details),
      );

      await expectLater(
        repository.saveRunnerPool(
          organizationId: 'org-1',
          resource: const CustomerRunnerPoolInput(
            name: 'GPU runners',
            runnerGroup: 'gpu-runners',
            capabilities: {'gpu.nvidia'},
            maxCpu: 16,
            maxRamMiB: 65536,
            maxConcurrent: 2,
          ).toDraft('runner_gpu_runners'),
        ),
        throwsA(
          isA<RunnerPoolFailure>().having(
            (failure) => failure.kind,
            'kind',
            kind,
          ),
        ),
      );
    });
  }
}

OrganizationRepository _repository(
  Future<http.Response> Function(http.Request request) handler,
) {
  final transport = MockClient(handler);
  addTearDown(transport.close);
  return OrganizationRepository(
    ApiClient(
      httpClient: transport,
      baseUrl: 'https://ii-os.example.com/api',
      reportFailures: false,
      authTokenProvider: (_) async => 'synthetic-session',
    ),
  );
}

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _error(int status, String code, {Object? details}) => _json({
  'error': {
    'code': code,
    'message': 'Synthetic server message.',
    'details': ?details,
  },
}, status);
