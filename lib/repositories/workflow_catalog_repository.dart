import '../models/models.dart';
import '../services/api_client.dart';
import 'workflow_template_repository.dart';

final class WorkflowCatalogIssue {
  const WorkflowCatalogIssue({required this.repository});

  final String repository;
}

final class WorkflowCatalogSnapshot {
  const WorkflowCatalogSnapshot({
    this.templates = const [],
    this.issues = const [],
  });

  final List<WorkflowTemplateModel> templates;
  final List<WorkflowCatalogIssue> issues;
}

abstract interface class WorkflowCatalogRepository {
  Future<WorkflowCatalogSnapshot> load(String workspaceId);
  Future<WorkflowCatalogSnapshot> refresh(String workspaceId);
}

final class WorkflowCatalogApiRepository implements WorkflowCatalogRepository {
  const WorkflowCatalogApiRepository(this.api);

  final ApiClient api;

  @override
  Future<WorkflowCatalogSnapshot> load(String workspaceId) async {
    final response = await api.get(
      'v1/workspaces/$workspaceId/workflow-templates',
    );
    return WorkflowCatalogSnapshot(templates: parseWorkflowTemplates(response));
  }

  @override
  Future<WorkflowCatalogSnapshot> refresh(String workspaceId) async {
    final response = await api.post(
      'v1/workspaces/$workspaceId/workflow-catalogs/refresh',
    );
    return parseWorkflowCatalogSnapshot(asJsonMap(response['data']));
  }
}

WorkflowCatalogSnapshot parseWorkflowCatalogSnapshot(JsonMap data) {
  final errors = data['errors'];
  return WorkflowCatalogSnapshot(
    templates: parseWorkflowTemplates(data),
    issues: errors is List<Object?>
        ? errors
              .whereType<Map<String, Object?>>()
              .map(
                (error) => WorkflowCatalogIssue(
                  repository: error['repository']?.toString() ?? 'Repository',
                ),
              )
              .toList(growable: false)
        : const [],
  );
}
