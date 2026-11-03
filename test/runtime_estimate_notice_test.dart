import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/runtime_estimate.dart';
import 'package:ii_os/widgets/runtime_estimate_notice.dart';

void main() {
  testWidgets('a fixed estimate explains its observed basis', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RuntimeEstimateNotice(
            estimate: RuntimeEstimateSnapshot(
              estimatedSeconds: 45,
              hardware: '24 GB GPU',
              measuredAt: '2026-08-24',
              baselineOutputSeconds: 0,
              baselineRuntimeSeconds: 45,
              selectedInputs: {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('About 1 minute on 24 GB GPU'), findsOneWidget);
    expect(find.textContaining('from an observed render'), findsOneWidget);
    expect(find.textContaining('0-second'), findsNothing);
  });
}
