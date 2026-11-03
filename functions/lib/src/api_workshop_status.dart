part of 'api.dart';

/// Resolves a single-select Status write to its human-readable transition.
/// Non-Status fields remain on the generic Project-field path.
(String, String)? _workshopStatusTransition({
  required Map<String, Object?> project,
  required String itemId,
  required String fieldId,
  required Map<String, Object?> value,
}) {
  final fields = _apiNodes(project['fields']);
  final statusField = fields.where((field) {
    return field['__typename'] == 'ProjectV2SingleSelectField' &&
        field['name'] == 'Status';
  }).firstOrNull;
  if (statusField == null || statusField['id'] != fieldId) return null;
  if (value.keys.toSet().length != 1 ||
      value['singleSelectOptionId'] is! String) {
    throw const ApiError(
      400,
      'workshop_status_invalid',
      'Choose one available Workshop status.',
    );
  }
  final optionId = value['singleSelectOptionId'];
  final target = _apiNodes(statusField['options'])
      .where((option) => option['id'] == optionId)
      .map((option) => option['name'])
      .whereType<String>()
      .firstOrNull;
  final item = _apiNodes(
    project['items'],
  ).where((candidate) => candidate['id'] == itemId).firstOrNull;
  if (target == null || item == null) {
    throw const ApiError(
      400,
      'workshop_status_invalid',
      'Choose one available Workshop status.',
    );
  }
  var current = '';
  for (final fieldValue in _apiNodes(item['fieldValues'])) {
    final field = fieldValue['field'];
    if (field is Map<String, Object?> && field['id'] == fieldId) {
      current = fieldValue['name'] as String? ?? '';
      break;
    }
  }
  return (current, target);
}

List<Map<String, Object?>> _apiNodes(Object? connection) {
  if (connection is List<Object?>) {
    return connection.whereType<Map<String, Object?>>().toList();
  }
  final nodes = connection is Map<String, Object?> ? connection['nodes'] : null;
  return nodes is List<Object?>
      ? nodes.whereType<Map<String, Object?>>().toList()
      : const [];
}

extension _ApiFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
