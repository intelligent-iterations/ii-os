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

  const permissions = {'organization_projects:write', 'issues:write'};
  final workspace = fixtures.projectWorkspace(
    repositories: {'acme/product', 'acme/retired-repository'},
    resourcePermissions: permissions,
    workspacePermissions: permissions,
  );

  GitHubClient client(
    List<Object?> scopes,
    List<String> operations, {
    String returnedRepository = 'acme/product',
  }) {
    final transport = MockClient((request) async {
      if (request.url.path.endsWith('/access_tokens')) {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final repositories = body['repositories']! as List<Object?>;
        scopes.add(repositories);
        if (repositories.contains('retired-repository')) {
          return http.Response(
            '{"message":"There is at least one repository that does not '
            'exist or is not accessible to the parent installation."}',
            422,
          );
        }
        return _json({
          'token': 'synthetic-scoped-token',
          'expires_at': '2099-01-01T00:00:00Z',
          'permissions': {'organization_projects': 'write', 'issues': 'write'},
        }, 201);
      }
      if (request.url.path == '/repos/acme/product/issues') {
        expect(request.method, 'POST');
        operations.add('create issue');
        return _json(_issue(), 201);
      }
      if (request.url.path == '/repos/acme/product/issues/7') {
        expect(request.method, 'PATCH');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        operations.add('issue ${body['state']}');
        return _json({..._issue(), 'state': body['state']});
      }
      expect(request.url.path, '/graphql');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final query = body['query']! as String;
      if (query.contains('mutation AddIssue')) {
        expect(body['variables'], {
          'projectId': 'PVT_workshop',
          'contentId': 'issue-7',
        });
        operations.add('add project item');
        return _json({
          'data': {
            'addProjectV2ItemById': {
              'item': {'id': 'item-7'},
            },
          },
        });
      }
      if (query.contains('mutation RemoveWorkshopTicket')) {
        expect(body['variables'], {
          'projectId': 'PVT_workshop',
          'itemId': 'item-7',
        });
        operations.add('remove project item');
        return _json({
          'data': {
            'deleteProjectV2Item': {'deletedItemId': 'item-7'},
          },
        });
      }
      expect(query, contains('query Project'));
      operations.add('read project');
      return _json({
        'data': {
          'node': {
            'id': 'PVT_workshop',
            'items': {
              'nodes': [
                {
                  'id': 'item-7',
                  'content': {
                    '__typename': 'Issue',
                    'number': 7,
                    'state': 'OPEN',
                    'body': '',
                    'repository': {'nameWithOwner': returnedRepository},
                  },
                },
              ],
            },
          },
        },
      });
    });
    addTearDown(transport.close);
    return GitHubClient(
      appId: '123',
      privateKey: privateKey,
      httpClient: transport,
    );
  }

  test(
    'human creation adds the issue despite an inaccessible sibling',
    () async {
      final scopes = <Object?>[];
      final operations = <String>[];
      final issue = await client(scopes, operations).createIssue(
        workspace,
        repository: 'acme/product',
        title: 'Human-authored ticket',
        projectId: 'PVT_workshop',
      );
      expect(issue['number'], 7);
      expect(issue['projectItemId'], 'item-7');
      expect(operations, ['create issue', 'add project item']);
      expect(scopes, [
        ['product'],
      ]);
    },
  );

  test('human deletion checks and removes only the selected ticket', () async {
    final scopes = <Object?>[];
    final operations = <String>[];
    final removed = await client(scopes, operations).removeWorkshopTicket(
      workspace,
      repository: 'acme/product',
      issueNumber: 7,
      projectId: 'PVT_workshop',
      itemId: 'item-7',
    );
    expect(removed['removedFromWorkshop'], isTrue);
    expect(operations, ['read project', 'issue closed', 'remove project item']);
    expect(scopes, [
      ['product'],
    ]);
  });

  test('deletion refuses a sibling ticket before either mutation', () async {
    final scopes = <Object?>[];
    final operations = <String>[];
    await expectLater(
      client(
        scopes,
        operations,
        returnedRepository: 'acme/retired-repository',
      ).removeWorkshopTicket(
        workspace,
        repository: 'acme/product',
        issueNumber: 7,
        projectId: 'PVT_workshop',
        itemId: 'item-7',
      ),
      throwsA(
        isA<ApiError>().having((error) => error.code, 'code', 'ticket_changed'),
      ),
    );
    expect(operations, ['read project']);
  });
}

http.Response _json(Map<String, Object?> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Map<String, Object?> _issue() => {
  'node_id': 'issue-7',
  'number': 7,
  'title': 'Human-authored ticket',
  'body': '',
  'state': 'open',
  'html_url': 'https://github.com/acme/product/issues/7',
};
