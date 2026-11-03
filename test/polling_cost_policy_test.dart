import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/polling_cost_policy.dart';

void main() {
  test('active-operation polling has one reviewed bounded cadence', () {
    expect(
      IiOsPollingCostPolicy.activeOperation,
      greaterThanOrEqualTo(const Duration(seconds: 2)),
    );
  });
}
