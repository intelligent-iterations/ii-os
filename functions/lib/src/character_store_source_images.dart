part of 'character_store.dart';

extension CharacterSourceImageStore on CharacterStore {
  Future<Map<String, Object?>?> _sourceImageMetadata(
    ({String id, Map<String, Object?> data}) character,
    Map<String, Object?>? selected,
  ) async {
    final sourceAssetId = character.data['sourceAssetId'];
    if (sourceAssetId is! String || sourceAssetId.isEmpty) return null;
    final snapshot = await firestore
        .collection('sourceAssets')
        .doc(sourceAssetId)
        .get();
    final source = snapshot.data();
    if (!snapshot.exists ||
        source == null ||
        source['workspaceId'] != character.data['workspaceId'] ||
        source['status'] != 'ready' ||
        recordRetentionExpired(source)) {
      return null;
    }
    final path = source['path'];
    final generation = source['generation'];
    final contentType = source['contentType'];
    final sizeBytes = source['sizeBytes'];
    final sha256 = source['sha256'];
    if (path is! String ||
        path.isEmpty ||
        !path.startsWith('workspaces/${character.data['workspaceId']}/') ||
        generation is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
        !_validCharacterImageIdentity(contentType, sizeBytes, sha256)) {
      return null;
    }
    final metadata = buildCharacterSourceImageMetadata(
      workspaceId: character.data['workspaceId']! as String,
      sourceAssetId: sourceAssetId,
      path: path,
      generation: generation,
      contentType: contentType! as String,
      sizeBytes: sizeBytes! as int,
      sha256: sha256! as String,
      createdAt: _date(source['createdAt']),
      selected: false,
    );
    return {
      ...metadata,
      'selected': _sameCharacterImageReference(selected, metadata),
    };
  }
}

Map<String, Object?> buildCharacterSourceImageMetadata({
  required String workspaceId,
  required String sourceAssetId,
  required String path,
  required String generation,
  required String contentType,
  required int sizeBytes,
  required String sha256,
  required String createdAt,
  required bool selected,
}) => buildCharacterImageMetadata(
  workspaceId: workspaceId,
  jobId: characterSourceImageJobId(sourceAssetId),
  path: path,
  generation: generation,
  contentType: contentType,
  sizeBytes: sizeBytes,
  sha256: sha256,
  createdAt: createdAt,
  selected: selected,
  sourceImage: true,
);

String characterSourceImageJobId(String sourceAssetId) =>
    'source-asset:$sourceAssetId';

bool _sameCharacterImageReference(
  Map<String, Object?>? selected,
  Map<String, Object?> image,
) =>
    selected?['jobId'] == image['jobId'] &&
    selected?['path'] == image['path'] &&
    selected?['generation'] == image['generation'];
