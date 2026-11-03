import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/screens/playground_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets('Ghost mode clearly switches Playground retention behavior', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()..selectedAccess = _workspaceAccess();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(body: PlaygroundScreen(controller: controller)),
      ),
    );

    expect(
      find.text('Generations are saved to workspace history.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('playground-ghost-mode')));
    await tester.pump();

    expect(
      find.text(
        'Nothing is added to history. Keep this tab open and download the '
        'result\u2014closing it discards your only copy.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (status, label, locked) in [
    (
      WorkflowRuntimeStatus.unavailable,
      'Classify, Open JEV runtime not installed',
      true,
    ),
    (
      WorkflowRuntimeStatus.unknown,
      'Classify, Open JEV runtime status not confirmed yet',
      false,
    ),
  ]) {
    testWidgets('Classify tab is visually gated while the runtime is $status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = AppController()..selectedAccess = _workspaceAccess();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            body: PlaygroundScreen(
              controller: controller,
              templateRepository: _ClassificationTemplates(status),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel(RegExp('^$label')), findsOneWidget);
      expect(
        find.byIcon(LucideIcons.lock),
        locked ? findsOneWidget : findsNothing,
      );
      semantics.dispose();
    });
  }

  testWidgets('Classify tab reads as ready once the runtime is installed', (
    tester,
  ) async {
    final controller = AppController()..selectedAccess = _workspaceAccess();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: PlaygroundScreen(
            controller: controller,
            templateRepository: const _ClassificationTemplates(
              WorkflowRuntimeStatus.available,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Classify'), findsOneWidget);
    expect(find.byIcon(LucideIcons.lock), findsNothing);
    expect(find.byIcon(LucideIcons.clock3), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });
}

final class _ClassificationTemplates implements WorkflowTemplateRepository {
  const _ClassificationTemplates(this.status);

  final WorkflowRuntimeStatus status;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async => [
    if (workflowIdPrefix == null ||
        'classification-open-jev-9b'.startsWith(workflowIdPrefix))
      WorkflowTemplateModel(
        id: 'acme-co/example-app#classification-open-jev-9b',
        workflowId: 'classification-open-jev-9b',
        version: '1',
        displayName: 'Open JEV 9B Classification',
        model: 'autotrust/JEV-9B',
        repository: 'acme-co/example-app',
        enabled: status == WorkflowRuntimeStatus.available,
        disabledReason: '',
        runtime: WorkflowRuntimeRequirement(status: status),
      ),
  ];
}

WorkspaceAccess _workspaceAccess() => const WorkspaceAccess(
  workspace: WorkspaceModel(
    id: 'workspace-1',
    name: 'Example',
    environment: 'dev',
    githubInstallationId: 12,
    repositories: ['acme-co/example-app'],
    projects: [],
    workflows: ['acme-co/example-app#image-create'],
    artifactStorage: null,
  ),
  membership: MembershipModel(
    workspaceId: 'workspace-1',
    uid: 'editor-1',
    email: 'editor@example.com',
    role: 'editor',
    roleLabel: 'Editor',
    featureClaims: {'jobs.trigger'},
    capabilities: {'jobs.read', 'jobs.trigger'},
  ),
);
