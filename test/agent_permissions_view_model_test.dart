import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os/models/agent_permission.dart';
import 'package:ii_os/models/codex_auth_session.dart';
import 'package:ii_os/repositories/agent_permissions_repository.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/view_models/agent_permissions_view_model.dart';

void main() {
  final retryCases = [
    (
      code: '',
      status: 'failed',
      terminal: true,
      repository: 'fixture/repo',
      expected: false,
    ),
    (
      code: 'codex_auth_refresh_failed',
      status: 'failed',
      terminal: true,
      repository: 'fixture/repo',
      expected: true,
    ),
    (
      code: 'codex_auth_request_unauthorized',
      status: 'failed',
      terminal: true,
      repository: 'fixture/repo',
      expected: true,
    ),
    (
      code: 'codex_auth_repository_secret_invalid',
      status: 'failed',
      terminal: true,
      repository: 'fixture/repo',
      expected: true,
    ),
    for (final code in [
      'codex_auth_network_failed',
      'codex_auth_usage_limited',
      'codex_auth_smoke_output_missing',
      'codex_auth_smoke_timeout',
      'codex_auth_smoke_failed',
    ])
      (
        code: code,
        status: 'failed',
        terminal: true,
        repository: 'fixture/repo',
        expected: false,
      ),
    (
      code: 'codex_auth_refresh_failed',
      status: 'validating',
      terminal: false,
      repository: 'fixture/repo',
      expected: false,
    ),
    (
      code: 'codex_auth_refresh_failed',
      status: 'succeeded',
      terminal: true,
      repository: 'fixture/repo',
      expected: false,
    ),
    (
      code: 'codex_auth_refresh_failed',
      status: 'failed',
      terminal: true,
      repository: 'other/repo',
      expected: false,
    ),
  ];
  for (final scenario in retryCases) {
    test('human Codex retry scopes reauthentication to $scenario', () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'data': {
              'session': {
                'id': 'next-session',
                'repository': 'fixture/repo',
                'status': 'failed',
                'terminal': true,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(transport.close);
      final model = AgentPermissionsViewModel(
        workspaceId: 'fixture-workspace',
        repositories: const ['fixture/repo'],
        initialRepository: 'fixture/repo',
        repositoryApi: AgentPermissionsRepository(
          ApiClient(
            httpClient: transport,
            authTokenProvider: (_) async => 'synthetic-session',
          ),
        ),
      );
      addTearDown(model.dispose);
      if (scenario.code.isNotEmpty) {
        model.codexSession = CodexAuthSessionModel.fromJson({
          'id': 'previous-session',
          'repository': scenario.repository,
          'status': scenario.status,
          'errorCode': scenario.code,
          'terminal': scenario.terminal,
        });
      }
      await Future<void>.delayed(Duration.zero);
      expect(requests, isEmpty, reason: 'a terminal error never starts a run');
      await model.startCodexVerification();
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {
        'repository': 'fixture/repo',
        'reauthenticate': scenario.expected,
      });
    });
  }

  test('installed runtime configuration survives default shape selection', () {
    final transport = MockClient((_) async => http.Response('', 500));
    addTearDown(transport.close);
    final json = {
      ...defaultAgentPermissionJson(),
      'schema_version': 4,
      'engine': 'codex',
      'version': 'reviewed-runtime-1',
      'runtime': {
        'configuration': {
          'path': '.ii-os/runtimes/agent.json',
          'sha256': 'a' * 64,
        },
        'execution_binding': {
          'path': '.ii-os/runtimes/binding.json',
          'sha256': 'b' * 64,
        },
      },
    }..removeWhere((key, _) => {'fleet', 'secret_injection'}.contains(key));
    final installed = AgentPermissionModel.fromJson(json);
    final model = AgentPermissionsViewModel(
      workspaceId: 'fixture-workspace',
      repositories: const ['fixture/repo'],
      initialRepository: 'fixture/repo',
      repositoryApi: AgentPermissionsRepository(
        ApiClient(httpClient: transport),
      ),
    )..profiles = [installed];
    addTearDown(model.dispose);
    expect(model.permissionShapes.first, same(installed));
    expect(model.hasRecommendedAccess, isTrue);
  });

  test('only an invalid installed profile is presented as outdated access', () {
    expect(
      isOutdatedAgentAccess(
        const ApiFailure(
          'agent_permission_invalid',
          'The installed profile is no longer valid.',
        ),
      ),
      isTrue,
    );
    expect(
      isOutdatedAgentAccess(
        const ApiFailure('request_failed', 'The request failed.'),
      ),
      isFalse,
    );
  });
}
