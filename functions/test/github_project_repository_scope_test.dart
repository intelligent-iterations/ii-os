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
    // Ephemeral signing material only; no stored key or provider is contacted.
    final generated = Process.runSync('openssl', ['genrsa', '2048']);
    expect(generated.exitCode, 0, reason: 'Generate an isolated test signer.');
    privateKey = generated.stdout as String;
  });

  final workspace = fixtures.projectWorkspace(
    repositories: {'acme/product', 'acme/renamed-framework'},
    resourcePermissions: {'organization_projects:write', 'issues:read'},
    workspacePermissions: {'organization_projects:write', 'issues:read'},
  );

  GitHubClient client(
    List<Object?> scopes, {
    bool rejectStale = false,
    String returnedRepository = 'acme/product',
  }) {
    final transport = MockClient((request) async {
      if (request.url.path.endsWith('/access_tokens')) {
        final scope = jsonDecode(request.body) as Map<String, Object?>;
        scopes.add(scope['repositories']);
        if (rejectStale &&
            (scope['repositories']! as List).contains('renamed-framework')) {
          return http.Response(
            '{"message":"There is at least one repository that does not '
            'exist or is not accessible to the parent installation."}',
            422,
          );
        }
        return http.Response(
          '{"token":"synthetic-installation","expires_at":"2099-01-01T00:00:00Z",'
          '"permissions":{"organization_projects":"write","issues":"read"}}',
          201,
        );
      }
      if (request.url.path == '/repos/acme/product') {
        return http.Response('{"id":100,"full_name":"acme/product"}', 200);
      }
      expect(request.url.path, '/graphql');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if ((body['query']! as String).contains('query AgentQueueItem')) {
        return http.Response(
          jsonEncode({
            'data': {
              'node': {
                'id': (body['variables']! as Map)['id'],
                'project': {'id': 'PVT_workshop'},
                'content': {
                  'repository': {'nameWithOwner': returnedRepository},
                },
              },
            },
          }),
          200,
        );
      }
      return http.Response(
        '{"data":{"node":{"id":"PVT_workshop","fields":{"nodes":[]},'
        '"items":{"nodes":[]}}}}',
        200,
      );
    });
    final result = GitHubClient(
      appId: '123',
      privateKey: privateKey,
      httpClient: transport,
    );
    addTearDown(transport.close);
    return result;
  }

  test(
    'selected project repository excludes an inaccessible sibling grant',
    () async {
      final scopes = <Object?>[];
      final project = await client(
        scopes,
        rejectStale: true,
      ).getProject(workspace, 'PVT_workshop', repository: 'acme/product');
      expect(project['id'], 'PVT_workshop');
      expect(scopes, [
        ['product'],
      ]);
    },
  );

  test(
    'selected repository outside the workspace fails before token minting',
    () async {
      final scopes = <Object?>[];
      await expectLater(
        client(
          scopes,
        ).getProject(workspace, 'PVT_workshop', repository: 'acme/not-granted'),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'repository_not_allowed',
          ),
        ),
      );
      expect(scopes, isEmpty);
    },
  );

  test(
    'project callers without a selected repository keep workspace scope',
    () async {
      final scopes = <Object?>[];
      await client(scopes).getProject(workspace, 'PVT_workshop');
      expect(scopes, [
        ['product', 'renamed-framework'],
      ]);
    },
  );

  test('different selected repositories do not share cached tokens', () async {
    final scopes = <Object?>[];
    final github = client(scopes);
    for (final repository in ['acme/product', 'acme/renamed-framework']) {
      await github.getProject(
        workspace,
        'PVT_workshop',
        repository: repository,
      );
    }
    expect(scopes, [
      ['product'],
      ['renamed-framework'],
    ]);
  });

  test(
    'Deploy reads and claim rereads exclude a stale sibling grant',
    () async {
      final scopes = <Object?>[];
      final github = client(scopes, rejectStale: true);
      await github.readAgentQueueProject(
        workspace,
        'PVT_workshop',
        repository: 'acme/product',
      );
      final item = await github.readAgentQueueProjectItem(
        workspace,
        projectId: 'PVT_workshop',
        itemId: 'item-1',
        repository: 'acme/product',
      );
      expect(item['id'], 'item-1');
      expect(scopes, [
        ['product'],
      ]);
    },
  );

  test(
    'claim reread rejects a provider item from a different repository',
    () async {
      await expectLater(
        client([], returnedRepository: 'acme/other').readAgentQueueProjectItem(
          workspace,
          projectId: 'PVT_workshop',
          itemId: 'item-1',
          repository: 'acme/product',
        ),
        throwsA(
          isA<ApiError>().having(
            (e) => e.code,
            'code',
            'agent_ticket_repository_mismatch',
          ),
        ),
      );
    },
  );

  test(
    'running and reset status mutations exclude a stale sibling grant',
    () async {
      final scopes = <Object?>[];
      final github = client(scopes, rejectStale: true);
      await github.updateProjectItemField(
        workspace,
        projectId: 'PVT_workshop',
        itemId: 'item-1',
        fieldId: 'status',
        value: {'singleSelectOptionId': 'running'},
        repository: 'acme/product',
      );
      await github.clearProjectItemField(
        workspace,
        projectId: 'PVT_workshop',
        itemId: 'item-1',
        fieldId: 'status',
        repository: 'acme/product',
      );
      expect(scopes, [
        ['product'],
      ]);
    },
  );

  test(
    'selected repository setup ignores an inaccessible sibling grant',
    () async {
      final scopes = <Object?>[];
      final checks = await client(
        scopes,
        rejectStale: true,
      ).inspectGitHubSetupRepository(workspace, repository: 'acme/product');
      expect(checks.first['status'], 'passed');
      expect(scopes, [
        ['product'],
      ]);
    },
  );
}
