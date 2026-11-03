import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/runtime_estimate.dart';

void main() {
  test('resolves a fixed observed runtime without a duration input', () {
    const estimate = WorkflowRuntimeEstimateModel(
      selector: {},
      durationInput: '',
      baselineOutputSeconds: 0,
      baselineRuntimeSeconds: 45,
      hardware: '24 GB GPU',
      measuredAt: '2026-08-24',
    );

    final resolved = estimate.resolve(const {});

    expect(resolved?.estimatedSeconds, 45);
    expect(resolved?.durationLabel, '1 minute');
  });
}
