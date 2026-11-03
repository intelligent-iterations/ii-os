import 'dart:convert';

import 'api_error.dart';
import 'domain.dart';
import 'organization_resources.dart';

final class FleetBuiltJob {
  const FleetBuiltJob({
    required this.jobId,
    required this.templateId,
    required this.templateVersion,
    required this.model,
    required this.normalizedInput,
    required this.request,
  });

  final String jobId;
  final String templateId;
  final String templateVersion;
  final String model;
  final Map<String, String> normalizedInput;
  final Map<String, Object?> request;
}

final class FleetTemplateCatalog {
  FleetTemplateCatalog._(this._templates);

  factory FleetTemplateCatalog.parse(String source) {
    if (source.trim().isEmpty) return FleetTemplateCatalog._(const {});
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> || decoded['schema_version'] != 1) {
        throw const FormatException('unsupported schema');
      }
      final rawTemplates = _requiredMap(decoded['templates'], 'templates');
      final templates = <String, FleetJobTemplate>{};
      for (final entry in rawTemplates.entries) {
        final raw = _requiredMap(entry.value, entry.key);
        final template = FleetJobTemplate.fromJson(entry.key, raw);
        templates[template.id] = template;
      }
      return FleetTemplateCatalog._(Map.unmodifiable(templates));
    } catch (_) {
      throw const ApiError(
        503,
        'fleet_templates_invalid',
        'Fleet job templates are not configured correctly.',
      );
    }
  }

  final Map<String, FleetJobTemplate> _templates;

  List<Map<String, Object?>> publicTemplates() {
    final result = _templates.values
        .map((item) => item.toPublicJson())
        .toList();
    result.sort(
      (left, right) => (left['displayName'] as String).compareTo(
        right['displayName'] as String,
      ),
    );
    return result;
  }

  FleetBuiltJob build({
    required Workspace workspace,
    required String actorUid,
    required String requestId,
    required String kind,
    required Map<String, Object?> input,
  }) {
    final template = _templates[kind];
    if (template == null) {
      throw const ApiError(
        400,
        'job_kind_not_allowed',
        'This job type is not allowlisted.',
      );
    }
    if (!template.enabled) {
      throw ApiError(
        409,
        'job_template_disabled',
        template.disabledReason.isEmpty
            ? 'This workflow is not ready for new runs.'
            : template.disabledReason,
      );
    }
    if (!_safeSegment.hasMatch(workspace.id) ||
        !_safeSegment.hasMatch(requestId)) {
      throw const ApiError(
        500,
        'job_identity_invalid',
        'The workspace or request identity is invalid.',
      );
    }
    final normalizedInput = normalizeFleetInput(kind, input);
    final placement = _resolvePlacement(workspace, template);
    final args = <String>[...template.baseArgs];
    for (final entry in normalizedInput.entries) {
      final flag = template.inputFlags[entry.key];
      if (flag == null || flag.isEmpty) {
        throw ApiError(
          503,
          'fleet_template_invalid',
          'Fleet template $kind does not map ${entry.key}.',
        );
      }
      args.addAll([flag, entry.value]);
    }
    final jobId = 'ii-os:${workspace.id}:$requestId';
    final submittedAt = DateTime.now().toUtc().toIso8601String();
    return FleetBuiltJob(
      jobId: jobId,
      templateId: template.id,
      templateVersion: template.version,
      model: template.displayName,
      normalizedInput: normalizedInput,
      request: {
        'job_id': jobId,
        'profile': template.profile,
        'resources': template.resources,
        'capabilities': template.capabilities,
        if (placement != null) 'pool': placement.pool.providerPoolId,
        'image': template.image,
        'runtime': {'kind': template.runtimeKind},
        'tags': {
          'workspace_id': workspace.id,
          'ii_os_job_kind': kind,
          'ii_os_template_version': template.version,
          'stream_id': 'ii-os:${workspace.id}:$requestId',
          'triggered_by_queue': 'true',
          'request_id': requestId,
          if (placement != null) 'runner_resource_id': placement.pool.id,
        },
        'runner': {
          'kind': 'direct-command',
          'registration': {
            'command': template.command,
            'args_json': jsonEncode(args),
            'cwd': template.cwd,
            'env_json': jsonEncode(template.environment),
            'artifact_paths_json': jsonEncode(template.artifactPaths),
            'artifact_prefix': 'workspaces/${workspace.id}/runs/$requestId',
            'max_log_bytes': template.maxLogBytes.toString(),
          },
        },
        'submitted_by': 'ii-os:$actorUid',
        'submitted_at': submittedAt,
      },
    );
  }

  _FleetPlacement? _resolvePlacement(
    Workspace workspace,
    FleetJobTemplate template,
  ) {
    if (!workspace.resourceGrantsExplicit) return null;
    final errors = workspace.resourceGrants.validateAgainst(
      workspace.organizationResources,
    );
    if (errors.isNotEmpty) {
      throw ApiError(
        409,
        'workspace_runner_grant_invalid',
        'The workspace runner grant is not currently valid.',
        details: {'errors': errors.toList()..sort()},
      );
    }
    final primary = workspace.resourceGrants.runners
        .where((item) => item.primary)
        .firstOrNull;
    final pool = primary == null
        ? null
        : workspace.organizationResources.runner(primary.resourceId);
    if (primary == null || pool == null || !pool.active) {
      throw const ApiError(
        409,
        'workspace_runner_pool_required',
        'Select one active workspace runner pool before starting this job.',
      );
    }
    if (pool.provider != 'fleet') {
      throw const ApiError(
        409,
        'runner_provider_unsupported',
        'This execution adapter requires a Fleet runner pool.',
      );
    }
    if (!_providerPoolId.hasMatch(pool.providerPoolId)) {
      throw const ApiError(
        409,
        'workspace_runner_pool_unenforced',
        'The selected resource is not bound to an enforceable Fleet pool.',
      );
    }
    final cpu = (template.resources['cpu'] as num?)?.toInt() ?? 0;
    final ram = (template.resources['ram_mb'] as num?)?.toInt() ?? 0;
    if (!primary.capabilities.containsAll(template.capabilities) ||
        cpu <= 0 ||
        ram <= 0 ||
        cpu > primary.maxCpu ||
        ram > primary.maxRamMiB) {
      throw const ApiError(
        409,
        'job_outside_runner_grant',
        'The job exceeds the selected workspace runner grant.',
      );
    }
    return _FleetPlacement(pool: pool);
  }
}

final class _FleetPlacement {
  const _FleetPlacement({required this.pool});

  final OrganizationRunnerPool pool;
}

final class FleetJobTemplate {
  const FleetJobTemplate({
    required this.id,
    required this.version,
    required this.displayName,
    required this.enabled,
    required this.disabledReason,
    required this.profile,
    required this.image,
    required this.runtimeKind,
    required this.resources,
    required this.capabilities,
    required this.command,
    required this.cwd,
    required this.baseArgs,
    required this.inputFlags,
    required this.environment,
    required this.artifactPaths,
    required this.maxLogBytes,
  });

  factory FleetJobTemplate.fromJson(String id, Map<String, Object?> json) {
    final execution = _requiredMap(json['execution'], 'execution');
    final resources = _requiredMap(execution['resources'], 'resources');
    final inputFlags = _requiredMap(
      execution['input_flags'],
      'input_flags',
    ).map((key, value) => MapEntry(key, value as String));
    final environment = _optionalMap(
      execution['environment'],
    ).map((key, value) => MapEntry(key, value.toString()));
    final template = FleetJobTemplate(
      id: id,
      version: json['version'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      enabled: json['enabled'] == true,
      disabledReason: json['disabled_reason'] as String? ?? '',
      profile: execution['profile'] as String? ?? '',
      image: execution['image'] as String? ?? '',
      runtimeKind: execution['runtime_kind'] as String? ?? '',
      resources: resources,
      capabilities: _requiredStrings(execution['capabilities'], 'capabilities'),
      command: execution['command'] as String? ?? '',
      cwd: execution['cwd'] as String? ?? '',
      baseArgs: _optionalStrings(execution['base_args']),
      inputFlags: inputFlags,
      environment: environment,
      artifactPaths: _requiredStrings(
        execution['artifact_paths'],
        'artifact_paths',
      ),
      maxLogBytes: (execution['max_log_bytes'] as num?)?.toInt() ?? 1048576,
    );
    if (!_safeSegment.hasMatch(template.id) ||
        !_safeSegment.hasMatch(template.version) ||
        template.displayName.isEmpty ||
        template.profile.isEmpty ||
        template.image.isEmpty ||
        !const {'docker', 'tart'}.contains(template.runtimeKind) ||
        template.command.isEmpty ||
        template.maxLogBytes < 0 ||
        template.maxLogBytes > 10485760 ||
        template.artifactPaths.any(
          (path) => path != 'artifacts' && !path.startsWith('artifacts/'),
        )) {
      throw const FormatException('Fleet template is incomplete');
    }
    return template;
  }

  final String id;
  final String version;
  final String displayName;
  final bool enabled;
  final String disabledReason;
  final String profile;
  final String image;
  final String runtimeKind;
  final Map<String, Object?> resources;
  final List<String> capabilities;
  final String command;
  final String cwd;
  final List<String> baseArgs;
  final Map<String, String> inputFlags;
  final Map<String, String> environment;
  final List<String> artifactPaths;
  final int maxLogBytes;

  Map<String, Object?> toPublicJson() => {
    'id': id,
    'version': version,
    'displayName': displayName,
    'enabled': enabled,
    if (!enabled && disabledReason.isNotEmpty) 'disabledReason': disabledReason,
  };
}

Map<String, String> normalizeFleetInput(
  String kind,
  Map<String, Object?> input,
) {
  final prompt = input['prompt'];
  if (prompt is! String || prompt.trim().isEmpty || prompt.length > 4000) {
    throw const ApiError(
      400,
      'invalid_prompt',
      'A prompt of at most 4,000 characters is required.',
    );
  }
  if (kind == 'image_create') {
    const dimensions = {
      '1:1': ('1024', '1024'),
      '4:5': ('896', '1120'),
      '3:2': ('1152', '768'),
      '16:9': ('1216', '684'),
      '9:16': ('684', '1216'),
    };
    final ratio = input['aspectRatio'] ?? '1:1';
    if (ratio is! String || !dimensions.containsKey(ratio)) {
      throw const ApiError(
        400,
        'invalid_aspect_ratio',
        'Aspect ratio is invalid.',
      );
    }
    final size = dimensions[ratio]!;
    final result = <String, String>{
      'prompt': prompt.trim(),
      'width': size.$1,
      'height': size.$2,
    };
    final seed = input['seed'];
    if (seed != null) {
      if (seed is! num || seed.toInt() < 0 || seed.toInt() > 2147483647) {
        throw const ApiError(
          400,
          'invalid_seed',
          'Seed must be a positive 32-bit integer.',
        );
      }
      result['seed'] = seed.toInt().toString();
    }
    return result;
  }
  if (kind == 'image_to_video') {
    final source = input['sourceImageUrl'];
    final uri = source is String ? Uri.tryParse(source.trim()) : null;
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'gs')) {
      throw const ApiError(
        400,
        'invalid_source_image',
        'A secure HTTPS or gs:// source image URL is required.',
      );
    }
    final duration = input['durationSeconds'] ?? 5;
    if (duration is! num || duration.toInt() < 2 || duration.toInt() > 20) {
      throw const ApiError(
        400,
        'invalid_duration',
        'Duration must be between 2 and 20 seconds.',
      );
    }
    return {
      'source_image_url': uri.toString(),
      'prompt': prompt.trim(),
      'duration_seconds': duration.toInt().toString(),
    };
  }
  throw const ApiError(
    400,
    'job_kind_not_allowed',
    'This job type is not allowlisted.',
  );
}

final RegExp _safeSegment = RegExp(r'^[A-Za-z0-9._-]{1,128}$');
final RegExp _providerPoolId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Map<String, Object?> _requiredMap(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$name must be an object');
}

Map<String, Object?> _optionalMap(Object? value) {
  return value is Map<String, Object?> ? value : <String, Object?>{};
}

List<String> _requiredStrings(Object? value, String name) {
  final result = _optionalStrings(value);
  if (result.isEmpty) throw FormatException('$name must not be empty');
  return result;
}

List<String> _optionalStrings(Object? value) {
  return value is List<Object?>
      ? value.whereType<String>().toList()
      : <String>[];
}
