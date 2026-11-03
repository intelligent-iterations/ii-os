import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_app_transport.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:test/test.dart';

import 'github_project_access_test.dart' as workspace_fixtures;
import 'organization_resources_test.dart' as fixtures;

void main() {
  late String privateKey;
  setUpAll(() {
    final generated = Process.runSync('openssl', ['genrsa', '2048']);
    expect(generated.exitCode, 0);
    privateKey = generated.stdout as String;
  });

  test(
    'refresh discovers only its existing installation and no workspace grant',
    () async {
      final requests = <String>[];
      final workspace = workspace_fixtures.projectWorkspace(
        repositories: {'acme/product', 'acme/removed-public'},
        resourcePermissions: {'contents:write', 'pull_requests:write'},
        workspacePermissions: {'contents:write', 'pull_requests:write'},
      );
      final client = GitHubClient(
        appId: '123',
        privateKey: privateKey,
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.url.path == '/app/installations/456/access_tokens') {
            // Discovery reads the accepted installation ceiling; it must not
            // request stale workspace repositories or enumerate sibling Apps.
            expect(request.body, isEmpty);
            return _token();
          }
          expect(request.url.path, '/installation/repositories');
          expect(request.url.queryParameters, {'per_page': '100', 'page': '1'});
          return _inventory(['acme/product', 'acme/private-source']);
        }),
      );
      final accepted = await client.grantedInstallationResources(workspace);
      expect(requests, [
        'POST /app/installations/456/access_tokens',
        'GET /installation/repositories',
      ]);
      expect(accepted.repositories, {'acme/product', 'acme/private-source'});
      expect(accepted.permissions, {'contents:write', 'pull_requests:write'});
      expect(workspace.repositories, {'acme/product', 'acme/removed-public'});
      expect(workspace.containsRepository('acme/private-source'), isFalse);
    },
  );

  test(
    'refresh bounds500 repositories at five pages and six requests',
    () async {
      var calls = 0;
      final transport = GitHubAppTransport(
        appId: '123',
        privateKey: privateKey,
        httpClient: MockClient((request) async {
          calls++;
          if (request.url.path.endsWith('/access_tokens')) return _token();
          final page = int.parse(request.url.queryParameters['page']!);
          expect(page, inInclusiveRange(1, 5));
          return _inventory(
            List.generate(
              100,
              (index) => 'acme/repo-${(page - 1) * 100 + index}',
            ),
            total: 500,
          );
        }),
      );
      addTearDown(transport.close);
      final accepted = await transport.discoverInstallation(303);
      expect(accepted.repositories, hasLength(500));
      expect(accepted.installationId, 303);
      expect(calls, 6);
    },
  );

  for (final scenario in [
    'empty',
    'oversized',
    'duplicate',
    'malformed',
    'incomplete',
    'changed-count',
  ]) {
    test('refresh fails closed for $scenario inventory', () async {
      var calls = 0;
      final transport = GitHubAppTransport(
        appId: '123',
        privateKey: privateKey,
        httpClient: MockClient((request) async {
          calls++;
          if (request.url.path.endsWith('/access_tokens')) return _token();
          final page = int.parse(request.url.queryParameters['page']!);
          return switch (scenario) {
            'empty' => _inventory([]),
            'oversized' => _inventory(['acme/product'], total: 501),
            'duplicate' => _inventory(['acme/product', 'acme/product']),
            'malformed' => _inventory(['acme/product', '../private-source']),
            'incomplete' => _inventory(['acme/repo-$page'], total: 6),
            _ => _inventory(['acme/repo-$page'], total: page == 1 ? 2 : 3),
          };
        }),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.discoverInstallation(303),
        throwsA(isA<ApiError>()),
      );
      expect(calls, lessThanOrEqualTo(6));
      if (scenario == 'incomplete') expect(calls, 6);
    });
  }

  test('refresh rejects invalid installation before HTTP', () async {
    final transport = GitHubAppTransport(
      appId: '123',
      privateKey: privateKey,
      httpClient: MockClient(
        (_) async => fail('invalid ID must not contact GitHub'),
      ),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.discoverInstallation(0),
      throwsA(isA<ApiError>()),
    );
  });

  for (final tokenResponse in [true, false]) {
    test(
      'refresh bounds ${tokenResponse ? 'token' : 'repository'} response bytes',
      () async {
        final transport = GitHubAppTransport(
          appId: '123',
          privateKey: privateKey,
          httpClient: MockClient((request) async {
            if (!tokenResponse && request.url.path.endsWith('/access_tokens')) {
              return _token();
            }
            return http.Response(
              ' ' * ((tokenResponse ? 64 * 1024 : 2 * 1024 * 1024) + 1),
              200,
            );
          }),
        );
        addTearDown(transport.close);
        await expectLater(
          transport.discoverInstallation(303),
          throwsA(
            isA<ApiError>().having(
              (error) => error.code,
              'code',
              'github_response_too_large',
            ),
          ),
        );
      },
    );
  }

  test('refresh enforces the byte limit on an unknown-length stream', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>();
    stream.onCancel = () {
      cancelled = true;
    };
    final transport = GitHubAppTransport(
      appId: '123',
      privateKey: privateKey,
      httpClient: _StreamingClient((request) async {
        stream.add(List.filled(64 * 1024 + 1, 32));
        return http.StreamedResponse(stream.stream, 200);
      }),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.discoverInstallation(303),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'github_response_too_large',
        ),
      ),
    );
    expect(cancelled, isTrue);
    await stream.close();
  });

  test(
    'refresh shares one five-second deadline across send and body',
    () async {
      var cancelled = false;
      late Timer responseTimer;
      final stream = StreamController<List<int>>();
      stream.onListen = () {
        responseTimer = Timer(const Duration(seconds: 2), () {
          stream.add(utf8.encode(_token().body));
          unawaited(stream.close());
        });
      };
      stream.onCancel = () {
        responseTimer.cancel();
        cancelled = true;
      };
      final transport = GitHubAppTransport(
        appId: '123',
        privateKey: privateKey,
        httpClient: _StreamingClient((request) async {
          await Future<void>.delayed(const Duration(seconds: 4));
          return http.StreamedResponse(stream.stream, 200);
        }),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.discoverInstallation(303),
        throwsA(isA<TimeoutException>()),
      );
      expect(cancelled, isTrue);
      await stream.close();
    },
  );

  test('installation discovery refuses malformed repository names', () async {
    final transport = GitHubAppTransport(
      appId: '123',
      privateKey: privateKey,
      httpClient: MockClient((request) async {
        if (request.url.path == '/app/installations') {
          return _json([
            {'id': 303},
          ]);
        }
        if (request.url.path.endsWith('/access_tokens')) {
          return _json({
            'token': 'synthetic-discovery-token',
            'permissions': {'contents': 'write'},
          });
        }
        return _json({
          'total_count': 1,
          'repositories': [
            {'full_name': 'https://foreign.invalid/acme/private-source'},
          ],
        });
      }),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.discoverInstallations(),
      throwsA(isA<ApiError>()),
    );
  });

  test('refresh replaces stale repositories and preserves other resources', () {
    const organizationId = '11111111-1111-4111-8111-111111111111';
    const workspaceId = '22222222-2222-4222-8222-222222222222';
    final connection = fixtures.legacyWorkspaceConnection(workspaceId);
    final existingGcp = OrganizationGcpResource(
      id: legacyGcpResourceId,
      name: 'Existing reviewed GCP name',
      connection: connection,
      permissionEnvelope: const {'workflows.upload'},
      legacySourceWorkspaceId: workspaceId,
    );
    final existingGitHub = OrganizationGitHubResource(
      id: legacyGithubResourceId,
      name: 'Existing reviewed GitHub name',
      secretGcpResourceId: legacyGcpResourceId,
      appId: connection.githubAppId,
      privateKeySecret: connection.githubAppSecret,
      installationId: 303,
      repositories: const {'acme/product', 'acme/removed-public'},
      permissionEnvelope: const {'contents:write', 'pull_requests:write'},
    );
    final siblingResource = fixtures.github(
      'github_sibling',
      gcpResourceId: legacyGcpResourceId,
      installationId: 404,
      repositories: {'acme/sibling'},
    );
    final current = OrganizationResourceCatalog(
      gcpResources: [existingGcp],
      githubResources: [existingGitHub, siblingResource],
      runnerPools: const [],
    );
    final siblingGrant = WorkspaceResourceGrants(
      gcp: const [],
      github: const [
        WorkspaceGitHubGrant(
          resourceId: 'github_sibling',
          repositories: {'acme/sibling'},
          permissions: {'contents:write'},
          primary: true,
        ),
      ],
      runners: const [],
    );
    final beforeGrant = jsonEncode(siblingGrant.toJson());
    final refreshed = promoteLegacyWorkspaceResources(
      current: current,
      organizationId: organizationId,
      sourceWorkspaceId: workspaceId,
      connection: connection,
      installationId: 303,
      repositories: const {'acme/product', 'acme/private-source'},
      githubPermissions: const {'contents:write', 'pull_requests:write'},
    );
    expect(refreshed.gcp(legacyGcpResourceId), same(existingGcp));
    expect(refreshed.github('github_sibling'), same(siblingResource));
    final updated = refreshed.github(legacyGithubResourceId)!;
    expect(updated.repositories, {'acme/product', 'acme/private-source'});
    expect(updated.repositories, isNot(contains('acme/removed-public')));
    expect(updated.name, existingGitHub.name);
    expect(updated.privateKeySecret, existingGitHub.privateKeySecret);
    expect(updated.appId, existingGitHub.appId);
    expect(updated.installationId, existingGitHub.installationId);
    expect(updated.secretGcpResourceId, existingGitHub.secretGcpResourceId);
    expect(jsonEncode(siblingGrant.toJson()), beforeGrant);
    expect(siblingGrant.validateAgainst(refreshed), isEmpty);
  });
}

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _token() => _json({
  'token': 'synthetic-discovery-token',
  'permissions': {'contents': 'write', 'pull_requests': 'write'},
});

http.Response _inventory(List<String> repositories, {int? total}) => _json({
  'total_count': total ?? repositories.length,
  'repositories': repositories.map((name) => {'full_name': name}).toList(),
});

final class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
}
