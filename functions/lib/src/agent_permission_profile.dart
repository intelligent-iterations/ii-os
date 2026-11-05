import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'api_error.dart';

part 'agent_permission_profile_digest.dart';
part 'agent_permission_profile_engines.dart';
part 'agent_permission_profile_runtime.dart';
part 'agent_permission_profile_schema.dart';

const String iiOsAgentTaskWorkflow = 'ii-os-agent-task.yml';
const String iiOsAgentWorkTicketWorkflow = 'ii-os-agent-work-ticket.yml';
const String iiOsAgentPermissionInstallerWorkflow =
    'ii-os-agent-permissions.yml';

/// Reviewed installer body. The dispatch surface above is a thin caller that
/// reaches it at an exact coordinator commit; protected coordinator jobs then
/// use the current control-plane credential.
const String iiOsAgentPermissionInstallerImplWorkflow =
    'ii-os-agent-permissions-impl.yml';

const String iiOsCodexAuthWorkflow = 'ii-os-codex-auth.yml';
const String iiOsCodexAuthFinalizeWorkflow = 'ii-os-codex-auth-finalize.yml';
const String iiOsAgentEnvironment = 'ii-os-agent-maintainer';
const String iiOsAgentBootstrapEnvironment = 'ii-os-agent-bootstrap';
const String codexAgentEngine = 'codex';
const String qwen38LocalAgentEngine = 'qwen38-local';
const Set<String> codexAgentCapabilities = {
  'runtime-docker',
  'auto-agent',
  'codex-oauth',
  'codex-sandbox',
  'github-app-token',
  'agent-usage-reporting',
  'linux-amd64',
};

/// Whether [engine] signs in with Codex OAuth, so its readiness includes the
/// Codex credential checks.
bool agentEngineUsesCodexOAuth(String engine) =>
    !localModelAgentEngines.contains(engine);

final class AgentPermissionProfile {
  const AgentPermissionProfile({
    required this.schemaVersion,
    required this.engine,
    required this.id,
    required this.version,
    required this.displayName,
    required this.description,
    required this.allowedActions,
    required this.deniedActions,
    required this.repository,
    AgentFleetPolicy? fleet,
    AgentSecretInjection? secretInjection,
    this.runtime,
    required this.workflow,
  }) : _legacyFleet = fleet,
       _legacySecrets = secretInjection;

  /// Parses and validates a profile against the engines this deployment
  /// offers. [engines] defaults to Codex only, which refuses every local
  /// model engine by name.
  factory AgentPermissionProfile.parse(
    Object? value, {
    AgentEngineCatalog engines = AgentEngineCatalog.codexOnly,
  }) {
    try {
      final json = value is String ? jsonDecode(value) : value;
      final root = _map(json, 'profile');
      final schemaVersion = root['schema_version'];
      if (schemaVersion is! int ||
          !const {1, 2, 3, 4}.contains(schemaVersion)) {
        throw const FormatException('schema_version must be 1, 2, 3, or 4');
      }
      _expectKeys(root, {
        'schema_version',
        if (schemaVersion >= 3) 'engine',
        'id',
        'version',
        'display_name',
        'description',
        'allowed_actions',
        'denied_actions',
        if (schemaVersion >= 2) 'repository_actions',
        if (schemaVersion < 4) 'fleet',
        if (schemaVersion < 4) 'secret_injection',
        if (schemaVersion == 4) 'runtime',
        'workflow',
      }, 'profile');
      return AgentPermissionProfile(
        schemaVersion: schemaVersion,
        engine: schemaVersion >= 3
            ? _agentEngine(root['engine'], engines)
            : codexAgentEngine,
        id: _safeName(root['id'], 'id'),
        version: _safeName(root['version'], 'version'),
        displayName: _text(root['display_name'], 'display_name', 100),
        description: _text(root['description'], 'description', 1000),
        allowedActions: _strings(
          root['allowed_actions'],
          'allowed_actions',
          required: true,
        ),
        deniedActions: _strings(
          root['denied_actions'],
          'denied_actions',
          required: true,
          allowEmpty: true,
        ),
        repository: schemaVersion >= 2
            ? AgentRepositoryPolicy.parse(root['repository_actions'])
            : const AgentRepositoryPolicy.pullRequest(),
        fleet: schemaVersion < 4 ? AgentFleetPolicy.parse(root['fleet']) : null,
        secretInjection: schemaVersion < 4
            ? AgentSecretInjection.parse(root['secret_injection'])
            : null,
        runtime: schemaVersion == 4
            ? AgentRuntimePolicy.parse(root['runtime'])
            : null,
        workflow: AgentWorkflowPolicy.parse(root['workflow']),
      )._validated(engines);
    } on ApiError {
      rethrow;
    } on Object {
      throw const ApiError(
        400,
        'agent_permission_invalid',
        'The agent permission JSON is invalid.',
      );
    }
  }

  final int schemaVersion;
  final String engine;
  final String id;
  final String version;
  final String displayName;
  final String description;
  final List<String> allowedActions;
  final List<String> deniedActions;
  final AgentRepositoryPolicy repository;
  final AgentFleetPolicy? _legacyFleet;
  final AgentSecretInjection? _legacySecrets;
  final AgentRuntimePolicy? runtime;
  AgentFleetPolicy get fleet =>
      _legacyFleet ??
      (throw StateError('Runtime profiles have no Fleet policy'));
  AgentSecretInjection get secretInjection =>
      _legacySecrets ??
      (throw StateError('Runtime profiles have no worker secret injection'));

  final AgentWorkflowPolicy workflow;

  AgentPermissionProfile _validated(AgentEngineCatalog engines) {
    if (schemaVersion == 4) {
      requireRuntimeAgentProfile(this);
      return this;
    }
    final capabilities = fleet.capabilities.toSet();
    final requiredCapabilities = agentCapabilitiesForEngine(engine, engines);
    final allowedCapabilities = {...requiredCapabilities, 'slack-notify'};
    if (fleet.runtimeKind != 'docker' ||
        !capabilities.containsAll(requiredCapabilities) ||
        capabilities.any((item) => !allowedCapabilities.contains(item))) {
      throw const ApiError(
        400,
        'agent_permission_invalid',
        'The Fleet execution policy must use Docker and only the supported agent capabilities.',
      );
    }
    final local = engines.localPolicy(engine);
    if (local != null && !local.admits(fleet)) {
      throw const ApiError(
        400,
        'agent_permission_invalid',
        'The local Qwen engine must use its reviewed execution profile, immutable image, and VRAM reservation.',
      );
    }
    if (engine == codexAgentEngine && fleet.resources.containsKey('vram_mb')) {
      throw const ApiError(
        400,
        'agent_permission_invalid',
        'The Codex engine cannot reserve accelerator memory.',
      );
    }
    final bySecret = <String, AgentSecretBinding>{};
    for (final binding in secretInjection.bindings) {
      if (!fleet.capabilities.contains(binding.capability)) {
        throw ApiError(
          400,
          'agent_permission_invalid',
          'Secret binding ${binding.id} requires its capability in Fleet.',
        );
      }
      if (bySecret.containsKey(binding.githubSecret)) {
        throw const ApiError(
          400,
          'agent_permission_invalid',
          'Each GitHub secret may be bound only once.',
        );
      }
      bySecret[binding.githubSecret] = binding;
    }
    if (secretInjection.environment != iiOsAgentEnvironment) {
      throw const ApiError(
        400,
        'agent_permission_invalid',
        'Secret injection must use the ii-os agent environment.',
      );
    }
    final requiredBindings = {
      'IIAUTO_GITHUB_TOKEN': ('github-app-token', 'GITHUB_TOKEN_FILE'),
      'II_OS_AGENT_USAGE_API_KEY': (
        'agent-usage-reporting',
        'AGENT_USAGE_KEY_FILE',
      ),
      if (engine == codexAgentEngine)
        'CODEX_AUTH_JSON': ('codex-oauth', 'CODEX_AUTH_JSON_FILE'),
    };
    final allowedBindings = {
      ...requiredBindings,
      'IIAUTO_SLACK_BOT_TOKEN': ('slack-notify', 'IIAUTO_SLACK_BOT_TOKEN_FILE'),
    };
    final bindingsValid =
        requiredBindings.entries.every((entry) {
          final binding = bySecret[entry.key];
          return binding != null &&
              binding.capability == entry.value.$1 &&
              binding.target == 'file' &&
              binding.targetName == entry.value.$2;
        }) &&
        secretInjection.bindings.every((binding) {
          final expected = allowedBindings[binding.githubSecret];
          return expected != null &&
              binding.capability == expected.$1 &&
              binding.target == 'file' &&
              binding.targetName == expected.$2;
        });
    if (!bindingsValid ||
        workflow.file != iiOsAgentTaskWorkflow ||
        workflow.ref != 'dev') {
      throw const ApiError(
        400,
        'agent_permission_invalid',
        'The workflow and capability-bound secret bindings do not match the executable agent contract.',
      );
    }
    return this;
  }

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    if (schemaVersion >= 3) 'engine': engine,
    'id': id,
    'version': version,
    'display_name': displayName,
    'description': description,
    'allowed_actions': allowedActions,
    'denied_actions': deniedActions,
    if (schemaVersion >= 2) 'repository_actions': repository.toJson(),
    if (schemaVersion < 4) 'fleet': fleet.toJson(),
    if (schemaVersion < 4) 'secret_injection': secretInjection.toJson(),
    if (schemaVersion == 4) 'runtime': runtime!.toJson(),
    'workflow': workflow.toJson(),
  };
}

/// Broker-enforced repository authority for one agent run.
///
/// Human-readable allow/deny lists explain a profile. This closed field is
/// what the post-cleanup broker uses to decide whether an exported mutation is
/// legal. The agent never receives a broader GitHub token because of it.
final class AgentRepositoryPolicy {
  const AgentRepositoryPolicy(this.mode);

  const AgentRepositoryPolicy.pullRequest() : mode = 'pull_request';

  factory AgentRepositoryPolicy.parse(Object? value) {
    final json = _map(value, 'repository_actions');
    _expectKeys(json, const {'mode'}, 'repository_actions');
    final mode = _safeName(json['mode'], 'repository_actions.mode');
    if (!const {
      'maintain_dev',
      'pull_request',
      'review_pull_requests',
    }.contains(mode)) {
      throw const FormatException('repository_actions.mode is not supported');
    }
    return AgentRepositoryPolicy(mode);
  }

  final String mode;

  bool get mayPublishChanges =>
      mode == 'maintain_dev' || mode == 'pull_request';
  bool get mayMergeDev => mode == 'maintain_dev';
  bool get mayApprovePullRequests => mode == 'review_pull_requests';

  Map<String, Object?> toJson() => {'mode': mode};
}

void requireExecutableAgentProfile(
  AgentPermissionProfile profile, {
  AgentEngineCatalog engines = AgentEngineCatalog.codexOnly,
}) {
  if (profile.schemaVersion == 4) {
    requireRuntimeAgentProfile(profile);
    return;
  }
  final capabilities = profile.fleet.capabilities.toSet();
  final bindings = {
    for (final binding in profile.secretInjection.bindings)
      binding.githubSecret: binding,
  };
  final requiredBindings = {
    'IIAUTO_GITHUB_TOKEN': ('github-app-token', 'GITHUB_TOKEN_FILE'),
    'II_OS_AGENT_USAGE_API_KEY': (
      'agent-usage-reporting',
      'AGENT_USAGE_KEY_FILE',
    ),
    if (profile.engine == codexAgentEngine)
      'CODEX_AUTH_JSON': ('codex-oauth', 'CODEX_AUTH_JSON_FILE'),
  };
  final allowedBindings = {
    ...requiredBindings,
    'IIAUTO_SLACK_BOT_TOKEN': ('slack-notify', 'IIAUTO_SLACK_BOT_TOKEN_FILE'),
  };
  final bindingsValid =
      requiredBindings.entries.every((entry) {
        final binding = bindings[entry.key];
        return binding != null &&
            binding.capability == entry.value.$1 &&
            binding.target == 'file' &&
            binding.targetName == entry.value.$2;
      }) &&
      bindings.length == profile.secretInjection.bindings.length &&
      profile.secretInjection.bindings.every((binding) {
        final expected = allowedBindings[binding.githubSecret];
        return expected != null &&
            binding.capability == expected.$1 &&
            binding.target == 'file' &&
            binding.targetName == expected.$2;
      });
  if (profile.workflow.file != iiOsAgentTaskWorkflow ||
      profile.workflow.ref != 'dev' ||
      profile.secretInjection.environment != iiOsAgentEnvironment ||
      !capabilities.containsAll(
        agentCapabilitiesForEngine(profile.engine, engines),
      ) ||
      capabilities.any(
        (item) => !{
          ...agentCapabilitiesForEngine(profile.engine, engines),
          'slack-notify',
        }.contains(item),
      ) ||
      !capabilities.contains('runtime-docker') ||
      !bindingsValid) {
    throw const ApiError(
      422,
      'agent_permission_execution_policy_invalid',
      'The selected profile must use the dev agent workflow, protected environment, Docker runtime, and all required capability-bound credentials.',
    );
  }
}

/// The exact runner capabilities a profile for [engine] must declare in the
/// deployment described by [engines].
Set<String> agentCapabilitiesForEngine(
  String engine, [
  AgentEngineCatalog engines = AgentEngineCatalog.codexOnly,
]) => engines.capabilitiesFor(engine);

String _agentEngine(Object? value, AgentEngineCatalog engines) {
  final engine = _safeName(value, 'engine');
  agentCapabilitiesForEngine(engine, engines);
  return engine;
}
