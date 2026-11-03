final class WorkflowRuntimeEstimateModel {
  const WorkflowRuntimeEstimateModel({
    required this.selector,
    required this.durationInput,
    required this.baselineOutputSeconds,
    required this.baselineRuntimeSeconds,
    required this.hardware,
    required this.measuredAt,
  });

  factory WorkflowRuntimeEstimateModel.fromJson(Map<String, Object?> json) =>
      WorkflowRuntimeEstimateModel(
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

  RuntimeEstimateSnapshot? resolve(Map<String, Object?> inputs) {
    if (baselineRuntimeSeconds <= 0 ||
        hardware.isEmpty ||
        selector.entries.any(
          (entry) => inputs[entry.key]?.toString() != entry.value,
        )) {
      return null;
    }
    if (durationInput.isEmpty && baselineOutputSeconds == 0) {
      return RuntimeEstimateSnapshot(
        estimatedSeconds: baselineRuntimeSeconds,
        hardware: hardware,
        measuredAt: measuredAt,
        baselineOutputSeconds: 0,
        baselineRuntimeSeconds: baselineRuntimeSeconds,
        selectedInputs: selector,
      );
    }
    if (durationInput.isEmpty || baselineOutputSeconds <= 0) return null;
    final outputSeconds = switch (inputs[durationInput]) {
      final num value => value.toDouble(),
      final Object value => double.tryParse(value.toString()),
      null => null,
    };
    if (outputSeconds == null ||
        !outputSeconds.isFinite ||
        outputSeconds <= 0) {
      return null;
    }
    return RuntimeEstimateSnapshot(
      estimatedSeconds:
          (baselineRuntimeSeconds * outputSeconds / baselineOutputSeconds)
              .round()
              .clamp(1, 7 * 24 * 60 * 60),
      hardware: hardware,
      measuredAt: measuredAt,
      baselineOutputSeconds: baselineOutputSeconds,
      baselineRuntimeSeconds: baselineRuntimeSeconds,
      selectedInputs: selector,
    );
  }
}

final class RuntimeEstimateSnapshot {
  const RuntimeEstimateSnapshot({
    required this.estimatedSeconds,
    required this.hardware,
    required this.measuredAt,
    required this.baselineOutputSeconds,
    required this.baselineRuntimeSeconds,
    required this.selectedInputs,
  });

  static RuntimeEstimateSnapshot? fromJob(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<Object?, Object?>();
    final estimatedSeconds = (json['estimatedSeconds'] as num?)?.toInt() ?? 0;
    final hardware = json['hardware'] as String? ?? '';
    if (estimatedSeconds <= 0 || hardware.isEmpty) return null;
    return RuntimeEstimateSnapshot(
      estimatedSeconds: estimatedSeconds,
      hardware: hardware,
      measuredAt: json['measuredAt'] as String? ?? '',
      baselineOutputSeconds:
          (json['baselineOutputSeconds'] as num?)?.toInt() ?? 0,
      baselineRuntimeSeconds:
          (json['baselineRuntimeSeconds'] as num?)?.toInt() ?? 0,
      selectedInputs: _stringMap(json['selectedInputs']),
    );
  }

  final int estimatedSeconds;
  final String hardware;
  final String measuredAt;
  final int baselineOutputSeconds;
  final int baselineRuntimeSeconds;
  final Map<String, String> selectedInputs;

  String get durationLabel => formatRuntimeSeconds(estimatedSeconds);
}

String formatRuntimeSeconds(int seconds) {
  final minutes = (seconds / 60).round().clamp(1, 7 * 24 * 60);
  if (minutes == 1) return '1 minute';
  if (minutes < 60) return '$minutes minutes';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hours' : '$hours hr $remainder min';
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}
