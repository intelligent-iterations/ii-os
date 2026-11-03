import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os/repositories/agent_permissions_repository.dart';
import 'package:ii_os/services/api_client.dart';

void main() {
  for (final reauthenticate in [false, true]) {
    test('Codex POST serializes reauthenticate=$reauthenticate', () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'data': {
              'session': {'id': 'session-1', 'status': 'dispatching'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(transport.close);
      final repository = AgentPermissionsRepository(
        ApiClient(
          httpClient: transport,
          authTokenProvider: (_) async => 'synthetic-session',
        ),
      );
      if (reauthenticate) {
        await repository.startCodex(
          workspaceId: 'fixture-workspace',
          repository: 'fixture/repo',
          reauthenticate: true,
        );
      } else {
        await repository.startCodex(
          workspaceId: 'fixture-workspace',
          repository: 'fixture/repo',
        );
      }
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(jsonDecode(requests.single.body), {
        'repository': 'fixture/repo',
        'reauthenticate': reauthenticate,
      });
    });
  }

  test('started Codex session unwraps the audited API envelope', () {
    final session = parseStartedCodexSession({
      'data': {
        'session': {
          'id': 'session-1',
          'repository': 'acme-co/example-app',
          'status': 'waiting_for_user',
          'verificationUrl': 'https://auth.openai.com/codex/device',
          'userCode': 'ABCD-EFGH',
          'runUrl': 'https://github.com/example/repository/actions/runs/123',
          'errorCode': '',
          'detail': '',
          'terminal': false,
        },
      },
    });

    expect(session.id, 'session-1');
    expect(session.status, 'waiting_for_user');
    expect(session.waitingForUser, isTrue);
  });
}
