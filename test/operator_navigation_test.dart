import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/navigation/app_route_state.dart';
import 'package:ii_os/screens/operator_shell.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets('Creative contains Storyboards and Characters', (tester) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Creative studio',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: [],
          projects: [],
          workflows: [],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'member-1',
          email: 'member@example.com',
          role: 'member',
          roleLabel: 'Member',
          featureClaims: {},
          capabilities: {'jobs.read', 'jobs.trigger', 'characters.read'},
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: OperatorNavigation(
            controller: controller,
            page: AppPage.home,
            onSelect: (_, {itemId}) {},
          ),
        ),
      ),
    );

    expect(find.text('Storyboards'), findsOneWidget);
    expect(find.text('Characters'), findsOneWidget);

    await tester.tap(find.text('CREATIVE'));
    await tester.pump();

    expect(find.text('Storyboards'), findsNothing);
    expect(find.text('Characters'), findsNothing);
  });
}
