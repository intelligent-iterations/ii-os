part of 'workspace_store.dart';

Map<String, Object?>? _validatedConnection(
  Object? value, {
  required bool emulated,
}) {
  if (value == null) return null;
  if (value is! Map<String, Object?>) {
    throw const ApiError(
      400,
      'invalid_workspace_connection',
      'Workspace connection must be a nonsecret persisted GCP record.',
    );
  }
  final connection = DataPlaneConnection.fromJson(value, emulated: emulated);
  if (connection.configurationChecks().any((check) => !check.passed)) {
    throw const ApiError(
      400,
      'invalid_workspace_connection',
      'Workspace connection contains missing or invalid resource identifiers.',
    );
  }
  return connection.toJson();
}

List<String> validatedWorkspaceStrings(Object? value, String field) {
  if (value is! List<Object?> || value.length > 100) {
    throw ApiError(400, 'invalid_$field', '$field must be a bounded list.');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty || item.length > 300) {
      throw ApiError(
        400,
        'invalid_$field',
        '$field contains an invalid value.',
      );
    }
    result.add(item.trim());
  }
  return result.toSet().toList()..sort();
}

List<Map<String, Object?>> _validatedProjects(Object? value) {
  if (value is! List<Object?> || value.length > 50) {
    throw const ApiError(
      400,
      'invalid_projects',
      'projects must be a bounded list.',
    );
  }
  final result = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map<String, Object?>) {
      throw const ApiError(
        400,
        'invalid_projects',
        'A project entry is invalid.',
      );
    }
    final project = GitHubProjectConfig.fromJson(item);
    if (project.id.isEmpty || project.owner.isEmpty || project.number <= 0) {
      throw const ApiError(
        400,
        'invalid_projects',
        'Project ID, owner, and number are required.',
      );
    }
    result.add(project.toJson());
  }
  return result;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
