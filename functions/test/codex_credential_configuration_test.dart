import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ii_os_functions/src/agent_permission_profile.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/codex_credential_policy.dart';
import 'package:test/test.dart';

void main() {
  test('transport preserves approved JSON file trailing newline', () {
    const configuration =
        '{"credentialBindings":[{"provider":"github-actions","resource":"example/project","key":"CODEX_AUTH_JSON","assignment":"harness.codex.oauth"}]}\n';
    final received = codexCredentialConfiguration({
      'runtimeConfiguration': configuration,
    });
    expect(received, configuration);
    expect(
      () => requireCodexCredentialConfiguration(
        profile: _profile(configuration),
        configuration: received,
        repository: 'example/project',
      ),
      returnsNormally,
    );
  });
  test('only the exact approved configuration grants this OAuth binding', () {
    final configuration = jsonEncode({
      'credentialBindings': [
        {
          'provider': 'github-actions',
          'resource': 'example/project',
          'key': 'CODEX_AUTH_JSON',
          'assignment': 'harness.codex.oauth',
        },
      ],
    });
    final profile = _profile(configuration);
    expect(
      () => requireCodexCredentialConfiguration(
        profile: profile,
        configuration: configuration,
        repository: 'example/project',
      ),
      returnsNormally,
    );
    expect(
      () => requireCodexCredentialConfiguration(
        profile: profile,
        configuration: '$configuration ',
        repository: 'example/project',
      ),
      throwsA(isA<ApiError>()),
    );
    for (final entry in {
      'CODEX_AUTH_JSON': 'ANOTHER_SECRET',
      'example/project': 'sibling/project',
      'github-actions': 'another-provider',
    }.entries) {
      final wrong = configuration.replaceAll(entry.key, entry.value);
      expect(
        () => requireCodexCredentialConfiguration(
          profile: _profile(wrong),
          configuration: wrong,
          repository: 'example/project',
        ),
        throwsA(isA<ApiError>()),
      );
    }
    final noBinding = jsonEncode({'credentialBindings': <Object?>[]});
    expect(
      () => requireCodexCredentialConfiguration(
        profile: _profile(noBinding),
        configuration: noBinding,
        repository: 'example/project',
      ),
      throwsA(isA<ApiError>()),
    );
  });
}

AgentPermissionProfile _profile(String configuration) => AgentPermissionProfile(
  schemaVersion: 4,
  engine: 'codex',
  id: 'maintainer',
  version: 'v1',
  displayName: 'Maintainer',
  description: 'Approved',
  allowedActions: const [],
  deniedActions: const [],
  repository: const AgentRepositoryPolicy.pullRequest(),
  runtime: AgentRuntimePolicy(
    configurationPath: '.ii-os/runtimes/maintainer.json',
    configurationDigest: sha256.convert(utf8.encode(configuration)).toString(),
    bindingPath: '.ii-os/runtimes/binding.json',
    bindingDigest: 'a' * 64,
  ),
  workflow: const AgentWorkflowPolicy(file: iiOsAgentTaskWorkflow, ref: 'dev'),
);
