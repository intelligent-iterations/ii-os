import 'api_error.dart';
import 'domain.dart';

/// Narrows an existing workspace grant before resolving provider credentials.
String? selectedWorkspaceRepository(Workspace workspace, Object? selected) {
  if (selected == null) return null;
  if (selected is! String || !workspace.containsRepository(selected)) {
    throw const ApiError(
      400,
      'repository_not_allowed',
      'Select a repository connected to this workspace.',
    );
  }
  return selected;
}

void requireSelectedProjectItemRepository({
  required Map<String, Object?> project,
  required String projectId,
  required String itemId,
  required String? repository,
}) {
  if (repository == null) return;
  final items = project['items'];
  final nodes = items is Map<String, Object?> ? items['nodes'] : null;
  final item = nodes is List
      ? nodes
            .whereType<Map<String, Object?>>()
            .where((item) => item['id'] == itemId)
            .firstOrNull
      : null;
  final content = item?['content'];
  final actual = content is Map<String, Object?> ? content['repository'] : null;
  if (project['id'] != projectId ||
      actual is! Map<String, Object?> ||
      actual['nameWithOwner'] != repository) {
    throw const ApiError(
      409,
      'agent_ticket_repository_mismatch',
      'The Project ticket does not belong to the selected repository.',
    );
  }
}
