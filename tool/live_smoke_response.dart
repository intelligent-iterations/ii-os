Map<String, Object?> liveSmokeAuditedObject(
  Map<String, Object?> response,
  String key,
) {
  final data = response['data'];
  if (data is! Map) {
    throw StateError('Expected an audited API data object');
  }
  final value = data[key];
  if (value is! Map) {
    throw StateError('Expected audited API data.$key to be an object');
  }
  return value.cast<String, Object?>();
}
