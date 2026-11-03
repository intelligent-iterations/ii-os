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
  const permissions = {
    'contents:write',
    'pull_requests:write',
    'deployments:read',
    'actions:write',
    'secrets:write',
  };
  final workspace = fixtures.projectWorkspace(
    repositories: {'acme/product', 'acme/retired-repository'},
    resourcePermissions: permissions,
    workspacePermissions: permissions,
  );

  GitHubClient client(List<Object?> scopes, {bool resolveMerge = false}) {
    final transport = MockClient((request) async {
      if (request.url.path.endsWith('/access_tokens')) {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final repositories = body['repositories']! as List;
        scopes.add(repositories);
        if (repositories.contains('retired-repository')) {
          return http.Response(
            '{"message":"Repository is not accessible to the parent installation."}',
            422,
          );
        }
        return http.Response(
          jsonEncode({
            'token': 'synthetic-scoped-token',
            'expires_at': '2099-01-01T00:00:00Z',
            'permissions': {
              'contents': 'write',
              'pull_requests': 'write',
              'deployments': 'read',
              'actions': 'write',
              'secrets': 'write',
            },
          }),
          201,
        );
      }
      if (request.url.path == '/repos/acme/product/pulls/7') {
        return http.Response(
          jsonEncode({
            'number': 7,
            'html_url': 'https://github.com/acme/product/pull/7',
            'state': 'closed',
            'merged': true,
            'merge_commit_sha': resolveMerge
                ? null
                : 'cccccccccccccccccccccccccccccccccccccccc',
            'head': {
              'ref': 'ii-os-agent/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'sha': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'repo': null,
            },
            'base': {
              'ref': 'dev',
              'sha': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              'repo': {'full_name': 'acme/product'},
            },
          }),
          200,
        );
      }
      if (request.url.path == '/graphql') {
        return http.Response(
          jsonEncode({
            'data': {
              'repository': {
                'nameWithOwner': 'acme/product',
                'pullRequest': {
                  'number': 7,
                  'url': 'https://github.com/acme/product/pull/7',
                  'merged': true,
                  'mergeCommit': {
                    'oid': 'cccccccccccccccccccccccccccccccccccccccc',
                  },
                },
              },
            },
          }),
          200,
        );
      }
      if (request.url.path == '/repos/acme/product/deployments') {
        return http.Response('[]', 200);
      }
      if (request.url.path.contains('/environments/')) {
        return http.Response('{"message":"Not Found"}', 404);
      }
      fail('Unexpected fixture provider path: ${request.url.path}');
    });
    addTearDown(transport.close);
    return GitHubClient(
      appId: '123',
      privateKey: privateKey,
      httpClient: transport,
    );
  }

  test(
    'PR merge fallback stays scoped despite an inaccessible sibling',
    () async {
      final scopes = <Object?>[];
      final pull = await client(
        scopes,
        resolveMerge: true,
      ).getPullRequest(workspace, repository: 'acme/product', number: 7);
      expect(
        pull['mergeCommitSha'],
        'cccccccccccccccccccccccccccccccccccccccc',
      );
      expect(scopes, [
        ['product'],
      ]);
    },
  );

  test(
    'QA deployment lookup stays scoped despite an inaccessible sibling',
    () async {
      final scopes = <Object?>[];
      final pull = await client(scopes).getPullRequestWithQaDeployment(
        workspace,
        repository: 'acme/product',
        number: 7,
      );
      expect(pull['merged'], true);
      expect(pull['qaDeployment'], isA<Map<String, Object?>>());
      expect(scopes, [
        ['product'],
      ]);
    },
  );

  test(
    'Codex dispatch reaches its own readiness check instead of a sibling grant',
    () async {
      final scopes = <Object?>[];
      await expectLater(
        client(scopes).requireCodexAuthDispatchReady(
          workspace,
          repository: 'acme/product',
          trustedSourceRef: 'refs/tags/fixture',
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'codex_auth_environment_unprotected',
          ),
        ),
      );
      expect(scopes, [
        ['product'],
      ]);
    },
  );
}
