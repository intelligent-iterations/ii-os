import 'dart:convert';

import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

import 'support/local_agent_engine_fixture.dart';

void main() {
  Map<String, Object?> runtimeProfile() => _profile()
    ..['schema_version'] = 4
    ..['engine'] = 'codex'
    ..['repository_actions'] = {'mode': 'maintain_dev'}
    ..remove('fleet')
    ..remove('secret_injection')
    ..['runtime'] = {
      'configuration': {
        'path': '.ii-os/runtimes/maintainer.json',
        'sha256': 'a' * 64,
      },
      'execution_binding': {
        'path': '.ii-os/runtimes/owned-compute.json',
        'sha256': 'b' * 64,
      },
    };

  test(
    'runtime profile pins configuration and placement without duplicating runtime settings or injecting worker secrets',
    () {
      final profile = AgentPermissionProfile.parse(runtimeProfile());
      expect(profile.schemaVersion, 4);
      expect(profile.runtime!.configurationDigest, 'a' * 64);
      expect(profile.toJson().containsKey('fleet'), isFalse);
      expect(profile.toJson().containsKey('secret_injection'), isFalse);
      expect(() => requireExecutableAgentProfile(profile), returnsNormally);
      expect(
        agentPermissionProfileDigest(
          AgentPermissionProfile.parse(profile.toJson()),
        ),
        agentPermissionProfileDigest(profile),
      );
      final changed = runtimeProfile();
      ((changed['runtime']! as Map<String, Object?>)['configuration']!
              as Map<String, Object?>)['sha256'] =
          'c' * 64;
      expect(
        agentPermissionProfileDigest(AgentPermissionProfile.parse(changed)),
        isNot(agentPermissionProfileDigest(profile)),
      );
    },
  );

  test(
    'runtime profile rejects unpinned, escaping or mixed legacy execution settings',
    () {
      for (final fault in ['digest', 'path', 'legacy']) {
        final value = runtimeProfile();
        final reference =
            (value['runtime']! as Map<String, Object?>)['configuration']!
                as Map<String, Object?>;
        if (fault == 'digest') reference['sha256'] = 'latest';
        if (fault == 'path') {
          reference['path'] = '.ii-os/runtimes/../private.json';
        }
        if (fault == 'legacy') value['fleet'] = _profile()['fleet'];
        expect(
          () => AgentPermissionProfile.parse(value),
          throwsA(isA<ApiError>()),
          reason: fault,
        );
      }
    },
  );

  test('Codex profiles require the native Intel runtime capability', () {
    expect(codexAgentCapabilities, contains('linux-amd64'));
  });

  test('accepts a Fleet permission profile with coupled secret bindings', () {
    final profile = AgentPermissionProfile.parse(_profile());

    expect(profile.id, 'repository-maintainer');
    expect(profile.fleet.runtimeKind, 'docker');
    expect(profile.fleet.capabilities, contains('codex-oauth'));
    expect(profile.fleet.capabilities, contains('codex-sandbox'));
    expect(profile.secretInjection.environment, 'ii-os-agent-maintainer');
    expect(profile.secretInjection.bindings, hasLength(3));
    expect(profile.toJson()['secret_injection'], isA<Map<String, Object?>>());
  });

  test('parses broker-enforced repository modes without widening v1', () {
    final legacy = AgentPermissionProfile.parse(_profile());
    expect(legacy.schemaVersion, 1);
    expect(legacy.engine, 'codex');
    expect(legacy.repository.mode, 'pull_request');
    expect(legacy.repository.mayPublishChanges, isTrue);
    expect(legacy.repository.mayMergeDev, isFalse);

    for (final mode in const [
      'maintain_dev',
      'pull_request',
      'review_pull_requests',
    ]) {
      final json = _profile()
        ..['schema_version'] = 2
        ..['repository_actions'] = {'mode': mode};
      final profile = AgentPermissionProfile.parse(json);
      expect(profile.schemaVersion, 2);
      expect(profile.repository.mode, mode);
      expect(profile.toJson()['repository_actions'], {'mode': mode});
    }
  });

  test('accepts a schema v3 local Qwen engine without Codex credentials', () {
    final engines = exampleLocalEngines();
    final profile = AgentPermissionProfile.parse(
      exampleLocalQwenProfile(_profile()),
      engines: engines,
    );

    expect(profile.schemaVersion, 3);
    expect(profile.engine, 'qwen38-local');
    expect(profile.fleet.capabilities, contains('example-model-cache'));
    expect(profile.fleet.capabilities, contains('example-sandbox'));
    expect(profile.fleet.capabilities, contains('nvidia-gpu'));
    expect(profile.fleet.resources['vram_mb'], 16384);
    expect(profile.fleet.capabilities, isNot(contains('codex-oauth')));
    expect(
      profile.secretInjection.bindings.map((binding) => binding.githubSecret),
      isNot(contains('CODEX_AUTH_JSON')),
    );
    expect(profile.toJson()['engine'], 'qwen38-local');
    expect(
      () => requireExecutableAgentProfile(profile, engines: engines),
      returnsNormally,
    );
  });

  test('rejects a local Qwen profile that retains Codex authority', () {
    final json = exampleLocalQwenProfile(_profile());
    final fleet = json['fleet']! as Map<String, Object?>;
    fleet['capabilities'] = [
      ...(fleet['capabilities']! as List<Object?>),
      'codex-oauth',
    ];

    expect(
      () => AgentPermissionProfile.parse(json, engines: exampleLocalEngines()),
      throwsA(isA<ApiError>()),
    );
  });

  test('rejects a local Qwen profile without the exact VRAM reservation', () {
    final json = exampleLocalQwenProfile(_profile());
    final resources =
        (json['fleet']! as Map<String, Object?>)['resources']!
            as Map<String, Object?>;
    resources.remove('vram_mb');

    expect(
      () => AgentPermissionProfile.parse(json, engines: exampleLocalEngines()),
      throwsA(isA<ApiError>()),
    );
  });

  test('rejects a local Qwen profile the deployment has not configured', () {
    expect(
      () => AgentPermissionProfile.parse(exampleLocalQwenProfile(_profile())),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'agent_engine_not_configured',
        ),
      ),
    );
  });

  test('requires an explicit supported engine in schema v3', () {
    final missing = _codexV3Profile()..remove('engine');
    final unknown = _codexV3Profile()..['engine'] = 'remote-unbounded-agent';

    expect(
      () => AgentPermissionProfile.parse(missing),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => AgentPermissionProfile.parse(unknown),
      throwsA(isA<ApiError>()),
    );
  });

  test('rejects an unknown repository action mode', () {
    final json = _profile()
      ..['schema_version'] = 2
      ..['repository_actions'] = {'mode': 'write_everything'};

    expect(() => AgentPermissionProfile.parse(json), throwsA(isA<ApiError>()));
  });

  test('rejects a secret not backed by a Fleet capability', () {
    final json = _profile();
    final injection = json['secret_injection']! as Map<String, Object?>;
    final bindings = injection['bindings']! as List<Object?>;
    final binding = bindings
        .whereType<Map<String, Object?>>()
        .where((item) => item['id'] == 'codex-auth')
        .single;
    binding['capability'] = 'github-write';

    expect(
      () => AgentPermissionProfile.parse(json),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'agent_permission_invalid',
        ),
      ),
    );
  });

  test('requires a protected environment when secrets are injected', () {
    final json = _profile();
    final injection = json['secret_injection']! as Map<String, Object?>;
    injection['environment'] = '';

    expect(() => AgentPermissionProfile.parse(json), throwsA(isA<ApiError>()));
  });

  test('rejects a mutable Fleet image tag', () {
    final json = _profile();
    final fleet = json['fleet']! as Map<String, Object?>;
    fleet['image'] = 'ghcr.io/example/coder:latest';

    expect(
      () => AgentPermissionProfile.parse(json),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'agent_permission_invalid',
        ),
      ),
    );
  });

  test('rejects unknown fields so approval and runtime digests agree', () {
    final json = Map<String, Object?>.from(_profile());
    json['unreviewed_extension'] = true;

    expect(() => AgentPermissionProfile.parse(json), throwsA(isA<ApiError>()));
  });

  test('rejects every parser shape that the executor rejects', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (json) => json['schema_version'] = 1.0,
      (json) => json.remove('denied_actions'),
      (json) => json['denied_actions'] = null,
      (json) {
        final fleet = json['fleet']! as Map<String, Object?>;
        fleet['runtime_kind'] = 'tart';
        fleet['capabilities'] = [
          ...(fleet['capabilities']! as List<Object?>),
          'runtime-tart',
        ];
      },
      (json) {
        final fleet = json['fleet']! as Map<String, Object?>;
        fleet['capabilities'] = [
          ...(fleet['capabilities']! as List<Object?>),
          'arbitrary-host-access',
        ];
      },
      (json) {
        final resources =
            (json['fleet']! as Map<String, Object?>)['resources']!
                as Map<String, Object?>;
        resources['cpu'] = 2.0;
      },
      (json) {
        final workflow = json['workflow']! as Map<String, Object?>;
        workflow.remove('ref');
      },
      (json) {
        final bindings =
            (json['secret_injection']! as Map<String, Object?>)['bindings']!
                as List<Object?>;
        bindings.removeAt(0);
      },
      (json) {
        final bindings =
            (json['secret_injection']! as Map<String, Object?>)['bindings']!
                as List<Object?>;
        bindings.add(Map<String, Object?>.from(bindings.first as Map));
      },
    ];
    for (final mutate in mutations) {
      final candidate = _deepCopy(_profile());
      mutate(candidate);
      expect(
        () => AgentPermissionProfile.parse(candidate),
        throwsA(isA<ApiError>()),
      );
    }
  });
}

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

Map<String, Object?> _codexV3Profile() => _deepCopy(_profile())
  ..['schema_version'] = 3
  ..['engine'] = codexAgentEngine
  ..['repository_actions'] = {'mode': 'pull_request'};

Map<String, Object?> _profile() => {
  'schema_version': 1,
  'id': 'repository-maintainer',
  'version': '2026-07-17.1',
  'display_name': 'Repository maintainer',
  'description': 'Edit code and run tests without changing ticket records.',
  'allowed_actions': ['Read and edit repository files', 'Run tests'],
  'denied_actions': ['Create or edit GitHub issues'],
  'fleet': {
    'profile': 'ii-os-agent',
    'image':
        'ghcr.io/example/coder@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
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
