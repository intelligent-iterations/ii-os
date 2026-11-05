import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:test/test.dart';

import 'github_project_access_test.dart' as fixtures;
import 'support/local_agent_engine_fixture.dart';

void main() {
  late String privateKey;
  setUpAll(() {
    final generated = Process.runSync('openssl', ['genrsa', '2048']);
    expect(generated.exitCode, 0);
    privateKey = generated.stdout as String;
  });
  const permissions = {'contents:read'};
  final workspace = fixtures.projectWorkspace(
    resourcePermissions: permissions,
    workspacePermissions: permissions,
  );
  const directory = '/repos/acme/product/contents/.ii-os/agent-permissions';

  GitHubClient client(
    Map<String, Map<String, Object?>> files, {
    AgentEngineCatalog? engines,
  }) {
    final transport = MockClient((request) async {
      if (request.url.path.endsWith('/access_tokens')) {
        return http.Response(
          jsonEncode({
            'token': 'synthetic-scoped-token',
            'expires_at': '2099-01-01T00:00:00Z',
            'permissions': {'contents': 'read'},
          }),
          201,
        );
      }
      if (request.url.path == directory) {
        return http.Response(
          jsonEncode([
            for (final name in files.keys) {'name': name, 'type': 'file'},
          ]),
          200,
        );
      }
      final name = request.url.pathSegments.last;
      final file = files[name];
      if (request.url.path == '$directory/$name' && file != null) {
        return http.Response(
          jsonEncode({
            'encoding': 'base64',
            'sha': 'a' * 40,
            'content': base64Encode(utf8.encode(jsonEncode(file))),
          }),
          200,
        );
      }
      fail('Unexpected fixture provider path: ${request.url.path}');
    });
    addTearDown(transport.close);
    return engines == null
        ? GitHubClient(
            appId: '123',
            privateKey: privateKey,
            httpClient: transport,
          )
        : GitHubClient(
            appId: '123',
            privateKey: privateKey,
            httpClient: transport,
            agentEngines: engines,
          );
  }

  Future<List<String>> listedIds(GitHubClient github) async => [
    for (final profile in await github.listAgentPermissionProfiles(
      workspace,
      repository: 'acme/product',
      ref: 'dev',
    ))
      profile['id']! as String,
  ];

  final codex = _codexProfile();
  final qwen = exampleLocalQwenProfile(codex);

  test(
    'an unconfigured deployment does not offer local Qwen profiles',
    () async {
      expect(
        await listedIds(
          client({'maintainer.json': codex, 'qwen-maintainer.json': qwen}),
        ),
        ['repository-maintainer'],
      );
    },
  );

  test('a configured deployment offers its local Qwen profiles', () async {
    expect(
      await listedIds(
        client({
          'maintainer.json': codex,
          'qwen-maintainer.json': qwen,
        }, engines: exampleLocalEngines()),
      ),
      unorderedEquals([
        'repository-maintainer',
        'qwen38-repository-maintainer',
      ]),
    );
  });

  test('a configured deployment still refuses a mismatched profile', () async {
    final mismatched = exampleLocalQwenProfile(codex);
    ((mismatched['fleet']! as Map)['resources']! as Map)['vram_mb'] = 24576;

    await expectLater(
      listedIds(
        client({
          'maintainer.json': codex,
          'qwen-maintainer.json': mismatched,
        }, engines: exampleLocalEngines()),
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'agent_permission_invalid',
        ),
      ),
    );
  });
}

Map<String, Object?> _codexProfile() => {
  'schema_version': 1,
  'id': 'repository-maintainer',
  'version': '2026-07-17.1',
  'display_name': 'Repository maintainer',
  'description': 'Edit code and run tests without changing ticket records.',
  'allowed_actions': ['Read and edit repository files', 'Run tests'],
  'denied_actions': ['Create or edit GitHub issues'],
  'fleet': {
    'profile': 'ii-os-agent',
    'image': 'ghcr.io/example/coder@sha256:${'a' * 64}',
    'runtime_kind': 'docker',
    'resources': {'ram_mb': 4096, 'cpu': 2, 'disk_gb': 40, 'timeout_s': 1800},
    'capabilities': [
      'runtime-docker',
      'auto-agent',
      'github-app-token',
      'codex-oauth',
      'codex-sandbox',
      'agent-usage-reporting',
      'linux-amd64',
    ],
  },
  'secret_injection': {
    'environment': 'ii-os-agent-maintainer',
    'bindings': [
      {
        'id': 'github-app-token',
        'capability': 'github-app-token',
        'github_secret': 'IIAUTO_GITHUB_TOKEN',
        'target': 'file',
        'target_name': 'GITHUB_TOKEN_FILE',
      },
      {
        'id': 'codex-auth',
        'capability': 'codex-oauth',
        'github_secret': 'CODEX_AUTH_JSON',
        'target': 'file',
        'target_name': 'CODEX_AUTH_JSON_FILE',
      },
      {
        'id': 'agent-usage',
        'capability': 'agent-usage-reporting',
        'github_secret': 'II_OS_AGENT_USAGE_API_KEY',
        'target': 'file',
        'target_name': 'AGENT_USAGE_KEY_FILE',
      },
    ],
  },
  'workflow': {'file': 'ii-os-agent-task.yml', 'ref': 'dev'},
};
