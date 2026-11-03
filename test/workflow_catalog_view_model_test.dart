import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/workflow_catalog_repository.dart';
import 'package:ii_os/view_models/workflow_catalog_view_model.dart';

void main() {
  test(
    'refresh replaces templates and keeps repository issues typed',
    () async {
      final repository = _CatalogRepository(
        loaded: const WorkflowCatalogSnapshot(),
        refreshed: const WorkflowCatalogSnapshot(
          templates: [_template],
          issues: [WorkflowCatalogIssue(repository: 'acme/broken')],
        ),
      );
      final model = WorkflowCatalogViewModel(
        workspaceId: 'workspace-1',
        repository: repository,
      );

      await model.start();
      await model.refresh();

      expect(model.templates, [_template]);
      expect(model.issues.single.repository, 'acme/broken');
      expect(repository.refreshes, 1);
    },
  );

  test('load failure becomes stable product copy', () async {
    final model = WorkflowCatalogViewModel(
      workspaceId: 'workspace-1',
      repository: _CatalogRepository(loadError: StateError('secret backend')),
    );

    await model.start();

    expect(
      model.errorMessage,
      'Workflows could not be loaded. Retry discovery in a moment.',
    );
    expect(model.errorMessage, isNot(contains('secret backend')));
  });

  test(
    'refresh failure preserves the workflow choices already on screen',
    () async {
      final model = WorkflowCatalogViewModel(
        workspaceId: 'workspace-1',
        repository: _CatalogRepository(
          loaded: const WorkflowCatalogSnapshot(templates: [_template]),
          refreshError: StateError('secret backend'),
        ),
      );

      await model.start();
      await model.refresh();

      expect(model.templates, [_template]);
      expect(
        model.errorMessage,
        'Workflow discovery could not finish. Check repository access and retry.',
      );
      expect(model.errorMessage, isNot(contains('secret backend')));
    },
  );
}

const _template = WorkflowTemplateModel(
  id: 'acme/app#video-create',
  repository: 'acme/app',
  workflowId: 'video-create',
  displayName: 'Create video',
  version: '1',
  model: 'minimax',
  enabled: false,
  disabledReason: '',
);

final class _CatalogRepository implements WorkflowCatalogRepository {
  _CatalogRepository({
    this.loaded = const WorkflowCatalogSnapshot(),
    this.refreshed = const WorkflowCatalogSnapshot(),
    this.loadError,
    this.refreshError,
  });

  final WorkflowCatalogSnapshot loaded;
  final WorkflowCatalogSnapshot refreshed;
  final Object? loadError;
  final Object? refreshError;
  int refreshes = 0;

  @override
  Future<WorkflowCatalogSnapshot> load(String workspaceId) async {
    if (loadError case final error?) throw error;
    return loaded;
  }

  @override
  Future<WorkflowCatalogSnapshot> refresh(String workspaceId) async {
    refreshes += 1;
    if (refreshError case final error?) throw error;
    return refreshed;
  }
}
