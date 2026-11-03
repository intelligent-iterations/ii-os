import 'package:flutter/foundation.dart';
import 'package:stacked/stacked.dart';

import '../models/character.dart';
import '../models/models.dart';
import '../repositories/character_repository.dart';

/// The result of a create.
///
/// Both fields can be set at once: a character created from an image exists on
/// the server even when starting its sheet fails, so the caller both selects it
/// and reports the failure.
final class CreateOutcome {
  const CreateOutcome({this.character, this.failure});

  final CharacterModel? character;
  final Object? failure;
}

/// State for the characters collection.
///
/// Owns the list, the in-flight create, and the generation jobs that used to
/// live in `_CharactersScreenState`. Mutations report through a return value
/// rather than the page error surface: when a delete fails the collection on
/// screen is still correct, and blanking it would throw away good content to
/// report a failed action.
final class CharactersViewModel extends BaseViewModel {
  CharactersViewModel({required this._characters, required this.workspaceId});

  final CharacterRepository _characters;
  final String workspaceId;

  List<CharacterModel> characters = const [];

  /// The head-sheet job to hand to the detail screen, if one just started.
  JsonMap? generationResult;

  /// The body-sheet job to hand to the detail screen, if one just started.
  JsonMap? bodyGenerationResult;

  bool creating = false;
  String? errorMessage;

  /// True only on the first load, when there is genuinely nothing to show. A
  /// refresh must not blank a collection the operator is already reading.
  bool get showLoadingSurface => isBusy && characters.isEmpty;

  CharacterModel? selected(String? characterId) {
    if (characterId == null) return null;
    for (final character in characters) {
      if (character.id == characterId) return character;
    }
    return null;
  }

  /// [onSelectionMissing] fires when the route points at a character the
  /// collection does not contain -- a stale deep link, or a character deleted in
  /// another tab. The page closes the detail view rather than showing nothing.
  Future<void> load({
    String? selectedCharacterId,
    VoidCallback? onSelectionMissing,
  }) async {
    setBusy(true);
    try {
      characters = await _characters.list(workspaceId);
      errorMessage = null;
      if (selectedCharacterId != null &&
          !characters.any((each) => each.id == selectedCharacterId)) {
        onSelectionMissing?.call();
      }
    } on Object catch (error) {
      errorMessage = error.toString();
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  /// Creates an empty character the operator then builds up by hand.
  Future<CreateOutcome> createScratch() {
    return _whileCreating(() async {
      final character = await _characters.create(workspaceId);
      _prepend(character);
      return CreateOutcome(character: character);
    });
  }

  /// Creates a character from an uploaded image and starts its sheet.
  ///
  /// A generation failure is reported but the character is still kept: it
  /// exists on the server either way, and dropping it from the list would leave
  /// the operator looking at a collection that is missing a real record.
  Future<CreateOutcome> createFromImage({
    required String name,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String bucket,
  }) {
    return _whileCreating(() async {
      var character = await _characters.createFromImage(
        workspaceId: workspaceId,
        name: name,
        filename: filename,
        bytes: bytes,
        contentType: contentType,
        bucket: bucket,
      );
      Object? generationFailure;
      JsonMap? job;
      try {
        final generation = await _characters.generateFromImage(
          workspaceId,
          character.id,
        );
        character = generation.character;
        job = generation.job;
      } on Object catch (error) {
        generationFailure = error;
      }
      _prepend(character, bodyJob: job);
      return CreateOutcome(character: character, failure: generationFailure);
    });
  }

  Future<Object?> deleteCharacter(String characterId) async {
    try {
      await _characters.delete(workspaceId, characterId);
      remove(characterId);
      return null;
    } on Object catch (error) {
      return error;
    }
  }

  /// Swaps in an updated character without refetching the collection.
  void replace(CharacterModel character) {
    characters = [
      for (final each in characters)
        if (each.id == character.id) character else each,
    ];
    notifyListeners();
  }

  /// Records a sheet job started from the detail screen.
  void recordGeneration(CharacterModel character, JsonMap job, bool isBody) {
    characters = [
      for (final each in characters)
        if (each.id == character.id) character else each,
    ];
    generationResult = isBody ? null : job;
    bodyGenerationResult = isBody ? job : null;
    notifyListeners();
  }

  void remove(String characterId) {
    characters = characters
        .where((character) => character.id != characterId)
        .toList(growable: false);
    clearGenerations();
  }

  void clearGenerations() {
    generationResult = null;
    bodyGenerationResult = null;
    notifyListeners();
  }

  Future<CreateOutcome> _whileCreating(
    Future<CreateOutcome> Function() action,
  ) async {
    creating = true;
    notifyListeners();
    try {
      return await action();
    } on Object catch (error) {
      return CreateOutcome(failure: error);
    } finally {
      creating = false;
      notifyListeners();
    }
  }

  void _prepend(CharacterModel character, {JsonMap? bodyJob}) {
    characters = [character, ...characters];
    generationResult = null;
    bodyGenerationResult = bodyJob;
  }
}
