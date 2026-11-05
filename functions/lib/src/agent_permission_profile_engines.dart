part of 'agent_permission_profile.dart';

/// The deployment setting that enables local model engines.
const String localAgentEnginesSetting = 'II_OS_LOCAL_AGENT_ENGINES_BASE64';

/// Engines that run their own model instead of signing in with Codex OAuth.
///
/// The source knows how to validate these engines but ships none of a
/// deployment's values for them: see [AgentEngineCatalog].
const Set<String> localModelAgentEngines = {qwen38LocalAgentEngine};

/// Capabilities the ii-os profile contract itself requires of a local engine:
/// the Docker runtime and the two credentials every agent run receives.
const Set<String> _localEngineContractCapabilities = {
  'runtime-docker',
  'github-app-token',
  'agent-usage-reporting',
};

const Set<String> _localEngineResources = {
  'ram_mb',
  'cpu',
  'disk_gb',
  'vram_mb',
  'timeout_s',
};

/// One deployment's exact execution policy for a local model engine.
///
/// A profile for the engine is accepted only when its execution profile,
/// runner capabilities, and resource reservation, including accelerator
/// memory, equal these values exactly and its image is pinned by digest.
final class LocalAgentEnginePolicy {
  LocalAgentEnginePolicy._({
    required this.profile,
    required Set<String> capabilities,
    required Map<String, int> resources,
  }) : capabilities = Set.unmodifiable(capabilities),
       resources = Map.unmodifiable(resources);

  final String profile;
  final Set<String> capabilities;
  final Map<String, int> resources;

  bool admits(AgentFleetPolicy fleet) =>
      fleet.profile == profile &&
      _immutableContainerImage.hasMatch(fleet.image) &&
      fleet.resources.length == resources.length &&
      resources.entries.every(
        (entry) => fleet.resources[entry.key] == entry.value,
      );
}

/// The agent engines one deployment offers.
///
/// Codex is always offered. A local model engine is offered only when the
/// composition root supplies its policy through [localAgentEnginesSetting];
/// until then every profile naming it is refused by name, so a deployment
/// never advertises an engine it cannot place.
final class AgentEngineCatalog {
  const AgentEngineCatalog._(this._local);

  static const AgentEngineCatalog codexOnly = AgentEngineCatalog._({});

  /// Parses the deployment setting. An empty value offers Codex only; any
  /// other invalid value fails closed with an error naming the setting.
  factory AgentEngineCatalog.fromBase64(String encoded) {
    final value = encoded.trim();
    if (value.isEmpty) return codexOnly;
    try {
      return AgentEngineCatalog._fromJson(
        jsonDecode(utf8.decode(base64Decode(value))),
      );
    } on FormatException catch (error) {
      throw FormatException(
        '$localAgentEnginesSetting is invalid: ${error.message}',
      );
    }
  }

  factory AgentEngineCatalog._fromJson(Object? decoded) {
    final root = _map(decoded, 'configuration');
    _expectKeys(root, const {'schema_version', 'engines'}, 'configuration');
    if (root['schema_version'] != 1) {
      throw const FormatException('schema_version must be 1');
    }
    final engines = _map(root['engines'], 'engines');
    if (engines.isEmpty) {
      throw const FormatException('engines must name at least one engine');
    }
    return AgentEngineCatalog._({
      for (final entry in engines.entries)
        _localEngineName(entry.key): _localPolicy(entry.value),
    });
  }

  final Map<String, LocalAgentEnginePolicy> _local;

  Set<String> get engines => {codexAgentEngine, ..._local.keys};

  bool offers(String engine) =>
      engine == codexAgentEngine || _local.containsKey(engine);

  LocalAgentEnginePolicy? localPolicy(String engine) => _local[engine];

  /// The exact runner capabilities a profile for [engine] must declare.
  Set<String> capabilitiesFor(String engine) {
    if (engine == codexAgentEngine) return codexAgentCapabilities;
    final local = _local[engine];
    if (local != null) return local.capabilities;
    if (localModelAgentEngines.contains(engine)) {
      throw ApiError(
        422,
        'agent_engine_not_configured',
        'This deployment does not offer the $engine agent engine.',
        details: {'engine': engine, 'setting': localAgentEnginesSetting},
      );
    }
    throw const FormatException('engine is not supported');
  }
}

String _localEngineName(String engine) {
  if (!localModelAgentEngines.contains(engine)) {
    throw FormatException('$engine is not a local model engine');
  }
  return engine;
}

LocalAgentEnginePolicy _localPolicy(Object? value) {
  final json = _map(value, 'engine policy');
  _expectKeys(json, const {
    'profile',
    'capabilities',
    'resources',
  }, 'engine policy');
  final rawCapabilities = json['capabilities'];
  if (rawCapabilities is! List<Object?>) {
    throw const FormatException('capabilities must be a list');
  }
  final capabilities = [
    for (final item in rawCapabilities) _safeName(item, 'capability'),
  ];
  if (capabilities.toSet().length != capabilities.length ||
      !capabilities.toSet().containsAll(_localEngineContractCapabilities)) {
    throw const FormatException(
      'capabilities must be unique and include runtime-docker, '
      'github-app-token, and agent-usage-reporting',
    );
  }
  if (capabilities.contains('codex-oauth')) {
    throw const FormatException('a local engine cannot hold Codex authority');
  }
  final resources = _map(json['resources'], 'resources');
  _expectKeys(resources, _localEngineResources, 'resources');
  return LocalAgentEnginePolicy._(
    profile: _safeName(json['profile'], 'profile'),
    capabilities: capabilities.toSet(),
    resources: {
      'ram_mb': _boundedInt(resources['ram_mb'], 'ram_mb', 65536),
      'cpu': _boundedInt(resources['cpu'], 'cpu', 32),
      'disk_gb': _boundedInt(resources['disk_gb'], 'disk_gb', 1000),
      'vram_mb': _boundedInt(resources['vram_mb'], 'vram_mb', 131072),
      'timeout_s': _boundedInt(resources['timeout_s'], 'timeout_s', 7200),
    },
  );
}

final _immutableContainerImage = RegExp(r'^[^\s@]+@sha256:[0-9a-f]{64}$');
