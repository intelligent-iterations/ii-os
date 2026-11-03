import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/data_plane_connection.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/project_admin_screen.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/state/app_controller.dart';

void main() {
  testWidgets('project settings advertise and queue automatic saves', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectAdminScreen(controller: controller)),
      ),
    );

    expect(find.text('Workspace setup'), findsOneWidget);
    expect(
      find.text(
        'Resources, workflows, and project tools · Changes save automatically',
      ),
      findsOneWidget,
    );
    expect(find.text('Set up this workspace in three steps'), findsOneWidget);
    expect(find.text('Organization resources'), findsOneWidget);
    expect(find.text('Workspace access'), findsOneWidget);
    expect(find.text('Generation workflows'), findsOneWidget);
    expect(
      find.textContaining('Resource access does not enable workflows'),
      findsWidgets,
    );
    expect(find.text('Legacy GitHub connection'), findsOneWidget);
    expect(find.text('Review GitHub connection'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Installation ID'), findsNothing);
    expect(find.widgetWithText(TextField, 'owner/repository'), findsNothing);
    expect(find.text('Saved automatically'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Updated workspace',
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Saving soon\u2026'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('GitHub Project setup discovers bounded choices', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectAdminScreen(controller: controller)),
      ),
    );

    final addProject = find.widgetWithText(FilledButton, 'Connect project');
    await tester.ensureVisible(addProject);
    await tester.tap(addProject);
    await tester.pump();

    expect(find.text('Connect a GitHub Project'), findsOneWidget);
    expect(find.text('Repository'), findsOneWidget);
    expect(find.text('Linked GitHub Projects'), findsOneWidget);
    expect(find.text('Display name'), findsNothing);
    expect(find.text('Organization owner'), findsNothing);
    expect(find.text('Project number'), findsNothing);
    expect(find.text('Project node ID'), findsNothing);
  });

  testWidgets('prompt enhancement autosave waits for a pasted key', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectAdminScreen(controller: controller)),
      ),
    );

    await tester.ensureVisible(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Needs attention'), findsOneWidget);

    final keyField = find.widgetWithText(TextField, 'DeepSeek API key');
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, 'sk-example-key-value');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Saving soon\u2026'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('prompt enhancement autosave waits for a valid secret', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectAdminScreen(controller: controller)),
      ),
    );

    await tester.ensureVisible(find.text('Secret Manager'));
    await tester.tap(find.text('Secret Manager'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Needs attention'), findsOneWidget);

    final secretField = find.widgetWithText(
      TextField,
      'DeepSeek API key secret version',
    );
    await tester.ensureVisible(secretField);
    await tester.enterText(
      secretField,
      'projects/example-project/secrets/deepseek-api-key/versions/latest',
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Saving soon\u2026'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

AppController _controller() {
  final connection = DataPlaneConnectionModel.empty().copyWith(
    workspaceId: 'workspace-1',
    projectId: 'example-project',
    databaseId: 'ii-os',
    region: 'us-central1',
    bucket: 'example-bucket',
    webOrigin: 'https://example.test',
  );
  final workspace = WorkspaceModel(
    id: 'workspace-1',
    name: 'Workspace',
    environment: 'dev',
    githubInstallationId: 123,
    repositories: const ['acme-co/example-app'],
    projects: const [],
    workflows: const [],
    artifactStorage: null,
    promptEnhancement: const PromptEnhancementModel(
      enabled: false,
      apiKeySecretVersion: '',
    ),
    connection: connection,
  );
  final membership = MembershipModel(
    workspaceId: workspace.id,
    uid: 'user-1',
    email: 'owner@example.com',
    role: 'owner',
    roleLabel: 'Owner',
    featureClaims: const {},
    capabilities: const {'workspace.manage'},
  );
  final controller = AppController(
    api: ApiClient(baseUrl: '', reportFailures: false),
  );
  controller.selectedAccess = WorkspaceAccess(
    workspace: workspace,
    membership: membership,
  );
  controller.connection = connection;
  return controller;
}
