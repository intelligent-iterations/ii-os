import 'dart:typed_data';

import '../models/character.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/source_asset_uploader.dart';

/// A character plus the job that is producing its sheet.
///
/// The two arrive from one response and are only ever used together: the screen
/// swaps in the updated character and starts watching the job. Returning them
/// as a pair keeps the caller from re-parsing the envelope.
final class CharacterGeneration {
  const CharacterGeneration({required this.character, required this.job});

  final CharacterModel character;
  final JsonMap job;
}

/// The single owner of `v1/workspaces/{id}/characters`.
///
/// Exists as an interface so a test can count how many times a screen actually
/// fetches. That is not a cosmetic concern: the character list was being
/// refetched on every selection because the page widget was rekeyed per item,
/// and nothing in the suite could observe it.
abstract interface class CharacterRepository {
  Future<List<CharacterModel>> list(String workspaceId);

  /// Creates an empty character the operator then builds up by hand.
  Future<CharacterModel> create(String workspaceId);

  /// Uploads [bytes] as a source asset and creates a character from it.
  ///
  /// The upload is part of creation rather than a separate step a caller has to
  /// remember: a source asset with no character pointing at it is orphaned
  /// bytes in the workspace bucket.
  Future<CharacterModel> createFromImage({
    required String workspaceId,
    required String name,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String bucket,
  });

  /// Starts the sheet generation for a character created from an image.
  Future<CharacterGeneration> generateFromImage(
    String workspaceId,
    String characterId,
  );

  Future<void> delete(String workspaceId, String characterId);
}

final class CharacterApiRepository implements CharacterRepository {
  const CharacterApiRepository(this.api);

  final ApiClient api;

  String _collection(String workspaceId) =>
      'v1/workspaces/$workspaceId/characters';

  @override
  Future<List<CharacterModel>> list(String workspaceId) async {
    final response = await api.get(_collection(workspaceId));
    return parseCharacters(response);
  }

  @override
  Future<CharacterModel> create(String workspaceId) async {
    final response = await api.post(_collection(workspaceId));
    return CharacterModel.fromJson(asJsonMap(response['data']));
  }

  @override
  Future<CharacterModel> createFromImage({
    required String workspaceId,
    required String name,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String bucket,
  }) async {
    final assetId = await SourceAssetUploader(api).upload(
      workspaceId: workspaceId,
      expectedBucket: bucket,
      filename: filename,
      bytes: bytes,
      contentType: contentType,
    );
    final created = await api.post(
      '${_collection(workspaceId)}/from-image',
      body: {'name': name, 'sourceAssetId': assetId},
    );
    return CharacterModel.fromJson(asJsonMap(created['data']));
  }

  @override
  Future<CharacterGeneration> generateFromImage(
    String workspaceId,
    String characterId,
  ) async {
    final response = await api.post(
      '${_collection(workspaceId)}/$characterId/generate-from-image',
    );
    final data = asJsonMap(response['data']);
    return CharacterGeneration(
      character: CharacterModel.fromJson(asJsonMap(data['character'])),
      job: asJsonMap(data['job']),
    );
  }

  @override
  Future<void> delete(String workspaceId, String characterId) =>
      api.delete('${_collection(workspaceId)}/$characterId');
}

/// Parses a character-collection response.
///
/// Split from the request so the wire format is testable without a signed-in
/// Firebase user.
List<CharacterModel> parseCharacters(JsonMap response) {
  // Type-checked rather than cast: the previous `as List<Object?>?` threw a
  // TypeError on a malformed payload, which surfaced as an unexplained red
  // screen instead of an empty collection.
  final raw = response['characters'];
  if (raw is! List<Object?>) return const [];
  return raw
      .map(asJsonMap)
      .map(CharacterModel.fromJson)
      .toList(growable: false);
}
