import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/repositories/character_repository.dart';
import 'package:ii_os/view_models/characters_view_model.dart';

final class _FakeCharacters implements CharacterRepository {
  _FakeCharacters({this.onList, this.onCreate, this.onGenerate, this.onDelete});

  Future<List<CharacterModel>> Function()? onList;
  Future<CharacterModel> Function()? onCreate;
  Future<CharacterGeneration> Function()? onGenerate;
  Future<void> Function(String characterId)? onDelete;

  int listCalls = 0;
  int generateCalls = 0;
  String? uploadedBucket;
  Uint8List? uploadedBytes;

  @override
  Future<List<CharacterModel>> list(String workspaceId) async {
    listCalls++;
    final handler = onList;
    return handler == null ? const [] : handler();
  }

  @override
  Future<CharacterModel> create(String workspaceId) async {
    final handler = onCreate;
    if (handler == null) return _character('new');
    return handler();
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
    uploadedBucket = bucket;
    uploadedBytes = bytes;
    final handler = onCreate;
    if (handler == null) return _character('from-image', name: name);
    return handler();
  }

  @override
  Future<CharacterGeneration> generateFromImage(
    String workspaceId,
    String characterId,
  ) async {
    generateCalls++;
    final handler = onGenerate;
    if (handler == null) {
      return CharacterGeneration(
        character: _character(characterId),
        job: const {'id': 'job-1'},
      );
    }
    return handler();
  }

  @override
  Future<void> delete(String workspaceId, String characterId) async {
    await onDelete?.call(characterId);
  }
}

CharacterModel _character(String id, {String? name}) =>
    CharacterModel.fromJson({
      'id': id,
      'name': name ?? id,
      'status': 'ready',
    });

CharactersViewModel _model(CharacterRepository repository) =>
    CharactersViewModel(characters: repository, workspaceId: 'ws_test');

Future<CreateOutcome> _createFromImage(CharactersViewModel model) =>
    model.createFromImage(
      name: 'Ada',
      filename: 'ada.png',
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/png',
      bucket: 'ws-bucket',
    );

void main() {
  group('load', () {
    test('exposes the collection', () async {
      final model = _model(
        _FakeCharacters(onList: () async => [_character('c1')]),
      );

      await model.load();

      expect(model.characters.single.id, 'c1');
      expect(model.errorMessage, isNull);
      expect(model.isBusy, isFalse);
    });

    test('reports a failure instead of throwing', () async {
      final model = _model(
        _FakeCharacters(onList: () async => throw StateError('api down')),
      );

      await model.load();

      expect(model.errorMessage, contains('api down'));
      expect(model.characters, isEmpty);
    });

    test('shows the loading surface only when there is nothing to show', () async {
      final model = _model(
        _FakeCharacters(onList: () async => [_character('c1')]),
      );
      expect(model.showLoadingSurface, isFalse, reason: 'not started');

      await model.load();

      // Rule 8: a refresh must never blank a collection already on screen.
      expect(model.characters, isNotEmpty);
      expect(model.showLoadingSurface, isFalse);
    });

    test('closes a selection the collection no longer contains', () async {
      final model = _model(
        _FakeCharacters(onList: () async => [_character('c1')]),
      );
      var closed = 0;

      await model.load(
        selectedCharacterId: 'deleted-elsewhere',
        onSelectionMissing: () => closed++,
      );

      expect(closed, 1, reason: 'a stale deep link must not show nothing');
    });

    test('keeps a selection the collection does contain', () async {
      final model = _model(
        _FakeCharacters(onList: () async => [_character('c1')]),
      );
      var closed = 0;

      await model.load(
        selectedCharacterId: 'c1',
        onSelectionMissing: () => closed++,
      );

      expect(closed, 0);
      expect(model.selected('c1')?.id, 'c1');
    });
  });

  group('createScratch', () {
    test('prepends the new character and returns it', () async {
      final repository = _FakeCharacters(
        onList: () async => [_character('old')],
        onCreate: () async => _character('fresh'),
      );
      final model = _model(repository);
      await model.load();

      final outcome = await model.createScratch();

      expect(outcome.character?.id, 'fresh');
      expect(outcome.failure, isNull);
      expect(model.characters.first.id, 'fresh', reason: 'newest goes first');
      expect(model.characters.length, 2, reason: 'the old one is kept');
      expect(
        repository.listCalls,
        1,
        reason: 'creating must not refetch the collection',
      );
    });

    test('reports a failure and leaves the collection alone', () async {
      final model = _model(
        _FakeCharacters(
          onList: () async => [_character('old')],
          onCreate: () async => throw StateError('quota'),
        ),
      );
      await model.load();

      final outcome = await model.createScratch();

      expect(outcome.failure, isA<StateError>());
      expect(outcome.character, isNull);
      expect(model.characters.single.id, 'old');
      expect(model.creating, isFalse, reason: 'the flag must always clear');
    });
  });

  group('createFromImage', () {
    test('passes the bucket and bytes through to the upload', () async {
      final repository = _FakeCharacters();
      final model = _model(repository);

      await _createFromImage(model);

      expect(repository.uploadedBucket, 'ws-bucket');
      expect(repository.uploadedBytes, [1, 2, 3]);
    });

    test('starts the sheet and records the body job', () async {
      final model = _model(_FakeCharacters());

      final outcome = await _createFromImage(model);

      expect(outcome.failure, isNull);
      expect(model.bodyGenerationResult, const {'id': 'job-1'});
      expect(model.generationResult, isNull);
      expect(model.characters, hasLength(1));
    });

    test('keeps the character when only the generation fails', () async {
      // The character exists on the server either way. Dropping it would leave
      // the operator looking at a collection missing a real record.
      final model = _model(
        _FakeCharacters(onGenerate: () async => throw StateError('busy')),
      );

      final outcome = await _createFromImage(model);

      expect(outcome.failure, isA<StateError>());
      expect(outcome.character, isNotNull);
      expect(model.characters, hasLength(1));
      expect(model.bodyGenerationResult, isNull);
    });

    test('does not attempt a sheet when creation itself fails', () async {
      final repository = _FakeCharacters(
        onCreate: () async => throw StateError('rejected'),
      );
      final model = _model(repository);

      final outcome = await _createFromImage(model);

      expect(outcome.failure, isA<StateError>());
      expect(model.characters, isEmpty);
      expect(repository.generateCalls, 0);
    });
  });

  group('deleteCharacter', () {
    test('removes it from the collection', () async {
      final model = _model(
        _FakeCharacters(onList: () async => [_character('a'), _character('b')]),
      );
      await model.load();

      final failure = await model.deleteCharacter('a');

      expect(failure, isNull);
      expect(model.characters.single.id, 'b');
    });

    test('keeps it when the delete fails', () async {
      // Removing it locally would tell the operator the record is gone when the
      // server still has it, and the next refresh would bring it back.
      final model = _model(
        _FakeCharacters(
          onList: () async => [_character('a')],
          onDelete: (_) async => throw StateError('forbidden'),
        ),
      );
      await model.load();

      final failure = await model.deleteCharacter('a');

      expect(failure, isA<StateError>());
      expect(model.characters.single.id, 'a');
    });
  });

  group('in-place updates', () {
    test('replace swaps one entry without refetching', () async {
      final repository = _FakeCharacters(
        onList: () async => [_character('a'), _character('b')],
      );
      final model = _model(repository);
      await model.load();

      model.replace(_character('a', name: 'Renamed'));

      expect(model.characters.first.name, 'Renamed');
      expect(model.characters.last.name, 'b');
      expect(repository.listCalls, 1);
    });

    test('recordGeneration routes head and body jobs separately', () async {
      final model = _model(_FakeCharacters(onList: () async => [_character('a')]));
      await model.load();

      model.recordGeneration(_character('a'), const {'id': 'head'}, false);
      expect(model.generationResult, const {'id': 'head'});
      expect(model.bodyGenerationResult, isNull);

      model.recordGeneration(_character('a'), const {'id': 'body'}, true);
      expect(model.bodyGenerationResult, const {'id': 'body'});
      expect(
        model.generationResult,
        isNull,
        reason: 'a body job must not leave a stale head job behind',
      );
    });
  });
}
