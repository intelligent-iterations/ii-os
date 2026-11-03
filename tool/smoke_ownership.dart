bool smokeOwnsWorkspaceDocument(
  Map<String, Object?> document, {
  required String runId,
  required Set<String> createdUserIds,
}) {
  final fields = _map(document['fields']);
  return _string(fields['smokeRunId']) == runId &&
      _boolean(fields['disposable']) == true &&
      createdUserIds.contains(_string(fields['createdBy']));
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

String _string(Object? value) => _map(value)['stringValue'] as String? ?? '';

bool? _boolean(Object? value) => _map(value)['booleanValue'] as bool?;
