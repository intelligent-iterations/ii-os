import 'package:yaml/yaml.dart';

import 'api_error.dart';
import 'workflow_runtime_estimate.dart';

const _supportedWorkflowContractVersions = {1, 2};

final class WorkflowCatalog {
  const WorkflowCatalog({
    required this.repository,
    required this.repositoryId,
    required this.ref,
    required this.sha,
    required this.workflows,
  });

  factory WorkflowCatalog.parse({
    required String repository,
    int repositoryId = 0,
    required String ref,
    required String sha,
    required String content,
  }) {
    if (content.length > 256 * 1024) {
      throw _invalidCatalog('The workflow catalog is too large.');
    }
    Object? yaml;
    try {
      yaml = loadYaml(content);
    } on Object {
      throw _invalidCatalog('The workflow catalog is not valid YAML.');
    }
    final root = _stringMap(_plain(yaml), 'The catalog root must be a map.');
    _rejectUnknown(root, const {'schema_version', 'workflows'}, 'catalog');
    if (root['schema_version'] != 1) {
      throw _invalidCatalog('The workflow catalog schema version is unknown.');
    }
    final rawWorkflows = root['workflows'];
    if (rawWorkflows is! List<Object?> ||
        rawWorkflows.isEmpty ||
        rawWorkflows.length > 50) {
      throw _invalidCatalog('The catalog must contain 1 to 50 workflows.');
    }
    final workflows = rawWorkflows
        .map((value) => WorkflowDefinition.fromCatalogJson(_stringMap(value)))
        .toList();
    final ids = workflows.map((item) => item.id).toSet();
    if (ids.length != workflows.length) {
      throw _invalidCatalog('Workflow IDs must be unique in a repository.');
    }
    return WorkflowCatalog(
      repository: repository,
      repositoryId: repositoryId,
      ref: ref,
      sha: sha,
      workflows: workflows,
    );
  }

  factory WorkflowCatalog.fromJson(Map<String, Object?> json) {
    final rawWorkflows = json['workflows'];
    if (rawWorkflows is! List<Object?>) {
      throw _invalidCatalog('The stored workflow catalog is invalid.');
    }
    return WorkflowCatalog(
      repository: json['repository'] as String? ?? '',
      repositoryId: (json['repositoryId'] as num?)?.toInt() ?? 0,
      ref: json['ref'] as String? ?? '',
      sha: json['sha'] as String? ?? '',
      workflows: rawWorkflows
          .map((value) => WorkflowDefinition.fromJson(_stringMap(value)))
          .toList(),
    );
  }

  final String repository;
  final int repositoryId;
  final String ref;
  final String sha;
  final List<WorkflowDefinition> workflows;

  WorkflowDefinition? find(String id) {
    for (final workflow in workflows) {
      if (workflow.id == id) return workflow;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'repository': repository,
    'repositoryId': repositoryId,
    'ref': ref,
    'sha': sha,
    'workflows': workflows.map((item) => item.toJson()).toList(),
  };
}

final class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.model,
    required this.workType,
    required this.contractVersion,
    required this.dispatchWorkflow,
    required this.inputs,
    required this.outputs,
    required this.runtimeEstimates,
  });

  factory WorkflowDefinition.fromCatalogJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'id',
      'name',
      'model',
      'work_type',
      'contract_version',
      'dispatch_workflow',
      'inputs',
      'outputs',
      'runtime_estimates',
    }, 'workflow');
    final id = _boundedString(json['id'], 'workflow id', 64);
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id)) {
      throw _invalidCatalog('A workflow ID is invalid.');
    }
    final dispatch = _boundedString(
      json['dispatch_workflow'],
      'dispatch workflow',
      160,
    );
    if (!RegExp(
      r'^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$',
    ).hasMatch(dispatch)) {
      throw _invalidCatalog('A dispatch workflow path is invalid.');
    }
    final contractVersion = json['contract_version'];
    if (contractVersion is! int ||
        !_supportedWorkflowContractVersions.contains(contractVersion)) {
      throw _invalidCatalog('A workflow contract version is unsupported.');
    }
    final rawInputs = json['inputs'];
    if (rawInputs is! Map<String, Object?> || rawInputs.length > 30) {
      throw _invalidCatalog('Workflow inputs must be a bounded map.');
    }
    final inputs = <String, WorkflowInputDefinition>{};
    for (final entry in rawInputs.entries) {
      if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(entry.key) ||
          entry.key == 'ii_request_id') {
        throw _invalidCatalog('A workflow input name is invalid or reserved.');
      }
      inputs[entry.key] = WorkflowInputDefinition.fromCatalogJson(
        _stringMap(entry.value),
      );
    }
    final runtimeEstimates = parseWorkflowRuntimeEstimates(
      json['runtime_estimates'],
    );
    _validateRuntimeEstimateInputs(runtimeEstimates, inputs);
    final rawOutputs = json['outputs'];
    if (rawOutputs is! List<Object?> ||
        rawOutputs.isEmpty ||
        rawOutputs.length > 20) {
      throw _invalidCatalog('Workflow outputs must be a bounded list.');
    }
    return WorkflowDefinition(
      id: id,
      name: _boundedString(json['name'], 'workflow name', 100),
      model: json['model'] == null
          ? _boundedString(json['name'], 'workflow name', 100)
          : _boundedString(json['model'], 'workflow model', 100),
      workType: _parseWorkType(json['work_type'], rawOutputs),
      contractVersion: contractVersion,
      dispatchWorkflow: dispatch,
      inputs: inputs,
      outputs: rawOutputs
          .map((value) => WorkflowOutputDefinition.fromJson(_stringMap(value)))
          .toList(),
      runtimeEstimates: runtimeEstimates,
    );
  }

  factory WorkflowDefinition.fromJson(Map<String, Object?> json) {
    final rawInputs = _stringMap(json['inputs']);
    final rawOutputs = json['outputs'];
    return WorkflowDefinition(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      model:
          json['model'] as String? ??
          json['name'] as String? ??
          'Unknown model',
      workType: JobWorkType.parse(json['workType']),
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      dispatchWorkflow: json['dispatchWorkflow'] as String? ?? '',
      inputs: rawInputs.map(
        (key, value) =>
            MapEntry(key, WorkflowInputDefinition.fromJson(_stringMap(value))),
      ),
      outputs: rawOutputs is List<Object?>
          ? rawOutputs
                .map(
                  (value) =>
                      WorkflowOutputDefinition.fromJson(_stringMap(value)),
                )
                .toList()
          : <WorkflowOutputDefinition>[],
      runtimeEstimates: switch (json['runtimeEstimates']) {
        final List<Object?> values =>
          values
              .map(
                (value) => WorkflowRuntimeEstimate.fromJson(_stringMap(value)),
              )
              .toList(growable: false),
        _ => const [],
      },
    );
  }

  final String id;
  final String name;
  final String model;
  final JobWorkType workType;
  final int contractVersion;
  final String dispatchWorkflow;
  final Map<String, WorkflowInputDefinition> inputs;
  final List<WorkflowOutputDefinition> outputs;
  final List<WorkflowRuntimeEstimate> runtimeEstimates;

  Map<String, Object?>? runtimeEstimateFor(Map<String, String> inputs) {
    for (final estimate in runtimeEstimates) {
      final resolved = estimate.resolve(inputs);
      if (resolved != null) return resolved;
    }
    return null;
  }

  Map<String, String> validateInputs(Map<String, Object?> supplied) {
    final unknown = supplied.keys.where((key) => !inputs.containsKey(key));
    if (unknown.isNotEmpty) {
      throw ApiError(
        400,
        'invalid_job_input',
        'The job contains an undeclared input.',
        details: {'input': unknown.first},
      );
    }
    final result = <String, String>{};
    for (final entry in inputs.entries) {
      final present =
          supplied.containsKey(entry.key) && supplied[entry.key] != null;
      if (!present) {
        if (entry.value.required) {
          throw ApiError(
            400,
            'invalid_job_input',
            'A required workflow input is missing.',
            details: {'input': entry.key},
          );
        }
        continue;
      }
      result[entry.key] = entry.value.normalize(supplied[entry.key], entry.key);
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'model': model,
    'workType': workType.name,
    'contractVersion': contractVersion,
    'dispatchWorkflow': dispatchWorkflow,
    'inputs': inputs.map((key, value) => MapEntry(key, value.toJson())),
    'outputs': outputs.map((item) => item.toJson()).toList(),
    'runtimeEstimates': runtimeEstimates.map((item) => item.toJson()).toList(),
  };
}

enum JobWorkType {
  content,
  runtime,
  asset,
  host,
  other;

  static JobWorkType parse(Object? value) => switch (value) {
    final String name => values.firstWhere(
      (item) => item.name == name,
      orElse: () => other,
    ),
    _ => other,
  };
}

JobWorkType _parseWorkType(Object? value, List<Object?> outputs) {
  if (value != null) {
    final parsed = JobWorkType.parse(value);
    if (parsed == JobWorkType.other && value != 'other') {
      throw _invalidCatalog('A workflow work type is invalid.');
    }
    return parsed;
  }
  for (final output in outputs) {
    final definition = WorkflowOutputDefinition.fromJson(_stringMap(output));
    if (definition.contentTypes.any(
      (type) =>
          type.startsWith('image/') ||
          type.startsWith('video/') ||
          type.startsWith('audio/'),
    )) {
      return JobWorkType.content;
    }
  }
  return JobWorkType.other;
}

void _validateRuntimeEstimateInputs(
  List<WorkflowRuntimeEstimate> estimates,
  Map<String, WorkflowInputDefinition> inputs,
) {
  final selectors = <String>{};
  for (final estimate in estimates) {
    if (estimate.durationInput.isNotEmpty) {
      final duration = inputs[estimate.durationInput];
      if (duration == null || duration.type != WorkflowInputType.number) {
        throw _invalidCatalog(
          'A workflow runtime duration input must name a declared number input.',
        );
      }
      if ((duration.minimum != null &&
              estimate.baselineOutputSeconds < duration.minimum!) ||
          (duration.maximum != null &&
              estimate.baselineOutputSeconds > duration.maximum!)) {
        throw _invalidCatalog(
          'A workflow runtime baseline is outside its duration input range.',
        );
      }
    }
    for (final entry in estimate.selector.entries) {
      final input = inputs[entry.key];
      if (input == null || input.type != WorkflowInputType.string) {
        throw _invalidCatalog(
          'A workflow runtime selector must name a declared string input.',
        );
      }
      input.normalize(entry.value, entry.key);
    }
    final signature =
        estimate.selector.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .toList()
          ..sort();
    if (!selectors.add(signature.join('&'))) {
      throw _invalidCatalog('Workflow runtime selectors must be unique.');
    }
  }
}

enum WorkflowInputType { string, number, boolean }

final class WorkflowInputDefinition {
  const WorkflowInputDefinition({
    required this.type,
    required this.required,
    required this.maxLength,
    this.allowedValues = const [],
    this.minimum,
    this.maximum,
    this.defaultNumber,
  });

  factory WorkflowInputDefinition.fromCatalogJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'type',
      'required',
      'max_length',
      'allowed_values',
      'minimum',
      'maximum',
      'default',
    }, 'input');
    final rawType = json['type'];
    final type = WorkflowInputType.values
        .where((item) => item.name == rawType)
        .firstOrNull;
    if (type == null) {
      throw _invalidCatalog('A workflow input type is unsupported.');
    }
    final required = json['required'] ?? false;
    if (required is! bool) {
      throw _invalidCatalog('A workflow input required flag is invalid.');
    }
    final rawMaxLength = json['max_length'];
    final maxLength = rawMaxLength == null
        ? null
        : rawMaxLength is int && rawMaxLength > 0 && rawMaxLength <= 60000
        ? rawMaxLength
        : throw _invalidCatalog('A workflow input length is invalid.');
    if (type != WorkflowInputType.string && maxLength != null) {
      throw _invalidCatalog('Only string inputs can declare a maximum length.');
    }
    final allowedValues = _allowedStringValues(
      json['allowed_values'],
      type: type,
    );
    final minimum = _optionalFiniteNumber(json['minimum'], 'minimum');
    final maximum = _optionalFiniteNumber(json['maximum'], 'maximum');
    final defaultNumber = _optionalFiniteNumber(json['default'], 'default');
    if (type != WorkflowInputType.number &&
        (minimum != null || maximum != null || defaultNumber != null)) {
      throw _invalidCatalog(
        'Only number inputs can declare minimum, maximum, or default.',
      );
    }
    if (minimum != null && maximum != null && minimum > maximum) {
      throw _invalidCatalog('A workflow input range is invalid.');
    }
    if (defaultNumber != null &&
        ((minimum != null && defaultNumber < minimum) ||
            (maximum != null && defaultNumber > maximum))) {
      throw _invalidCatalog('A workflow input default is outside its range.');
    }
    return WorkflowInputDefinition(
      type: type,
      required: required,
      maxLength: maxLength,
      allowedValues: allowedValues,
      minimum: minimum,
      maximum: maximum,
      defaultNumber: defaultNumber,
    );
  }

  factory WorkflowInputDefinition.fromJson(Map<String, Object?> json) {
    return WorkflowInputDefinition(
      type: WorkflowInputType.values.firstWhere(
        (item) => item.name == json['type'],
        orElse: () => throw _invalidCatalog('A stored input type is invalid.'),
      ),
      required: json['required'] as bool? ?? false,
      maxLength: (json['maxLength'] as num?)?.toInt(),
      allowedValues: switch (json['allowedValues']) {
        final List<Object?> values => values.whereType<String>().toList(),
        _ => const [],
      },
      minimum: json['minimum'] as num?,
      maximum: json['maximum'] as num?,
      defaultNumber: json['default'] as num?,
    );
  }

  final WorkflowInputType type;
  final bool required;
  final int? maxLength;
  final List<String> allowedValues;
  final num? minimum;
  final num? maximum;
  final num? defaultNumber;

  String normalize(Object? value, String name) {
    return switch (type) {
      WorkflowInputType.string => _normalizeString(value, name),
      WorkflowInputType.number => _normalizeNumber(value, name),
      WorkflowInputType.boolean =>
        value is bool
            ? value.toString()
            : throw _invalidInput(name, 'must be true or false'),
    };
  }

  String _normalizeNumber(Object? value, String name) {
    if (value is! num || !value.isFinite) {
      throw _invalidInput(name, 'must be a finite number');
    }
    if (minimum != null && value < minimum!) {
      throw _invalidInput(name, 'must be at least $minimum');
    }
    if (maximum != null && value > maximum!) {
      throw _invalidInput(name, 'must be at most $maximum');
    }
    return value.toString();
  }

  String _normalizeString(Object? value, String name) {
    if (value is! String) throw _invalidInput(name, 'must be text');
    final normalized = value.trim();
    if (required && normalized.isEmpty) {
      throw _invalidInput(name, 'must not be empty');
    }
    if (maxLength != null && normalized.length > maxLength!) {
      throw _invalidInput(name, 'is too long');
    }
    if (normalized.isNotEmpty &&
        allowedValues.isNotEmpty &&
        !allowedValues.contains(normalized)) {
      throw _invalidInput(name, 'is not an allowed value');
    }
    return normalized;
  }

  Map<String, Object?> toJson() => {
    'type': type.name,
    'required': required,
    if (maxLength != null) 'maxLength': maxLength,
    if (allowedValues.isNotEmpty) 'allowedValues': allowedValues,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
    if (defaultNumber != null) 'default': defaultNumber,
  };
}

List<String> _allowedStringValues(
  Object? raw, {
  required WorkflowInputType type,
}) {
  if (raw == null) return const [];
  if (type != WorkflowInputType.string ||
      raw is! List<Object?> ||
      raw.isEmpty ||
      raw.length > 30) {
    throw _invalidCatalog(
      'Only string inputs can declare 1 to 30 allowed values.',
    );
  }
  final values = raw
      .map((value) => _boundedString(value, 'allowed input value', 120))
      .toList(growable: false);
  if (values.toSet().length != values.length) {
    throw _invalidCatalog('Workflow input allowed values must be unique.');
  }
  return values;
}

num? _optionalFiniteNumber(Object? value, String name) {
  if (value == null) return null;
  if (value is num && value.isFinite) return value;
  throw _invalidCatalog('A workflow input $name must be a finite number.');
}

final class WorkflowOutputDefinition {
  const WorkflowOutputDefinition({
    required this.kind,
    required this.contentTypes,
    required this.maxBytes,
  });

  factory WorkflowOutputDefinition.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'kind',
      'content_types',
      'max_bytes',
      'contentTypes',
      'maxBytes',
    }, 'output');
    final kind = _boundedString(json['kind'], 'output kind', 40);
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,39}$').hasMatch(kind)) {
      throw _invalidCatalog('A workflow output kind is invalid.');
    }
    final rawTypes = json['content_types'] ?? json['contentTypes'];
    if (rawTypes is! List<Object?> ||
        rawTypes.isEmpty ||
        rawTypes.length > 20 ||
        rawTypes.any(
          (value) =>
              value is! String ||
              !RegExp(r'^[a-z0-9.+-]+/[a-zA-Z0-9.+-]+$').hasMatch(value),
        )) {
      throw _invalidCatalog('Workflow output content types are invalid.');
    }
    final rawMaxBytes = json['max_bytes'] ?? json['maxBytes'];
    if (rawMaxBytes is! num ||
        rawMaxBytes.toInt() <= 0 ||
        rawMaxBytes.toInt() > 10 * 1024 * 1024 * 1024) {
      throw _invalidCatalog('A workflow output size is invalid.');
    }
    return WorkflowOutputDefinition(
      kind: kind,
      contentTypes: rawTypes.cast<String>(),
      maxBytes: rawMaxBytes.toInt(),
    );
  }

  final String kind;
  final List<String> contentTypes;
  final int maxBytes;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'contentTypes': contentTypes,
    'maxBytes': maxBytes,
  };
}

Object? _plain(Object? value) {
  if (value is YamlMap) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw _invalidCatalog('Workflow catalog keys must be strings.');
      }
      result[entry.key as String] = _plain(entry.value);
    }
    return result;
  }
  if (value is YamlList) return value.map(_plain).toList();
  return value;
}

Map<String, Object?> _stringMap([
  Object? value,
  String message = 'A workflow catalog entry must be a map.',
]) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw _invalidCatalog(message);
}

String _boundedString(Object? value, String field, int maxLength) {
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw _invalidCatalog('The $field is invalid.');
  }
  return value.trim();
}

void _rejectUnknown(
  Map<String, Object?> value,
  Set<String> allowed,
  String scope,
) {
  final unknown = value.keys.where((key) => !allowed.contains(key));
  if (unknown.isNotEmpty) {
    throw _invalidCatalog('The $scope contains an unknown field.');
  }
}

ApiError _invalidCatalog(String message) =>
    ApiError(422, 'workflow_catalog_invalid', message);

ApiError _invalidInput(String name, String reason) => ApiError(
  400,
  'invalid_job_input',
  'Workflow input $name $reason.',
  details: {'input': name},
);
