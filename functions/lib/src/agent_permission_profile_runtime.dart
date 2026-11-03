part of 'agent_permission_profile.dart';

/// ii-os approves references to runtime-owned configuration, never another copy
/// of its CPU, RAM, image, command, model or credential policy.
final class AgentRuntimePolicy {
  const AgentRuntimePolicy({
    required this.configurationPath,
    required this.configurationDigest,
    required this.bindingPath,
    required this.bindingDigest,
  });

  factory AgentRuntimePolicy.parse(Object? value) {
    final json = _map(value, 'runtime');
    _expectKeys(json, const {'configuration', 'execution_binding'}, 'runtime');
    final configuration = _map(json['configuration'], 'configuration');
    final binding = _map(json['execution_binding'], 'execution_binding');
    for (final reference in [configuration, binding]) {
      _expectKeys(reference, const {'path', 'sha256'}, 'runtime reference');
      final path = reference['path'];
      if (path is! String ||
          !RegExp(
            r'^\.ii-os/runtimes/[A-Za-z0-9][A-Za-z0-9._/-]{0,180}\.json$',
          ).hasMatch(path) ||
          path.contains('..') ||
          path.contains('//') ||
          reference['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(reference['sha256']! as String)) {
        throw const FormatException('runtime reference is invalid');
      }
    }
    if (configuration['path'] == binding['path']) {
      throw const FormatException('runtime references must be distinct');
    }
    return AgentRuntimePolicy(
      configurationPath: configuration['path']! as String,
      configurationDigest: configuration['sha256']! as String,
      bindingPath: binding['path']! as String,
      bindingDigest: binding['sha256']! as String,
    );
  }

  final String configurationPath;
  final String configurationDigest;
  final String bindingPath;
  final String bindingDigest;

  Map<String, Object?> toJson() => {
    'configuration': {'path': configurationPath, 'sha256': configurationDigest},
    'execution_binding': {'path': bindingPath, 'sha256': bindingDigest},
  };
}

void requireRuntimeAgentProfile(AgentPermissionProfile profile) {
  if (profile.schemaVersion != 4 ||
      profile.runtime == null ||
      profile._legacyFleet != null ||
      profile._legacySecrets != null ||
      profile.workflow.file != iiOsAgentTaskWorkflow ||
      profile.workflow.ref != 'dev') {
    throw const ApiError(
      422,
      'agent_permission_execution_policy_invalid',
      'The selected profile must pin runtime configuration and its execution binding and use the reviewed dev agent workflow.',
    );
  }
}
