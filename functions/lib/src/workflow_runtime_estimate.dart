import 'api_error.dart';

/// An observed runtime baseline published by a workflow owner.
///
/// The control plane resolves the matching baseline against normalized,
/// catalog-validated inputs. Clients never get to supply this metadata.
final class WorkflowRuntimeEstimate {
  const WorkflowRuntimeEstimate({
    required this.selector,
    required this.durationInput,
    required this.baselineOutputSeconds,
    required this.baselineRuntimeSeconds,
    required this.hardware,
    required this.measuredAt,
  });

  factory WorkflowRuntimeEstimate.fromCatalogJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'selector',
      'duration_input',
      'baseline_output_seconds',
      'baseline_runtime_seconds',
      'hardware',
      'measured_at',
    });
    final selector = _selector(json['selector']);
    final durationInput = _optionalBoundedString(
      json['duration_input'],
      'duration input',
      64,
    );
    final baselineOutputSeconds = _optionalBoundedInt(
      json['baseline_output_seconds'],
      'baseline output seconds',
      maximum: 86400,
    );
    if ((durationInput == null) != (baselineOutputSeconds == null)) {
      throw _invalid(
        'A scaled workflow runtime estimate must declare both its duration '
        'input and baseline output seconds.',
      );
    }
    return WorkflowRuntimeEstimate(
      selector: selector,
      durationInput: durationInput ?? '',
      baselineOutputSeconds: baselineOutputSeconds ?? 0,
      baselineRuntimeSeconds: _boundedInt(
        json['baseline_runtime_seconds'],
        'baseline runtime seconds',
        maximum: 7 * 24 * 60 * 60,
      ),
      hardware: _boundedString(json['hardware'], 'hardware', 100),
      measuredAt: _date(json['measured_at']),
    );
  }

  factory WorkflowRuntimeEstimate.fromJson(Map<String, Object?> json) =>
      WorkflowRuntimeEstimate(
        selector: _stringMap(json['selector']),
        durationInput: json['durationInput'] as String? ?? '',
        baselineOutputSeconds:
            (json['baselineOutputSeconds'] as num?)?.toInt() ?? 0,
        baselineRuntimeSeconds:
            (json['baselineRuntimeSeconds'] as num?)?.toInt() ?? 0,
        hardware: json['hardware'] as String? ?? '',
        measuredAt: json['measuredAt'] as String? ?? '',
      );

  final Map<String, String> selector;
  final String durationInput;
  final int baselineOutputSeconds;
  final int baselineRuntimeSeconds;
  final String hardware;
  final String measuredAt;

  bool matches(Map<String, String> inputs) =>
      selector.entries.every((entry) => inputs[entry.key] == entry.value);

  Map<String, Object?>? resolve(Map<String, String> inputs) {
    if (!matches(inputs)) return null;
    if (durationInput.isEmpty && baselineOutputSeconds == 0) {
      return {
        'estimatedSeconds': baselineRuntimeSeconds,
        'hardware': hardware,
        'basis': 'observed',
        'measuredAt': measuredAt,
        'baselineRuntimeSeconds': baselineRuntimeSeconds,
        'selectedInputs': selector,
      };
    }
    final outputSeconds = double.tryParse(inputs[durationInput] ?? '');
    if (outputSeconds == null ||
        !outputSeconds.isFinite ||
        outputSeconds <= 0) {
      return null;
    }
    final estimatedSeconds =
        (baselineRuntimeSeconds * outputSeconds / baselineOutputSeconds)
            .round()
            .clamp(1, 7 * 24 * 60 * 60);
    return {
      'estimatedSeconds': estimatedSeconds,
      'hardware': hardware,
      'basis': 'observed',
      'measuredAt': measuredAt,
      'baselineOutputSeconds': baselineOutputSeconds,
      'baselineRuntimeSeconds': baselineRuntimeSeconds,
      'durationInput': durationInput,
      'selectedInputs': selector,
    };
  }

  Map<String, Object?> toJson() => {
    'selector': selector,
    if (durationInput.isNotEmpty) 'durationInput': durationInput,
    if (baselineOutputSeconds > 0)
      'baselineOutputSeconds': baselineOutputSeconds,
    'baselineRuntimeSeconds': baselineRuntimeSeconds,
    'hardware': hardware,
    'measuredAt': measuredAt,
  };
}

List<WorkflowRuntimeEstimate> parseWorkflowRuntimeEstimates(Object? value) {
  if (value == null) return const [];
  if (value is! List<Object?> || value.isEmpty || value.length > 20) {
    throw _invalid('Workflow runtime estimates must contain 1 to 20 entries.');
  }
  return value
      .map((item) => WorkflowRuntimeEstimate.fromCatalogJson(_objectMap(item)))
      .toList(growable: false);
}

Map<String, String> _selector(Object? value) {
  if (value == null) return const {};
  final raw = _objectMap(value);
  if (raw.length > 10) {
    throw _invalid('A workflow runtime selector may contain up to 10 inputs.');
  }
  return raw.map((key, value) {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key)) {
      throw _invalid('A workflow runtime selector input is invalid.');
    }
    return MapEntry(key, _boundedString(value, 'selector value', 100));
  });
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw _invalid('A workflow runtime estimate must be a map.');
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}

String _boundedString(Object? value, String field, int maximum) {
  if (value is! String || value.trim().isEmpty || value.length > maximum) {
    throw _invalid('The workflow runtime $field is invalid.');
  }
  return value.trim();
}

int _boundedInt(Object? value, String field, {required int maximum}) {
  if (value is! int || value <= 0 || value > maximum) {
    throw _invalid('The workflow runtime $field is invalid.');
  }
  return value;
}

String? _optionalBoundedString(Object? value, String field, int maximum) =>
    value == null ? null : _boundedString(value, field, maximum);

int? _optionalBoundedInt(Object? value, String field, {required int maximum}) =>
    value == null ? null : _boundedInt(value, field, maximum: maximum);

String _date(Object? value) {
  final date = _boundedString(value, 'measurement date', 10);
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (match == null) {
    throw _invalid('The workflow runtime measurement date is invalid.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw _invalid('The workflow runtime measurement date is invalid.');
  }
  return date;
}

void _rejectUnknown(Map<String, Object?> value, Set<String> allowed) {
  final unknown = value.keys.where((key) => !allowed.contains(key));
  if (unknown.isNotEmpty) {
    throw _invalid('A workflow runtime estimate contains an unknown field.');
  }
}

ApiError _invalid(String message) =>
    ApiError(422, 'workflow_catalog_invalid', message);
