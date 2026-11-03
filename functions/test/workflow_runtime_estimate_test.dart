import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workflow_runtime_estimate.dart';
import 'package:test/test.dart';

void main() {
  test('resolves a fixed observed runtime without a duration input', () {
    final estimate = WorkflowRuntimeEstimate.fromCatalogJson(const {
      'baseline_runtime_seconds': 45,
      'hardware': 'Example GPU 24 GB',
      'measured_at': '2026-08-24',
    });

    expect(estimate.resolve(const {}), {
      'estimatedSeconds': 45,
      'hardware': 'Example GPU 24 GB',
      'basis': 'observed',
      'measuredAt': '2026-08-24',
      'baselineRuntimeSeconds': 45,
      'selectedInputs': const <String, String>{},
    });
  });

  test('rejects a normalized but nonexistent measurement date', () {
    expect(
      () => WorkflowRuntimeEstimate.fromCatalogJson(const {
        'selector': {'performance_mode': 'turbo'},
        'duration_input': 'duration_seconds',
        'baseline_output_seconds': 15,
        'baseline_runtime_seconds': 900,
        'hardware': 'Example GPU 24 GB',
        'measured_at': '2026-02-30',
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'workflow_catalog_invalid',
        ),
      ),
    );
  });

  test('rejects a scaled estimate with only one duration field', () {
    expect(
      () => WorkflowRuntimeEstimate.fromCatalogJson(const {
        'duration_input': 'duration_seconds',
        'baseline_runtime_seconds': 45,
        'hardware': 'Example GPU 24 GB',
        'measured_at': '2026-08-24',
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'workflow_catalog_invalid',
        ),
      ),
    );
  });
}
