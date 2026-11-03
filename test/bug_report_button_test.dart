import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/services/bug_report_client.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/bug_report_button.dart';

void main() {
  testWidgets('bug report action is visible at desktop and mobile widths', (
    tester,
  ) async {
    for (final variant in const [
      (size: Size(390, 844), compact: true),
      (size: Size(1440, 900), compact: false),
    ]) {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            appBar: AppBar(
              actions: [
                BugReportButton(
                  compact: variant.compact,
                  currentRoute: '/workspaces/workspace-1/home',
                  onSubmit: (_) async => 'report-1',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('bug-report-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('collects bug details and an optional screenshot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    BugReportDraft? submitted;
    final screenshot = BugReportScreenshot(
      filename: 'bug.png',
      bytes: Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
          '2mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
      contentType: 'image/png',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              BugReportButton(
                compact: true,
                currentRoute: '/workspaces/workspace-1/generate',
                pickScreenshot: () async => screenshot,
                onSubmit: (draft) async {
                  submitted = draft;
                  return '123e4567-e89b-42d3-a456-426614174000';
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('bug-report-button')));
    await tester.pumpAndSettle();
    expect(find.text('What went wrong?'), findsOneWidget);
    expect(find.text('Attach screenshot'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('bug-description-field')),
      'The output stayed blank after generation finished.',
    );
    await tester.enterText(
      find.byKey(const Key('bug-expected-field')),
      'The generated image should replace the loading state.',
    );
    await tester.pump();
    await tester.tap(find.text('Attach screenshot'));
    await tester.pumpAndSettle();
    expect(find.text('bug.png'), findsOneWidget);

    await tester.tap(find.byKey(const Key('send-bug-report-button')));
    await tester.pumpAndSettle();

    expect(submitted?.description, contains('output stayed blank'));
    expect(submitted?.expectedBehavior, contains('generated image'));
    expect(submitted?.route, '/workspaces/workspace-1/generate');
    expect(submitted?.screenshot?.filename, 'bug.png');
    expect(find.textContaining('123e4567'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the dialog open when submission fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: BugReportButton(
            currentRoute: '/workspaces/workspace-1/home',
            onSubmit: (_) async => throw StateError('Service unavailable'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('bug-report-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('bug-description-field')),
      'Refresh stopped working.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-bug-report-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bug-report-error')), findsOneWidget);
    expect(find.textContaining('Service unavailable'), findsOneWidget);
    expect(find.text('Report a bug'), findsWidgets);
  });
}
