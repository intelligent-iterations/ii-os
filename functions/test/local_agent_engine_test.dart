import 'dart:convert';
import 'dart:io';

import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

import 'support/local_agent_engine_fixture.dart';

void main() {
  Matcher notConfigured() => throwsA(
    isA<ApiError>()
        .having((error) => error.code, 'code', 'agent_engine_not_configured')
        .having((error) => error.details, 'details', {
          'engine': qwen38LocalAgentEngine,
          'setting': localAgentEnginesSetting,
        }),
  );
  Matcher invalidProfile() => throwsA(
    isA<ApiError>().having(
      (error) => error.code,
      'code',
      'agent_permission_invalid',
    ),
  );

  group('an unconfigured deployment', () {
    test('offers only the Codex engine', () {
      final engines = AgentEngineCatalog.fromBase64('');

      expect(engines.engines, {codexAgentEngine});
      expect(engines.offers(codexAgentEngine), isTrue);
      expect(engines.offers(qwen38LocalAgentEngine), isFalse);
      expect(AgentEngineCatalog.codexOnly.engines, {codexAgentEngine});
    });

    test('rejects a local Qwen profile by name', () {
      final profile = exampleLocalQwenProfile(_codexProfile());

      expect(() => AgentPermissionProfile.parse(profile), notConfigured());
      expect(
        () => AgentPermissionProfile.parse(
          profile,
          engines: AgentEngineCatalog.fromBase64(''),
        ),
        notConfigured(),
      );
      expect(
        () => agentCapabilitiesForEngine(qwen38LocalAgentEngine),
        notConfigured(),
      );
    });

    test('rejects a runtime-pinned local Qwen profile by name', () {
      expect(
        () => AgentPermissionProfile.parse(_runtimeProfile()),
        notConfigured(),
      );
    });
  });

  group('a configured deployment', () {
    final engines = exampleLocalEngines();

    test('accepts exactly the configured profile and capabilities', () {
      final profile = AgentPermissionProfile.parse(
        exampleLocalQwenProfile(_codexProfile()),
        engines: engines,
      );

      expect(engines.engines, {codexAgentEngine, qwen38LocalAgentEngine});
      expect(profile.engine, qwen38LocalAgentEngine);
      expect(profile.fleet.profile, 'example-gpu-coder');
      expect(
        profile.fleet.capabilities.toSet(),
        (exampleLocalQwenPolicy['capabilities']! as List).toSet(),
      );
      expect(profile.fleet.resources['vram_mb'], 16384);
      expect(
        agentCapabilitiesForEngine(qwen38LocalAgentEngine, engines),
        (exampleLocalQwenPolicy['capabilities']! as List).toSet(),
      );
      expect(
        () => requireExecutableAgentProfile(profile, engines: engines),
        returnsNormally,
      );
      expect(() => requireExecutableAgentProfile(profile), notConfigured());
      expect(agentEngineUsesCodexOAuth(profile.engine), isFalse);
    });

    test('accepts a runtime-pinned local Qwen profile', () {
      final profile = AgentPermissionProfile.parse(
        _runtimeProfile(),
        engines: engines,
      );

      expect(profile.engine, qwen38LocalAgentEngine);
      expect(profile.runtime, isNotNull);
    });

    test('rejects every deviation from the configured reservation', () {
      final mutations = <String, void Function(Map<String, Object?> fleet)>{
        'profile': (fleet) => fleet['profile'] = 'another-gpu-coder',
        'mutable image': (fleet) =>
            fleet['image'] = 'registry.example.invalid/qwen-coder:latest',
        'missing capability': (fleet) =>
            (fleet['capabilities']! as List).remove('example-model-cache'),
        'extra capability': (fleet) =>
            (fleet['capabilities']! as List).add('arbitrary-host-access'),
        'Codex authority': (fleet) =>
            (fleet['capabilities']! as List).add('codex-oauth'),
        'different VRAM': (fleet) =>
            (fleet['resources']! as Map)['vram_mb'] = 24576,
        'missing VRAM': (fleet) =>
            (fleet['resources']! as Map).remove('vram_mb'),
        'different RAM': (fleet) =>
            (fleet['resources']! as Map)['ram_mb'] = 8192,
        'different timeout': (fleet) =>
            (fleet['resources']! as Map)['timeout_s'] = 7200,
      };
      for (final entry in mutations.entries) {
        final json = exampleLocalQwenProfile(_codexProfile());
        entry.value(json['fleet']! as Map<String, Object?>);
        expect(
          () => AgentPermissionProfile.parse(json, engines: engines),
          invalidProfile(),
          reason: entry.key,
        );
      }
    });

    test('never lets the local engine receive the Codex credential', () {
      final json = exampleLocalQwenProfile(_codexProfile());
      final codex = _codexProfile();
      final codexBinding =
          ((codex['secret_injection']! as Map)['bindings']! as List)
              .cast<Map<String, Object?>>()
              .singleWhere(
                (item) => item['github_secret'] == 'CODEX_AUTH_JSON',
              );
      ((json['secret_injection']! as Map)['bindings']! as List).add(
        codexBinding,
      );

      expect(
        () => AgentPermissionProfile.parse(json, engines: engines),
        invalidProfile(),
      );
    });
  });

  test('the documented setting admits the runner README profile', () {
    String jsonBlock(String path, String after) {
      final text = File(path).readAsStringSync();
      final start = text.indexOf('```json\n', text.indexOf(after));
      final end = text.indexOf('\n```', start);
      return text.substring(start + '```json\n'.length, end);
    }

    final setting = jsonBlock(
      '../docs/deployment.md',
      localAgentEnginesSetting,
    );
    final engines = AgentEngineCatalog.fromBase64(
      base64Encode(utf8.encode(setting)),
    );
    final profile = jsonBlock(
      '../examples/implementation/runners/qwen-coder/README.md',
      'Offer the engine in ii-os',
    ).replaceAll('<digest>', 'b' * 64);

    final parsed = AgentPermissionProfile.parse(profile, engines: engines);
    expect(parsed.engine, qwen38LocalAgentEngine);
    expect(
      () => requireExecutableAgentProfile(parsed, engines: engines),
      returnsNormally,
    );
    expect(
      () => AgentPermissionProfile.parse(profile),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'agent_engine_not_configured',
        ),
      ),
    );
  });

  group('the deployment setting', () {
    Matcher namesSetting() => throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains(localAgentEnginesSetting),
      ),
    );
    String encode(Object? value) =>
        base64Encode(utf8.encode(jsonEncode(value)));
    List<Object?> withoutCapability(String name) =>
        [...(exampleLocalQwenPolicy['capabilities']! as List)]..remove(name);
    Map<Object?, Object?> withoutResource(String name) =>
        {...(exampleLocalQwenPolicy['resources']! as Map)}..remove(name);
    Map<String, Object?> policy() =>
        (jsonDecode(jsonEncode(exampleLocalQwenPolicy)) as Map)
            .cast<String, Object?>();

    test('round-trips through its base64 encoding', () {
      final engines = AgentEngineCatalog.fromBase64(
        exampleLocalEnginesBase64(),
      );
      final local = engines.localPolicy(qwen38LocalAgentEngine)!;

      expect(local.profile, 'example-gpu-coder');
      expect(local.resources, {
        'ram_mb': 6144,
        'cpu': 4,
        'disk_gb': 30,
        'vram_mb': 16384,
        'timeout_s': 3600,
      });
    });

    test('fails closed by name on any invalid value', () {
      final faults = <String, Object?>{
        'not base64': null,
        'unknown schema': {...exampleLocalEnginesJson(), 'schema_version': 2},
        'unknown field': {...exampleLocalEnginesJson(), 'extra': true},
        'no engines': {'schema_version': 1, 'engines': <String, Object?>{}},
        'unknown engine': {
          'schema_version': 1,
          'engines': {'remote-unbounded-agent': policy()},
        },
        'Codex is not a local engine': {
          'schema_version': 1,
          'engines': {codexAgentEngine: policy()},
        },
        'unknown policy field': exampleLocalEnginesJson(
          policy: policy()..['image'] = 'registry.example.invalid/x',
        ),
        'unsafe profile name': exampleLocalEnginesJson(
          policy: policy()..['profile'] = 'gpu coder',
        ),
        'Codex authority': exampleLocalEnginesJson(
          policy: policy()
            ..['capabilities'] = [
              ...(exampleLocalQwenPolicy['capabilities']! as List),
              'codex-oauth',
            ],
        ),
        'duplicate capability': exampleLocalEnginesJson(
          policy: policy()
            ..['capabilities'] = [
              ...(exampleLocalQwenPolicy['capabilities']! as List),
              'nvidia-gpu',
            ],
        ),
        'missing Docker runtime': exampleLocalEnginesJson(
          policy: policy()
            ..['capabilities'] = withoutCapability('runtime-docker'),
        ),
        'missing GitHub token capability': exampleLocalEnginesJson(
          policy: policy()
            ..['capabilities'] = withoutCapability('github-app-token'),
        ),
        'missing usage reporting capability': exampleLocalEnginesJson(
          policy: policy()
            ..['capabilities'] = withoutCapability('agent-usage-reporting'),
        ),
        'missing VRAM': exampleLocalEnginesJson(
          policy: policy()..['resources'] = withoutResource('vram_mb'),
        ),
        'unbounded VRAM': exampleLocalEnginesJson(
          policy: policy()
            ..['resources'] = {
              ...(exampleLocalQwenPolicy['resources']! as Map),
              'vram_mb': 262144,
            },
        ),
        'fractional CPU': exampleLocalEnginesJson(
          policy: policy()
            ..['resources'] = {
              ...(exampleLocalQwenPolicy['resources']! as Map),
              'cpu': 4.5,
            },
        ),
      };
      for (final entry in faults.entries) {
        final encoded = entry.value == null
            ? 'not base64 at all'
            : encode(entry.value);
        expect(
          () => AgentEngineCatalog.fromBase64(encoded),
          namesSetting(),
          reason: entry.key,
        );
      }
    });
  });
}

Map<String, Object?> _runtimeProfile() => {
  'schema_version': 4,
  'engine': qwen38LocalAgentEngine,
  'id': 'qwen38-repository-maintainer',
  'version': '2026-07-17.1',
  'display_name': 'Repository maintainer',
  'description': 'Edit code and run tests without changing ticket records.',
  'allowed_actions': ['Read and edit repository files', 'Run tests'],
  'denied_actions': ['Create or edit GitHub issues'],
  'repository_actions': {'mode': 'maintain_dev'},
  'runtime': {
    'configuration': {
      'path': '.ii-os/runtimes/local-maintainer.json',
      'sha256': 'a' * 64,
    },
    'execution_binding': {
      'path': '.ii-os/runtimes/owned-compute.json',
      'sha256': 'b' * 64,
    },
  },
  'workflow': {'file': 'ii-os-agent-task.yml', 'ref': 'dev'},
};

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
