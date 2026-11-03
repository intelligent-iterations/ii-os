part of 'agent_permission_profile.dart';

final class AgentFleetPolicy {
  const AgentFleetPolicy({
    required this.profile,
    required this.image,
    required this.runtimeKind,
    required this.resources,
    required this.capabilities,
  });

  factory AgentFleetPolicy.parse(Object? value) {
    final json = _map(value, 'fleet');
    _expectKeys(json, const {
      'profile',
      'image',
      'runtime_kind',
      'resources',
      'capabilities',
    }, 'fleet');
    final runtimeKind = _text(json['runtime_kind'], 'runtime_kind', 20);
    if (runtimeKind != 'docker') {
      throw const FormatException('runtime_kind must be docker');
    }
    final resources = _map(json['resources'], 'resources');
    _expectKeys(resources, {
      'ram_mb',
      'cpu',
      'disk_gb',
      'timeout_s',
      if (resources.containsKey('vram_mb')) 'vram_mb',
    }, 'resources');
    final normalizedResources = <String, Object?>{
      'ram_mb': _boundedInt(resources['ram_mb'], 'ram_mb', 65536),
      'cpu': _boundedInt(resources['cpu'], 'cpu', 32),
      'disk_gb': _boundedInt(resources['disk_gb'], 'disk_gb', 1000),
      if (resources.containsKey('vram_mb'))
        'vram_mb': _boundedInt(resources['vram_mb'], 'vram_mb', 131072),
      'timeout_s': _boundedInt(resources['timeout_s'], 'timeout_s', 7200),
    };
    final capabilities = _strings(
      json['capabilities'],
      'capabilities',
      required: true,
      safeNames: true,
    );
    if (!capabilities.contains('runtime-$runtimeKind')) {
      throw const FormatException('runtime capability is required');
    }
    return AgentFleetPolicy(
      profile: _safeName(json['profile'], 'profile'),
      image: _immutableImageReference(json['image']),
      runtimeKind: runtimeKind,
      resources: normalizedResources,
      capabilities: capabilities,
    );
  }

  final String profile;
  final String image;
  final String runtimeKind;
  final Map<String, Object?> resources;
  final List<String> capabilities;

  Map<String, Object?> toJson() => {
    'profile': profile,
    'image': image,
    'runtime_kind': runtimeKind,
    'resources': resources,
    'capabilities': capabilities,
  };
}

final class AgentSecretInjection {
  const AgentSecretInjection({
    required this.environment,
    required this.bindings,
  });

  factory AgentSecretInjection.parse(Object? value) {
    final json = _map(value, 'secret_injection');
    _expectKeys(json, const {'environment', 'bindings'}, 'secret_injection');
    final rawBindings = json['bindings'];
    if (rawBindings is! List<Object?>) {
      throw const FormatException('secret bindings must be a list');
    }
    final bindings = rawBindings.map(AgentSecretBinding.parse).toList();
    if (bindings.map((item) => item.id).toSet().length != bindings.length) {
      throw const FormatException('secret binding ids must be unique');
    }
    return AgentSecretInjection(
      environment: _safeName(json['environment'], 'environment'),
      bindings: bindings,
    );
  }

  final String environment;
  final List<AgentSecretBinding> bindings;

  Map<String, Object?> toJson() => {
    'environment': environment,
    'bindings': bindings.map((item) => item.toJson()).toList(),
  };
}

final class AgentSecretBinding {
  const AgentSecretBinding({
    required this.id,
    required this.capability,
    required this.githubSecret,
    required this.target,
    required this.targetName,
  });

  factory AgentSecretBinding.parse(Object? value) {
    final json = _map(value, 'secret binding');
    _expectKeys(json, const {
      'id',
      'capability',
      'github_secret',
      'target',
      'target_name',
    }, 'secret binding');
    final githubSecret = json['github_secret'];
    if (githubSecret is! String || !_secretName.hasMatch(githubSecret)) {
      throw const FormatException('github_secret is invalid');
    }
    final target = _text(json['target'], 'target', 20);
    if (target != 'file' && target != 'environment') {
      throw const FormatException('secret target is invalid');
    }
    final targetName = _text(json['target_name'], 'target_name', 128);
    if (!_secretName.hasMatch(targetName)) {
      throw const FormatException('secret target_name is invalid');
    }
    return AgentSecretBinding(
      id: _safeName(json['id'], 'secret id'),
      capability: _safeName(json['capability'], 'secret capability'),
      githubSecret: githubSecret,
      target: target,
      targetName: targetName,
    );
  }

  final String id;
  final String capability;
  final String githubSecret;
  final String target;
  final String targetName;

  Map<String, Object?> toJson() => {
    'id': id,
    'capability': capability,
    'github_secret': githubSecret,
    'target': target,
    'target_name': targetName,
  };
}

final class AgentWorkflowPolicy {
  const AgentWorkflowPolicy({required this.file, required this.ref});

  factory AgentWorkflowPolicy.parse(Object? value) {
    final json = _map(value, 'workflow');
    _expectKeys(json, const {'file', 'ref'}, 'workflow');
    final file = _text(json['file'], 'workflow file', 200);
    if (!_workflowFile.hasMatch(file)) {
      throw const FormatException('workflow file is invalid');
    }
    return AgentWorkflowPolicy(file: file, ref: _safeRef(json['ref']));
  }

  final String file;
  final String ref;

  Map<String, Object?> toJson() => {'file': file, 'ref': ref};
}

final RegExp _safeNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final RegExp _safeRefPattern = RegExp(
  r'^(?!/)(?!.*(?:\.\.|//))[A-Za-z0-9._/-]{1,200}$',
);
final RegExp _secretName = RegExp(r'^[A-Z][A-Z0-9_]{0,127}$');
final RegExp _workflowFile = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*\.ya?ml$');
final RegExp _immutableImage = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:/-]*@sha256:[a-f0-9]{64}$',
);

Map<String, Object?> _map(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('$name must be an object');
}

void _expectKeys(Map<String, Object?> value, Set<String> allowed, String name) {
  if (value.keys.toSet().length != allowed.length ||
      !value.keys.toSet().containsAll(allowed)) {
    throw FormatException('$name has missing or unknown fields');
  }
}

String _safeName(Object? value, String name) {
  if (value is! String || !_safeNamePattern.hasMatch(value)) {
    throw FormatException('$name is invalid');
  }
  return value;
}

String _safeRef(Object? value) {
  if (value is! String || !_safeRefPattern.hasMatch(value)) {
    throw const FormatException('ref is invalid');
  }
  return value;
}

String _text(Object? value, String name, int maxLength) {
  if (value is! String ||
      value.trim().isEmpty ||
      value != value.trim() ||
      value.length > maxLength) {
    throw FormatException('$name is invalid');
  }
  return value;
}

String _immutableImageReference(Object? value) {
  final image = _text(value, 'image', 500);
  if (!_immutableImage.hasMatch(image)) {
    throw const FormatException(
      'image must be pinned to an immutable sha256 digest',
    );
  }
  return image;
}

int _boundedInt(Object? value, String name, int maximum) {
  if (value is! int || value <= 0) {
    throw FormatException('$name must be a positive integer');
  }
  if (value > maximum) {
    throw FormatException('$name exceeds its maximum');
  }
  return value;
}

List<String> _strings(
  Object? value,
  String name, {
  bool required = false,
  bool allowEmpty = false,
  bool safeNames = false,
}) {
  if (value == null && !required) return const [];
  if (value is! List<Object?>) throw FormatException('$name must be a list');
  final result = <String>[];
  for (final item in value) {
    if (item is! String ||
        item.trim().isEmpty ||
        item != item.trim() ||
        item.length > 300) {
      throw FormatException('$name contains an invalid value');
    }
    if (safeNames && !_safeNamePattern.hasMatch(item)) {
      throw FormatException('$name contains an invalid capability');
    }
    result.add(item);
  }
  if (required && result.isEmpty && !allowEmpty) {
    throw FormatException('$name must not be empty');
  }
  if (result.toSet().length != result.length) {
    throw FormatException('$name contains duplicates');
  }
  return List.unmodifiable(result);
}
