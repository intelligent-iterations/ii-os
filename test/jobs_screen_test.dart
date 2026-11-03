import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/screens/jobs_table.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets('jobs show their work type and workflow and remain clickable', (
    tester,
  ) async {
    String? selectedJobId;
    String? copiedText;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: JobsTable(
            jobs: const [
              {
                'jobId': 'content-job-1',
                'status': 'completed',
                'workType': 'content',
                'kind': 'video-create',
                'workflowName': 'MiniMax H3 video',
                'repository': 'acme/media',
                'githubUrl':
                    'https://github.com/acme/media/actions/runs/123456789',
                'submittedAt': '2026-08-21T12:00:00Z',
              },
              {
                'jobId': 'runtime-job-1',
                'status': 'running',
                'workType': 'runtime',
                'kind': 'mobile-update-android',
              },
              {
                'jobId': 'asset-job-1',
                'status': 'requested',
                'workType': 'asset',
                'kind': 'asset-import',
              },
              {
                'jobId': 'host-job-1',
                'status': 'completed',
                'workType': 'host',
                'kind': 'host-maintenance',
              },
              {
                'jobId': 'other-job-1',
                'status': 'completed',
                'workType': 'other',
                'kind': 'custom-job',
              },
            ],
            onSelectJob: (jobId) => selectedJobId = jobId,
          ),
        ),
      ),
    );

    expect(find.text('WORK TYPE'), findsOneWidget);
    expect(find.text('WORKFLOW'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Runtime'), findsOneWidget);
    expect(find.text('Asset'), findsOneWidget);
    expect(find.text('Computer host'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('MiniMax H3 video'), findsOneWidget);
    expect(find.text('GITHUB ACTIONS'), findsOneWidget);
    expect(
      find.text('https://github.com/acme/media/actions/runs/123456789'),
      findsOneWidget,
    );
    expect(find.byTooltip('Open GitHub Actions run'), findsOneWidget);
    expect(find.byTooltip('Copy GitHub Actions URL'), findsOneWidget);

    final copyAction = find.byTooltip('Copy GitHub Actions URL');
    await tester.ensureVisible(copyAction);
    await tester.tap(copyAction);
    expect(copiedText, 'https://github.com/acme/media/actions/runs/123456789');

    final contentWorkType = find.text('Content');
    await tester.ensureVisible(contentWorkType);
    await tester.tap(contentWorkType);

    expect(selectedJobId, 'content-job-1');
  });
}
