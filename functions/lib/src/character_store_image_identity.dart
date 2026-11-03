part of 'character_store.dart';

extension CharacterImageIdentityStore on CharacterStore {
  Future<Map<String, Object?>?> resolveCharacterImageReference(
    String workspaceId,
    Object? value,
  ) async {
    final reference = _map(value);
    final jobId = reference?['jobId'];
    final path = reference?['path'];
    final generation = reference?['generation'];
    if (jobId is! String ||
        jobId.isEmpty ||
        path is! String ||
        path.isEmpty ||
        generation is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation)) {
      return null;
    }
    if (jobId.startsWith('source-asset:')) {
      return _resolveCharacterSourceImage(
        workspaceId: workspaceId,
        jobId: jobId,
        path: path,
        generation: generation,
      );
    }
    final snapshot = await firestore.collection('jobRuns').doc(jobId).get();
    final job = snapshot.data();
    if (!snapshot.exists ||
        job == null ||
        job['workspaceId'] != workspaceId ||
        !path.startsWith('workspaces/$workspaceId/runs/$jobId/')) {
      return null;
    }
    for (final artifact in _maps(job['artifacts'])) {
      if (artifact['path'] != path || artifact['generation'] != generation) {
        continue;
      }
      final contentType = artifact['content_type'];
      final sizeBytes = artifact['size_bytes'];
      final sha256 = artifact['sha256'];
      if (!_validCharacterImageIdentity(contentType, sizeBytes, sha256)) {
        return null;
      }
      return buildCharacterImageMetadata(
        workspaceId: workspaceId,
        jobId: jobId,
        path: path,
        generation: generation,
        contentType: contentType! as String,
        sizeBytes: sizeBytes! as int,
        sha256: sha256! as String,
        createdAt: _date(job['completedAt']).isNotEmpty
            ? _date(job['completedAt'])
            : _date(job['createdAt']),
        selected: true,
        editLabel: characterImageEditLabel(job),
      );
    }
    return null;
  }

  Future<Map<String, Object?>?> _resolveCharacterSourceImage({
    required String workspaceId,
    required String jobId,
    required String path,
    required String generation,
  }) async {
    final sourceAssetId = jobId.substring('source-asset:'.length);
    if (sourceAssetId.isEmpty) return null;
    final snapshot = await firestore
        .collection('sourceAssets')
        .doc(sourceAssetId)
        .get();
    final source = snapshot.data();
    final contentType = source?['contentType'];
    final sizeBytes = source?['sizeBytes'];
    final sha256 = source?['sha256'];
    if (!snapshot.exists ||
        source == null ||
        source['workspaceId'] != workspaceId ||
        source['status'] != 'ready' ||
        recordRetentionExpired(source) ||
        source['path'] != path ||
        !path.startsWith('workspaces/$workspaceId/') ||
        source['generation'] != generation ||
        !_validCharacterImageIdentity(contentType, sizeBytes, sha256)) {
      return null;
    }
    return buildCharacterSourceImageMetadata(
      workspaceId: workspaceId,
      sourceAssetId: sourceAssetId,
      path: path,
      generation: generation,
      contentType: contentType! as String,
      sizeBytes: sizeBytes! as int,
      sha256: sha256! as String,
      createdAt: _date(source['createdAt']),
      selected: true,
    );
  }
}

bool _validCharacterImageIdentity(
  Object? contentType,
  Object? sizeBytes,
  Object? sha256,
) =>
    contentType is String &&
    const {'image/jpeg', 'image/png', 'image/webp'}.contains(contentType) &&
    sizeBytes is int &&
    sizeBytes > 0 &&
    sha256 is String &&
    RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256);

Map<String, Object?> buildCharacterImageMetadata({
  required String workspaceId,
  required String jobId,
  required String path,
  required String generation,
  required String contentType,
  required int sizeBytes,
  required String sha256,
  required String createdAt,
  required bool selected,
  bool sourceImage = false,
  String? editLabel,
}) => {
  'workspaceId': workspaceId,
  'jobId': jobId,
  'path': path,
  'generation': generation,
  'contentType': contentType,
  'sizeBytes': sizeBytes,
  'sha256': sha256,
  'createdAt': createdAt,
  'selected': selected,
  if (sourceImage) 'sourceImage': true,
  'editLabel': ?editLabel,
};

String? characterImageEditLabel(Map<String, Object?> job) {
  final review = _map(job['generationReview']);
  if (review?['kind'] != 'character_sheet_edit') return null;
  final prefix = review?['mode'] == 'area' ? 'Area edit' : 'Sheet tweak';
  final inputs = _map(job['inputs']);
  final prompt = (inputs?['prompt'] as String? ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (prompt.isEmpty) return prefix;
  final withoutPeriod = prompt.endsWith('.')
      ? prompt.substring(0, prompt.length - 1)
      : prompt;
  var detail = withoutPeriod;
  if (detail.length > 36) {
    final clipped = detail.substring(0, 35).trimRight();
    final lastSpace = clipped.lastIndexOf(' ');
    detail =
        '${lastSpace >= 24 ? clipped.substring(0, lastSpace) : clipped}\u2026';
  }
  return '$prefix: $detail';
}
