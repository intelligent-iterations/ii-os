@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/runtime_estimate.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/runtime_estimate_notice.dart';

void main() {
  testWidgets('runtime estimate notice communicates the useful uncertainty', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: IiOsTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: RuntimeEstimateNotice(
              estimate: RuntimeEstimateSnapshot(
                estimatedSeconds: 900,
                hardware: '24 GB GPU',
                measuredAt: '2026-08-14',
                baselineOutputSeconds: 15,
                baselineRuntimeSeconds: 900,
                selectedInputs: {'performance_mode': 'turbo'},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(RuntimeEstimateNotice),
      matchesGoldenFile('goldens/runtime_estimate_notice.png'),
    );
  });

  testWidgets('fixed runtime estimate notice explains its observed basis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: IiOsTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: RuntimeEstimateNotice(
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
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(RuntimeEstimateNotice),
      matchesGoldenFile('goldens/runtime_estimate_notice_fixed.png'),
    );
  });
}
