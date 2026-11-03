import 'api_error.dart';
import 'source_asset_service.dart';

final class CharacterReferenceImage {
  const CharacterReferenceImage({
    required this.characterId,
    required this.name,
    required this.path,
    required this.generation,
    required this.contentType,
  });

  final String characterId;
  final String name;
  final String path;
  final String generation;
  final String contentType;
}

final class CharacterReferenceAsset {
  const CharacterReferenceAsset({
    required this.assetId,
    required this.characterId,
    required this.name,
  });

  final String assetId;
  final String characterId;
  final String name;
}

List<CharacterReferenceImage> selectedCharacterReferenceImages(
  List<Map<String, Object?>> characters,
) {
  final references = <CharacterReferenceImage>[];
  for (final character in characters) {
    final characterId = character['id']?.toString().trim() ?? '';
    final name = character['name']?.toString().trim() ?? '';
    final raw = character['selectedBodyImage'];
    if (raw is! Map) continue;
    final value = raw.cast<Object?, Object?>();
    final path = value['path'];
    final generation = value['generation'];
    final contentType = value['contentType'] ?? value['content_type'];
    if (path is String &&
        path.isNotEmpty &&
        generation is String &&
        generation.isNotEmpty &&
        contentType is String &&
        const {'image/jpeg', 'image/png', 'image/webp'}.contains(contentType)) {
      references.add(
        CharacterReferenceImage(
          characterId: characterId,
          name: name.isEmpty ? 'Untitled character' : name,
          path: path,
          generation: generation,
          contentType: contentType,
        ),
      );
    }
  }
  return references;
}

String characterReferenceFilename(String name) {
  final normalized = name.trim();
  return '${normalized.isEmpty ? 'Untitled character' : normalized}.png';
}

final class CharacterReferenceSheetComposer {
  const CharacterReferenceSheetComposer({required this.sourceAssets});

  final SourceAssetService sourceAssets;

  Future<List<CharacterReferenceAsset>> createMany({
    required String workspaceId,
    required String actorUid,
    required List<Map<String, Object?>> characters,
    required int retentionDays,
  }) async {
    final references = selectedCharacterReferenceImages(characters);
    if (references.isEmpty) return const [];
    final assets = <CharacterReferenceAsset>[];
    for (final reference in references) {
      final asset = await sourceAssets.registerWorkspaceObject(
        workspaceId: workspaceId,
        actorUid: actorUid,
        objectName: reference.path,
        generation: reference.generation,
        filename: characterReferenceFilename(reference.name),
        contentType: reference.contentType,
        retentionDays: retentionDays,
      );
      final id = asset['assetId'];
      if (id is String && id.isNotEmpty) {
        assets.add(
          CharacterReferenceAsset(
            assetId: id,
            characterId: reference.characterId,
            name: reference.name,
          ),
        );
      }
    }
    return assets;
  }

  Future<String?> create({
    required String workspaceId,
    required String actorUid,
    required List<Map<String, Object?>> characters,
    required int retentionDays,
  }) async {
    final references = selectedCharacterReferenceImages(characters);
    if (references.isEmpty) return null;
    if (references.length != 1) {
      throw const ApiError(
        409,
        'client_reference_composition_required',
        'Multiple character references must be composed on the client.',
      );
    }
    final reference = references.single;
    final asset = await sourceAssets.registerWorkspaceObject(
      workspaceId: workspaceId,
      actorUid: actorUid,
      objectName: reference.path,
      generation: reference.generation,
      filename: characterReferenceFilename(reference.name),
      contentType: reference.contentType,
      retentionDays: retentionDays,
    );
    return asset['assetId'] as String?;
  }
}
