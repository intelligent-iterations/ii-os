@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/workflow_catalog_repository.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/widgets/workflow_catalog_editor.dart';

import 'golden_harness.dart';

void main() {
  setUpAll(loadIiOsFonts);

  testWidgets('workflow catalog makes discovery and enablement explicit', (
    tester,
  ) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Creative',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#video-create'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'owner-1',
          email: 'owner@example.com',
          role: 'owner',
          roleLabel: 'Owner',
          featureClaims: {},
          capabilities: {'workspace.manage'},
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      goldenHarness(
        WorkflowCatalogEditor(
          controller: controller,
          selected: const ['acme/media#video-create'],
          repository: const _CatalogRepository(),
          onChanged: (_) {},
        ),
        width: 720,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(WorkflowCatalogEditor),
      matchesGoldenFile('goldens/workflow_catalog_editor.png'),
    );
    await expectLater(
      find.byType(WorkflowCatalogEditor),
      matchesGoldenFile('goldens/workflow_catalog_editor_body.png'),
    );
    await expectLater(
      find.byType(WorkflowCatalogEditor),
      matchesGoldenFile('goldens/workflow_catalog_editor_content.png'),
    );
  });
}

final class _CatalogRepository implements WorkflowCatalogRepository {
  const _CatalogRepository();

  static const snapshot = WorkflowCatalogSnapshot(
    templates: [
      WorkflowTemplateModel(
        id: 'acme/media#video-create',
        workflowId: 'video-create',
        version: '1',
        displayName: 'Create video with MiniMax H3',
        model: 'minimax-h3',
        repository: 'acme/media',
        enabled: true,
        disabledReason: '',
      ),
      WorkflowTemplateModel(
        id: 'acme/media#image-create',
        workflowId: 'image-create',
        version: '2',
        displayName: 'Create images with Qwen',
        model: 'qwen-image',
        repository: 'acme/media',
        enabled: false,
        disabledReason: '',
      ),
    ],
  );

  @override
  Future<WorkflowCatalogSnapshot> load(String workspaceId) async => snapshot;

  @override
  Future<WorkflowCatalogSnapshot> refresh(String workspaceId) async => snapshot;
}
