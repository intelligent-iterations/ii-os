import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_permission.dart';

void main() {
  test(
    'default maintainer approves runtime references without duplicating runtime policy',
    () {
      final profile = AgentPermissionModel.fromJson(
        defaultAgentPermissionJson(),
      );

      expect(profile.version, defaultAgentPermissionVersion);
      expect(profile.mayMergeDev, isTrue);
      expect(profile.json['schema_version'], 4);
      expect(profile.engine, 'codex');
      expect(profile.runtime.keys.toSet(), {
        'configuration',
        'execution_binding',
      });
      expect(profile.runtimeKind, 'Agent runtime');
      expect(profile.installableJson, isNot(contains('fleet')));
      expect(profile.installableJson, isNot(contains('secret_injection')));
    },
  );

  test('default shapes carry mutually exclusive repository authority', () {
    final profiles = {
      for (final json in defaultAgentPermissionJsons())
        AgentPermissionModel.fromJson(json).id: AgentPermissionModel.fromJson(
          json,
        ),
    };

    expect(profiles.keys, {
      repositoryMaintainerPermissionId,
      pullRequestAuthorPermissionId,
      pullRequestReviewerPermissionId,
    });
    expect(profiles[repositoryMaintainerPermissionId]?.mayMergeDev, isTrue);
    expect(profiles[pullRequestAuthorPermissionId]?.mayPublishChanges, isTrue);
    expect(profiles[pullRequestAuthorPermissionId]?.mayMergeDev, isFalse);
    expect(
      profiles[pullRequestReviewerPermissionId]?.mayApprovePullRequests,
      isTrue,
    );
    expect(
      profiles[pullRequestReviewerPermissionId]?.mayPublishChanges,
      isFalse,
    );
  });

  test('installable profile excludes GitHub listing metadata', () {
    final profile = AgentPermissionModel.fromJson({
      ...defaultAgentPermissionJson(),
      'path': '.ii-os/agent-permissions/repository-maintainer.json',
      'ref': 'dev',
      'repository': 'acme-co/example-app',
      'sha': 'dddddddddddddddddddddddddddddddddddddddd',
    });

    expect(profile.installableJson, defaultAgentPermissionJson());
    expect(profile.installableJson, isNot(contains('path')));
    expect(profile.installableJson, isNot(contains('ref')));
    expect(profile.installableJson, isNot(contains('repository')));
    expect(profile.installableJson, isNot(contains('sha')));
  });

  test('local Qwen profile is an explicit selectable engine', () {
    final profile = AgentPermissionModel.fromJson({
      ...defaultAgentPermissionJson(),
      'schema_version': 3,
      'id': 'qwen38-repository-maintainer',
      'engine': 'qwen38-local',
      'display_name': 'Repository maintainer',
    });

    expect(profile.engine, 'qwen38-local');
    expect(profile.engineDisplayName, 'Qwen3.8 local');
    expect(profile.selectionLabel, 'Repository maintainer · Qwen3.8 local');
    expect(profile.installableJson['engine'], 'qwen38-local');
    expect(
      AgentPermissionModel.fromJson(defaultAgentPermissionJson()).engine,
      'codex',
    );
  });

  test('runtime profile editing preserves the approved file references', () {
    final json = {
      ...defaultAgentPermissionJson(),
      'schema_version': 4,
      'engine': 'codex',
      'runtime': {
        'configuration': {
          'path': '.ii-os/runtimes/agent.json',
          'sha256': 'a' * 64,
        },
        'execution_binding': {
          'path': '.ii-os/runtimes/binding.json',
          'sha256': 'b' * 64,
        },
      },
    }..removeWhere((key, _) => {'fleet', 'secret_injection'}.contains(key));
    final profile = AgentPermissionModel.fromJson(json);
    expect(profile.installableJson, json);
  });
}
