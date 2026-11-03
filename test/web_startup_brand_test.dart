import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

void main() {
  testWidgets('Flutter startup surface carries the ii-os brand and progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: IiOsTheme.light(), home: const IiOsStartupView()),
    );

    expect(find.text('ii-os'), findsOneWidget);
    expect(find.text('Creative operations, in motion.'), findsOneWidget);
    expect(find.byType(IiOsMark), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.bySemanticsLabel('Opening your ii-os workspace'),
      findsOneWidget,
    );
  });

  test('web shell has a staged accessible loader and first-frame handoff', () {
    final index = File('web/index.html').readAsStringSync();
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, Object?>;

    expect(index, contains('id="ii-os-bootstrap"'));
    expect(index, contains('aria-live="polite"'));
    expect(index, contains('prefers-reduced-motion: reduce'));
    expect(index, contains('flutter_bootstrap.js" defer'));
    expect(bootstrap, contains('onEntrypointLoaded'));
    expect(bootstrap, contains('engineInitializer.initializeEngine()'));
    expect(bootstrap, contains("'ii-os-first-frame'"));
    expect(bootstrap, contains("'ii-os-startup-failed'"));
    expect(bootstrap, contains('start().catch(fail)'));
    expect(manifest['name'], 'ii-os · Creative operations');
    expect(manifest['background_color'], '#F4F6F5');
    expect(File('web/icons/ii-os-mark.svg').existsSync(), isTrue);
    expect(File('web/icons/ii-os-mask-icon.svg').existsSync(), isTrue);
    expect(File('web/apple-touch-icon.png').existsSync(), isTrue);
    expect(File('web/favicon.ico').existsSync(), isTrue);
    expect(File('web/icons/notification-badge-96.png').existsSync(), isTrue);
  });
}
