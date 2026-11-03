part of 'job_run_store.dart';

Map<String, Object?> _publicJob(Map<String, Object?> data) {
  final safe = _jsonSafe(data);
  safe['workType'] ??= legacyJobWorkType(data);
  safe.remove('fleetRequest');
  safe.remove('claimOwner');
  safe.remove('claimExpiresAt');
  safe.remove('bridgeError');
  safe.remove('generationSelection');
  safe.remove('retentionAttachment');
  if (data['ghostMode'] == true) {
    const visible = {
      'workspaceId',
      'jobId',
      'ghostMode',
      'workType',
      'status',
      'githubStatus',
      'githubConclusion',
      'errorCode',
      'events',
      'artifacts',
      'createdAt',
      'submittedAt',
      'updatedAt',
      'completedAt',
      'consumedAt',
      'expiresAt',
    };
    safe.removeWhere((key, _) => !visible.contains(key));
  }
  return safe;
}

/// Read-time compatibility for job records created before work types existed.
String legacyJobWorkType(Map<String, Object?> data) {
  final kind = data['kind']?.toString().toLowerCase() ?? '';
  if (kind.startsWith('mobile-update-')) return 'runtime';
  final artifacts = data['artifacts'];
  if (artifacts is List<Object?>) {
    for (final artifact in artifacts.whereType<Map<String, Object?>>()) {
      final contentType = artifact['content_type']?.toString() ?? '';
      if (contentType.startsWith('image/') ||
          contentType.startsWith('video/') ||
          contentType.startsWith('audio/')) {
        return 'content';
      }
    }
  }
  const contentKinds = {
    'image',
    'video',
    'audio',
    'song',
    'narration',
    'character',
    'storyboard',
  };
  if (contentKinds.any(kind.contains)) return 'content';
  return 'other';
}

Map<String, Object?> _jsonSafe(Map<String, Object?> data) =>
    data.map((key, value) => MapEntry(key, _jsonSafeValue(value)));

Object? _jsonSafeValue(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  if (value is List<Object?>) return value.map(_jsonSafeValue).toList();
  if (value is Map<String, Object?>) return _jsonSafe(value);
  return value;
}
