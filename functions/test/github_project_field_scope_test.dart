import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:test/test.dart';

import 'github_project_access_test.dart' as fixtures;

void main() {
  late String privateKey;
  setUpAll(() {
    final generated = Process.runSync('openssl', ['genrsa', '2048']);
    expect(generated.exitCode, 0);
    privateKey = generated.stdout as String;
  });
  final workspace = fixtures.projectWorkspace(
    resourcePermissions: {'organization_projects:write'},
    workspacePermissions: {'organization_projects:write'},
  );
  const fieldId = 'PVTSSF_example';
  const options = <Map<String, Object?>>[
    {'name': 'Todo', 'color': 'GRAY', 'description': ''},
  ];

  GitHubClient client(Object? node, List<String> queries) {
    final transport = MockClient((request) async {
      if (request.url.path.endsWith('/access_tokens')) {
        return http.Response(
          '{"token":"synthetic-installation","expires_at":"2099-01-01T00:00:00Z",'
          '"permissions":{"organization_projects":"write"}}',
          201,
        );
      }
      expect(request.url.path, '/graphql');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final query = body['query']! as String;
      queries.add(query);
      if (query.contains('mutation UpdateOptions')) {
        return http.Response('{"data":{"updateProjectV2Field":{}}}', 200);
      }
      expect((body['variables']! as Map)['fieldId'], fieldId);
      return http.Response(
        jsonEncode({
          'data': {'node': node},
        }),
        200,
      );
    });
    addTearDown(transport.close);
    return GitHubClient(
      appId: '123',
      privateKey: privateKey,
      httpClient: transport,
    );
  }

  for (final entry in <String, Object?>{
    'another project': {
      'id': fieldId,
      'project': {'id': 'PVT_other'},
    },
    'a missing field': null,
    'an unexpected node': {'id': fieldId},
    'a mismatched field': {
      'id': 'PVTSSF_other',
      'project': {'id': 'PVT_workshop'},
    },
  }.entries) {
    test('field options reject ${entry.key} before any mutation', () async {
      final queries = <String>[];
      await expectLater(
        client(entry.value, queries).updateProjectFieldOptions(
          workspace,
          projectId: 'PVT_workshop',
          fieldId: fieldId,
          options: options,
        ),
        throwsA(
          isA<ApiError>()
              .having((error) => error.status, 'status', 403)
              .having(
                (error) => error.code,
                'code',
                'project_field_not_allowed',
              ),
        ),
      );
      expect(queries, hasLength(1));
      expect(queries.single, isNot(contains('mutation')));
    });
  }

  test('an owned field is checked before its options are updated', () async {
    final queries = <String>[];
    await client({
      'id': fieldId,
      'project': {'id': 'PVT_workshop'},
    }, queries).updateProjectFieldOptions(
      workspace,
      projectId: 'PVT_workshop',
      fieldId: fieldId,
      options: options,
    );
    expect(queries, hasLength(2));
    expect(queries.first, contains('project { id }'));
    expect(queries.last, contains('mutation UpdateOptions'));
  });
}
