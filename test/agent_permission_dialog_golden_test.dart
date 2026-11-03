@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_permission.dart';
import 'package:ii_os/screens/agent_permission_dialog.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

import 'golden_harness.dart';

/// The dialog an owner reads before handing an agent authority over their code.
///
/// Pinned because the whole point of the surface is what it leads with. A change
/// that puts the runtime facts back above the two action lists is a change to
/// the decision being asked for, and should have to be deliberate.
void main() {
  setUpAll(loadIiOsFonts);

  testWidgets('permission dialog leads with allow and deny', (tester) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: Center(
            child: AgentPermissionDialog(initial: defaultAgentPermissionJson()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AgentPermissionDialog),
      matchesGoldenFile('goldens/agent_permission_dialog.png'),
    );
  });
}
