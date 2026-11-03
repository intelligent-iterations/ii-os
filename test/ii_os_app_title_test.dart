import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/config/app_config.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/ii_os_app_title.dart';

void main() {
  test('formats a deployment build number and short commit', () {
    expect(AppConfig.buildLabel(number: '12345'), 'Build #12345');
    expect(
      AppConfig.buildDetails(number: '12345', gitSha: 'abcdef0123456789'),
      'Build #12345 · commit abcdef0',
    );
  });

  testWidgets('signed-in title keeps the build number visible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(appBar: AppBar(title: const IiOsAppTitle())),
      ),
    );

    expect(find.text(AppConfig.buildLabel()), findsOneWidget);
  });
}
