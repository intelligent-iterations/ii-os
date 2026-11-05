import 'dart:convert';

import 'package:ii_os_functions/src/agent_permission_profile.dart';

/// A synthetic deployment policy for the local Qwen engine.
///
/// Every value here is invented: a deployment supplies its own execution
/// profile, runner capability labels, and resource reservation through
/// [localAgentEnginesSetting].
const Map<String, Object?> exampleLocalQwenPolicy = {
  'profile': 'example-gpu-coder',
  'capabilities': [
    'runtime-docker',
    'auto-agent',
    'github-app-token',
    'agent-usage-reporting',
    'nvidia-gpu',
    'example-model-cache',
    'example-sandbox',
  ],
  'resources': {
    'ram_mb': 6144,
    'cpu': 4,
    'disk_gb': 30,
    'vram_mb': 16384,
    'timeout_s': 3600,
  },
};

Map<String, Object?> exampleLocalEnginesJson({
  Map<String, Object?> policy = exampleLocalQwenPolicy,
}) => {
  'schema_version': 1,
  'engines': {qwen38LocalAgentEngine: policy},
};

String exampleLocalEnginesBase64({
  Map<String, Object?> policy = exampleLocalQwenPolicy,
}) => base64Encode(
  utf8.encode(jsonEncode(exampleLocalEnginesJson(policy: policy))),
);

AgentEngineCatalog exampleLocalEngines() =>
    AgentEngineCatalog.fromBase64(exampleLocalEnginesBase64());

/// Turns a schema v1 Codex profile into a schema v3 local Qwen profile that
/// matches [exampleLocalQwenPolicy] exactly.
Map<String, Object?> exampleLocalQwenProfile(Map<String, Object?> codex) {
  final json = (jsonDecode(jsonEncode(codex)) as Map).cast<String, Object?>()
    ..['schema_version'] = 3
    ..['engine'] = qwen38LocalAgentEngine
    ..['id'] = 'qwen38-repository-maintainer'
    ..['repository_actions'] = {'mode': 'maintain_dev'};
  final fleet = json['fleet']! as Map<String, Object?>;
  fleet['profile'] = exampleLocalQwenPolicy['profile'];
  fleet['image'] =
      'registry.example.invalid/qwen-coder@sha256:${List.filled(64, 'a').join()}';
  fleet['resources'] = jsonDecode(
    jsonEncode(exampleLocalQwenPolicy['resources']),
  );
  fleet['capabilities'] = [
    ...(exampleLocalQwenPolicy['capabilities']! as List<Object?>),
  ];
  final injection = json['secret_injection']! as Map<String, Object?>;
  final bindings = injection['bindings']! as List<Object?>;
  bindings.removeWhere(
    (binding) =>
        (binding! as Map<String, Object?>)['github_secret'] ==
        'CODEX_AUTH_JSON',
  );
  return json;
}
