import 'dart:convert';

import 'models.dart';

const defaultAgentPermissionVersion = '2026-10-29.1';
const repositoryMaintainerPermissionId = 'repository-maintainer';
const pullRequestAuthorPermissionId = 'pull-request-author';
const pullRequestReviewerPermissionId = 'pull-request-reviewer';
const defaultAgentRuntimeReferences = String.fromEnvironment(
  'II_OS_DEFAULT_AGENT_RUNTIME_REFERENCES',
  defaultValue: '{}',
);

final class AgentPermissionModel {
  const AgentPermissionModel(this.json);

  factory AgentPermissionModel.fromJson(JsonMap json) =>
      AgentPermissionModel(json);

  final JsonMap json;

  /// The executable profile document, without GitHub listing metadata.
  ///
  /// Profile listings also carry fields such as `path`, `ref`, `repository`,
  /// and `sha`. Those describe where GitHub found the document; they are not
  /// part of the strict permission schema accepted by the installer.
  JsonMap get installableJson => {
    for (final key in _profileKeys)
      if (json.containsKey(key)) key: json[key],
  };

  String get id => json['id'] as String? ?? '';
  String get version => json['version'] as String? ?? '';
  String get engine => const {3, 4}.contains(json['schema_version'])
      ? json['engine'] as String? ?? ''
      : 'codex';
  String get engineDisplayName => switch (engine) {
    'codex' => 'Codex',
    'qwen38-local' => 'Qwen3.8 local',
    _ => engine,
  };
  String get displayName => json['display_name'] as String? ?? id;
  String get selectionLabel => '$displayName · $engineDisplayName';
  String get description => json['description'] as String? ?? '';
  List<String> get allowedActions => _strings(json['allowed_actions']);
  List<String> get deniedActions => _strings(json['denied_actions']);

  JsonMap get repositoryActions => asJsonMap(json['repository_actions']);
  String get repositoryMode =>
      repositoryActions['mode'] as String? ?? 'pull_request';
  bool get mayPublishChanges =>
      const {'maintain_dev', 'pull_request'}.contains(repositoryMode);
  bool get mayMergeDev => repositoryMode == 'maintain_dev';
  bool get mayApprovePullRequests => repositoryMode == 'review_pull_requests';

  JsonMap get fleet => asJsonMap(json['fleet']);
  List<String> get capabilities => _strings(fleet['capabilities']);
  String get runtimeKind => runtime.isNotEmpty
      ? 'Agent runtime'
      : fleet['runtime_kind'] as String? ?? '';
  String get image => fleet['image'] as String? ?? '';

  JsonMap get secretInjection => asJsonMap(json['secret_injection']);
  JsonMap get runtime => asJsonMap(json['runtime']);
  String get runtimeConfigurationReference =>
      _runtimeReference(runtime['configuration']);
  String get runtimeBindingReference =>
      _runtimeReference(runtime['execution_binding']);
  String get environment => secretInjection['environment'] as String? ?? '';
  List<JsonMap> get secretBindings =>
      (secretInjection['bindings'] as List<Object?>? ?? const [])
          .map(asJsonMap)
          .toList();

  JsonMap get workflow => asJsonMap(json['workflow']);
  String get workflowRef => workflow['ref'] as String? ?? 'dev';

  String get prettyJson => const JsonEncoder.withIndent('  ').convert(json);
}

const _profileKeys = <String>{
  'schema_version',
  'engine',
  'id',
  'version',
  'display_name',
  'description',
  'allowed_actions',
  'denied_actions',
  'repository_actions',
  'fleet',
  'secret_injection',
  'runtime',
  'workflow',
};

JsonMap defaultAgentPermissionJson([
  String id = repositoryMaintainerPermissionId,
]) {
  final shape = _defaultPermissionShapes[id];
  if (shape == null) {
    throw ArgumentError.value(id, 'id', 'Unknown default permission shape');
  }
  return {
    'schema_version': 4,
    'engine': 'codex',
    ...shape,
    'version': defaultAgentPermissionVersion,
    'runtime': _runtimeReferences(id),
    'workflow': {'file': 'ii-os-agent-task.yml', 'ref': 'dev'},
  };
}

List<JsonMap> defaultAgentPermissionJsons() => _defaultPermissionShapes.keys
    .map(defaultAgentPermissionJson)
    .toList(growable: false);

final Map<String, JsonMap> _defaultPermissionShapes = {
  repositoryMaintainerPermissionId: {
    'id': repositoryMaintainerPermissionId,
    'display_name': 'Repository maintainer',
    'description':
        'Implements and verifies repository changes, opens a pull request, and may merge the exact reviewed change to dev.',
    'allowed_actions': [
      'Read and edit files in the selected repository',
      'Run repository tests and validation commands',
      'Create implementation commits and a reviewable pull request',
      'Merge the exact approved pull request to dev',
      'Comment implementation evidence on the existing source ticket',
    ],
    'denied_actions': [
      'Create new GitHub issues or Project items',
      'Set Done or another human-only Project status',
      'Push to public mirrors',
      'Use credentials not declared by this profile',
    ],
    'repository_actions': {'mode': 'maintain_dev'},
  },
  pullRequestAuthorPermissionId: {
    'id': pullRequestAuthorPermissionId,
    'display_name': 'Pull request author',
    'description':
        'Implements and verifies repository changes, then opens a pull request for someone else to approve and merge.',
    'allowed_actions': [
      'Read and edit files in the selected repository',
      'Run repository tests and validation commands',
      'Create implementation commits and a reviewable pull request',
      'Comment implementation evidence on the existing source ticket',
    ],
    'denied_actions': [
      'Approve or merge pull requests',
      'Create new GitHub issues or Project items',
      'Set Done or another human-only Project status',
      'Push to public mirrors',
    ],
    'repository_actions': {'mode': 'pull_request'},
  },
  pullRequestReviewerPermissionId: {
    'id': pullRequestReviewerPermissionId,
    'display_name': 'Pull request reviewer',
    'description':
        'Reviews an existing pull request and may approve it without publishing code or merging it.',
    'allowed_actions': [
      'Read repository code, pull request changes, and verification results',
      'Approve the exact reviewed pull request',
      'Comment review evidence on the existing source ticket',
    ],
    'denied_actions': [
      'Edit or publish repository files',
      'Create or merge pull requests',
      'Create new GitHub issues or Project items',
      'Set Done or another human-only Project status',
    ],
    'repository_actions': {'mode': 'review_pull_requests'},
  },
};

JsonMap _runtimeReferences(String id) {
  final configured = asJsonMap(jsonDecode(defaultAgentRuntimeReferences));
  final references = asJsonMap(configured[id]);
  if (references.isNotEmpty) return references;
  // A deployment supplies reviewed file references. An unconfigured template
  // cannot authorize execution: the installer requires both exact file hashes.
  return {
    'configuration': {'path': '.ii-os/runtimes/$id.json', 'sha256': '0' * 64},
    'execution_binding': {
      'path': '.ii-os/runtimes/execution-binding.json',
      'sha256': '0' * 64,
    },
  };
}

List<String> _strings(Object? value) => value is List<Object?>
    ? value.whereType<String>().toList()
    : const <String>[];

String _runtimeReference(Object? value) {
  final reference = asJsonMap(value);
  final path = reference['path'] as String? ?? '';
  final digest = reference['sha256'] as String? ?? '';
  return path.isEmpty || digest.isEmpty ? '' : '$path\nsha256:$digest';
}
