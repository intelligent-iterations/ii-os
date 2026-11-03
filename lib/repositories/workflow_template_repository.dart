import '../models/models.dart';
import '../services/api_client.dart';

/// The single owner of `v1/workspaces/{id}/workflow-templates`.
///
/// Five screens each had their own copy of this fetch, its parse, and its
/// "which template is selected" rule, which is why the image, video, song,
/// storyboard, and image-edit surfaces drifted apart. Rule 3 in
/// `docs/ii-os-frontend.md` § Rules exists because of this endpoint.
abstract interface class WorkflowTemplateRepository {
  /// Templates for a workspace, optionally narrowed to one workflow family.
  ///
  /// [workflowIdPrefix] matches the leading segment of `workflowId`, e.g.
  /// `image-create` or `video-create`.
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  });
}

final class WorkflowTemplateApiRepository
    implements WorkflowTemplateRepository {
  const WorkflowTemplateApiRepository(this.api);

  final ApiClient api;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async {
    final response = await api.get(
      'v1/workspaces/$workspaceId/workflow-templates',
    );
    return parseWorkflowTemplates(response, workflowIdPrefix: workflowIdPrefix);
  }
}

/// Parses a `workflow-templates` response.
///
/// Split out from the request so the wire format has a test that does not need
/// a signed-in Firebase user. A malformed or missing `templates` key yields an
/// empty list rather than throwing: an operator with no workflows configured is
/// a normal state, not an error.
List<WorkflowTemplateModel> parseWorkflowTemplates(
  JsonMap response, {
  String? workflowIdPrefix,
}) {
  final raw = response['templates'];
  if (raw is! List<Object?>) return const [];
  final templates = raw.map(asJsonMap).map(WorkflowTemplateModel.fromJson);
  if (workflowIdPrefix == null) return templates.toList(growable: false);
  return templates
      .where((template) => template.workflowId.startsWith(workflowIdPrefix))
      .toList(growable: false);
}

/// The template a surface should act on, given the user's explicit choice.
///
/// Prefers the explicitly selected [selectedId], then the first enabled
/// template, then the first template at all so the UI can explain why nothing
/// is runnable. This ordering was previously reimplemented -- slightly
/// differently -- in four screens.
WorkflowTemplateModel? resolveSelectedTemplate(
  List<WorkflowTemplateModel> templates, {
  String? selectedId,
}) {
  for (final template in templates) {
    if (template.id == selectedId) return template;
  }
  for (final template in templates) {
    if (template.enabled) return template;
  }
  return templates.isEmpty ? null : templates.first;
}
