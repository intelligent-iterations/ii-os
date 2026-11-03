import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'character_prompt.dart';
import 'retention.dart';

part 'character_store_support.dart';
part 'character_store_generation.dart';
part 'character_store_source_images.dart';
part 'character_store_image_identity.dart';

String characterSelectedImageField({required bool body}) =>
    body ? 'selectedBodyImage' : 'selectedImage';

final class CharacterStore {
  CharacterStore(this.firestore);

  final Firestore firestore;
  final Uuid _uuid = const Uuid();

  Future<List<Map<String, Object?>>> listCharacters(String workspaceId) async {
    final snapshots = await firestore
        .collection('characters')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .limit(200)
        .get();
    final characters = snapshots.docs
        .map((snapshot) => _publicCharacter(snapshot.id, snapshot.data()))
        .toList();
    characters.sort(
      (left, right) =>
          (right['updatedAt'] as String).compareTo(left['updatedAt'] as String),
    );
    return characters;
  }

  Future<Map<String, Object?>> getCharacter(
    String workspaceId,
    String characterId,
  ) async {
    final snapshot = await firestore
        .collection('characters')
        .doc(characterId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId) {
      throw const ApiError(404, 'character_not_found', 'Character not found.');
    }
    return _publicCharacter(snapshot.id, data);
  }

  Future<Map<String, Object?>> createCharacter({
    required String workspaceId,
    required String createdBy,
    String name = 'Untitled character',
  }) => _createCharacter(
    workspaceId: workspaceId,
    createdBy: createdBy,
    name: name,
    creationMode: 'scratch',
    status: 'draft',
  );

  Future<Map<String, Object?>> createImageCharacter({
    required String workspaceId,
    required String createdBy,
    required String name,
    required String sourceAssetId,
    String? characterId,
  }) => _createCharacter(
    workspaceId: workspaceId,
    createdBy: createdBy,
    name: name,
    creationMode: 'image',
    status: 'ready',
    sourceAssetId: sourceAssetId,
    characterId: characterId,
  );

  Future<Map<String, Object?>> _createCharacter({
    required String workspaceId,
    required String createdBy,
    required String name,
    required String creationMode,
    required String status,
    String? sourceAssetId,
    String? characterId,
  }) async {
    characterId ??= _uuid.v4();
    final now = Timestamp.now();
    final answers = <String, String>{};
    final bodyAnswers = <String, String>{};
    final clothingAnswers = <String, String>{};
    final data = <String, Object?>{
      'workspaceId': workspaceId,
      'name': _validatedName(name),
      'creationMode': creationMode,
      'sourceAssetId': sourceAssetId,
      'answers': answers,
      'prompt': buildCharacterSheetPrompt(answers),
      'bodyAnswers': bodyAnswers,
      'clothingAnswers': clothingAnswers,
      'bodyPrompt': buildCharacterBodyPrompt(
        answers,
        bodyAnswers,
        clothingAnswers,
      ),
      'status': status,
      'thumbnailUrl': null,
      'selectedImage': null,
      'generationJobIds': <String>[],
      'lastGenerationJobId': null,
      'lastGenerationRequestedAt': null,
      'selectedBodyImage': null,
      'bodyGenerationJobIds': <String>[],
      'lastBodyGenerationJobId': null,
      'lastBodyGenerationRequestedAt': null,
      'createdBy': createdBy,
      'updatedBy': createdBy,
      'createdAt': now,
      'updatedAt': now,
    };
    await firestore.collection('characters').doc(characterId).create(data);
    return _publicCharacter(characterId, data);
  }

  Future<Map<String, Object?>> updateCharacter({
    required String workspaceId,
    required String characterId,
    required String updatedBy,
    required Map<String, Object?> changes,
  }) async {
    final ref = firestore.collection('characters').doc(characterId);
    final snapshot = await ref.get();
    final current = snapshot.data();
    if (!snapshot.exists ||
        current == null ||
        current['workspaceId'] != workspaceId) {
      throw const ApiError(404, 'character_not_found', 'Character not found.');
    }

    const allowed = {
      'name',
      'goal',
      'answers',
      'bodyAnswers',
      'clothingAnswers',
      'status',
    };
    if (changes.keys.any((key) => !allowed.contains(key))) {
      throw const ApiError(
        400,
        'invalid_character_update',
        'Only supported character fields may be updated.',
      );
    }
    final currentStatus = current['status'] as String? ?? 'draft';
    if (current['creationMode'] == 'image' &&
        changes.keys.any((key) => key != 'name')) {
      throw const ApiError(
        400,
        'invalid_image_character_update',
        'Image-based characters do not use the interview questionnaire.',
      );
    }

    final update = <String, Object?>{
      'updatedBy': updatedBy,
      'updatedAt': Timestamp.now(),
    };
    if (changes.containsKey('name')) {
      update['name'] = _validatedName(changes['name']);
    }
    if (changes.containsKey('goal')) {
      // Transitional no-op for clients opened before Goal was removed.
      _validatedText(changes['goal'], 'goal', 1000);
    }

    var answers = _answers(current['answers']);
    if (changes.containsKey('answers')) {
      answers = {
        ...answers,
        ..._validatedAnswers(
          changes['answers'],
          keys: characterAnswerKeys,
          errorCode: 'invalid_character_answers',
        ),
      };
      update['answers'] = answers;
      update['prompt'] = buildCharacterSheetPrompt(answers);
    }

    var bodyAnswers = _answers(current['bodyAnswers']);
    var clothingAnswers = _answers(current['clothingAnswers']);
    if (changes.containsKey('bodyAnswers')) {
      bodyAnswers = {
        ...bodyAnswers,
        ..._validatedAnswers(
          changes['bodyAnswers'],
          keys: characterBodyAnswerKeys,
          errorCode: 'invalid_character_body_answers',
        ),
      };
      update['bodyAnswers'] = bodyAnswers;
    }
    if (changes.containsKey('clothingAnswers')) {
      clothingAnswers = {
        ...clothingAnswers,
        ..._validatedAnswers(
          changes['clothingAnswers'],
          keys: characterClothingAnswerKeys,
          errorCode: 'invalid_character_clothing_answers',
        ),
      };
      update['clothingAnswers'] = clothingAnswers;
    }
    if (changes.containsKey('answers') ||
        changes.containsKey('bodyAnswers') ||
        changes.containsKey('clothingAnswers')) {
      update['bodyPrompt'] = buildCharacterBodyPrompt(
        answers,
        bodyAnswers,
        clothingAnswers,
      );
    }

    if (changes.containsKey('status')) {
      final status = changes['status'];
      if (status != 'ready' || currentStatus != 'draft') {
        throw const ApiError(
          400,
          'invalid_character_status',
          'A draft character can only be completed once.',
        );
      }
      final prompt = update['prompt'] ?? current['prompt'];
      if (prompt is! String || prompt.trim().isEmpty) {
        throw const ApiError(
          400,
          'character_prompt_missing',
          'The character needs a prompt before it can be completed.',
        );
      }
      update['status'] = 'ready';
    }

    await ref.update(update);
    return getCharacter(workspaceId, characterId);
  }

  Future<List<Map<String, Object?>>> listCharacterImages(
    String workspaceId,
    String characterId,
  ) async {
    return _listImages(
      workspaceId,
      characterId,
      jobIdsField: 'generationJobIds',
      lastJobIdField: 'lastGenerationJobId',
      selectedField: characterSelectedImageField(body: false),
    );
  }

  Future<List<Map<String, Object?>>> listCharacterBodyImages(
    String workspaceId,
    String characterId,
  ) async {
    return _listImages(
      workspaceId,
      characterId,
      jobIdsField: 'bodyGenerationJobIds',
      lastJobIdField: 'lastBodyGenerationJobId',
      selectedField: characterSelectedImageField(body: true),
      includeSourceImage: true,
    );
  }

  Future<List<Map<String, Object?>>> _listImages(
    String workspaceId,
    String characterId, {
    required String jobIdsField,
    required String lastJobIdField,
    required String selectedField,
    bool includeSourceImage = false,
  }) async {
    final character = await _characterData(workspaceId, characterId);
    final selected = _map(character.data[selectedField]);
    final images = <Map<String, Object?>>[];
    if (includeSourceImage && character.data['creationMode'] == 'image') {
      final sourceImage = await _sourceImageMetadata(character, selected);
      if (sourceImage != null) images.add(sourceImage);
    }
    final jobIds = _jobIds(
      character.data,
      listField: jobIdsField,
      lastField: lastJobIdField,
    );
    for (final jobId in jobIds.reversed.take(20)) {
      final snapshot = await firestore.collection('jobRuns').doc(jobId).get();
      final job = snapshot.data();
      if (!snapshot.exists ||
          job == null ||
          job['workspaceId'] != workspaceId) {
        continue;
      }
      final createdAt = _date(job['completedAt']).isNotEmpty
          ? _date(job['completedAt'])
          : _date(job['createdAt']);
      final editLabel = characterImageEditLabel(job);
      for (final artifact in _maps(job['artifacts'])) {
        final contentType = artifact['content_type'];
        final path = artifact['path'];
        final generation = artifact['generation'];
        final sizeBytes = artifact['size_bytes'];
        final sha256 = artifact['sha256'];
        if (path is! String ||
            path.isEmpty ||
            !path.startsWith('workspaces/$workspaceId/runs/$jobId/') ||
            generation is! String ||
            !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
            !_validCharacterImageIdentity(contentType, sizeBytes, sha256)) {
          continue;
        }
        images.add(
          buildCharacterImageMetadata(
            workspaceId: workspaceId,
            jobId: jobId,
            path: path,
            generation: generation,
            contentType: contentType! as String,
            sizeBytes: sizeBytes! as int,
            sha256: sha256! as String,
            createdAt: createdAt,
            editLabel: editLabel,
            selected:
                selected?['jobId'] == jobId &&
                selected?['path'] == path &&
                selected?['generation'] == generation,
          ),
        );
      }
    }
    return images;
  }

  Future<Map<String, Object?>> selectCharacterImage({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String path,
    required String generation,
    required String updatedBy,
  }) async {
    return _selectImage(
      workspaceId: workspaceId,
      characterId: characterId,
      jobId: jobId,
      path: path,
      generation: generation,
      updatedBy: updatedBy,
      body: false,
    );
  }

  Future<Map<String, Object?>> selectCharacterBodyImage({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String path,
    required String generation,
    required String updatedBy,
  }) async {
    return _selectImage(
      workspaceId: workspaceId,
      characterId: characterId,
      jobId: jobId,
      path: path,
      generation: generation,
      updatedBy: updatedBy,
      body: true,
    );
  }

  Future<Map<String, Object?>> _selectImage({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String path,
    required String generation,
    required String updatedBy,
    required bool body,
  }) async {
    final selected = await selectableCharacterImage(
      workspaceId: workspaceId,
      characterId: characterId,
      jobId: jobId,
      path: path,
      generation: generation,
      body: body,
    );
    final selectedField = characterSelectedImageField(body: body);
    await firestore.collection('characters').doc(characterId).update({
      selectedField: {
        'jobId': jobId,
        'path': path,
        'generation': generation,
        'contentType': selected['content_type'],
        'sizeBytes': selected['size_bytes'],
        'sha256': selected['sha256'],
      },
      'updatedBy': updatedBy,
      'updatedAt': Timestamp.now(),
    });
    return getCharacter(workspaceId, characterId);
  }

  Future<Map<String, Object?>> selectableCharacterImage({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String path,
    required String generation,
    required bool body,
  }) async {
    final character = await _characterData(workspaceId, characterId);
    final selectedField = characterSelectedImageField(body: body);
    Map<String, Object?>? selected;
    if (body && character.data['creationMode'] == 'image') {
      final sourceImage = await _sourceImageMetadata(
        character,
        _map(character.data[selectedField]),
      );
      if (sourceImage != null &&
          sourceImage['jobId'] == jobId &&
          sourceImage['path'] == path &&
          sourceImage['generation'] == generation) {
        selected = {
          'path': sourceImage['path'],
          'generation': sourceImage['generation'],
          'content_type': sourceImage['contentType'],
          'size_bytes': sourceImage['sizeBytes'],
          'sha256': sourceImage['sha256'],
        };
      }
    }
    final jobIds = _jobIds(
      character.data,
      listField: body ? 'bodyGenerationJobIds' : 'generationJobIds',
      lastField: body ? 'lastBodyGenerationJobId' : 'lastGenerationJobId',
    );
    if (selected == null && jobIds.contains(jobId)) {
      final snapshot = await firestore.collection('jobRuns').doc(jobId).get();
      final job = snapshot.data();
      if (snapshot.exists && job?['workspaceId'] == workspaceId) {
        for (final artifact in _maps(job?['artifacts'])) {
          final contentType = artifact['content_type'];
          if (artifact['path'] == path &&
              path.startsWith('workspaces/$workspaceId/runs/$jobId/') &&
              artifact['generation'] == generation &&
              _validCharacterImageIdentity(
                contentType,
                artifact['size_bytes'],
                artifact['sha256'],
              )) {
            selected = artifact;
            break;
          }
        }
      }
    }
    if (selected == null) {
      throw const ApiError(
        404,
        'character_image_not_found',
        'The character image was not found.',
      );
    }
    return selected;
  }

  Future<({String id, Map<String, Object?> data})> _characterData(
    String workspaceId,
    String characterId,
  ) async {
    final snapshot = await firestore
        .collection('characters')
        .doc(characterId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId) {
      throw const ApiError(404, 'character_not_found', 'Character not found.');
    }
    return (id: snapshot.id, data: data);
  }

  Future<void> deleteCharacter(String workspaceId, String characterId) async {
    final ref = firestore.collection('characters').doc(characterId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId) {
      throw const ApiError(404, 'character_not_found', 'Character not found.');
    }
    await ref.delete();
  }

  Future<Map<String, Object?>> deleteCharacterBodyImage({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String path,
  }) async {
    final character = await _characterData(workspaceId, characterId);
    final sourceAssetId = character.data['sourceAssetId'];
    if (sourceAssetId is String &&
        jobId == characterSourceImageJobId(sourceAssetId)) {
      throw const ApiError(
        400,
        'character_source_image_not_deletable',
        'The original source image cannot be deleted from sheet history.',
      );
    }
    final ids = _jobIds(
      character.data,
      listField: 'bodyGenerationJobIds',
      lastField: 'lastBodyGenerationJobId',
    ).where((id) => id != jobId).toList();
    final selectedField = characterSelectedImageField(body: true);
    final selected = _map(character.data[selectedField]);
    final deletesSelectedImage = selected?['jobId'] == jobId;
    final replacement = deletesSelectedImage
        ? await _latestImageReference(workspaceId, ids)
        : null;
    await firestore.collection('characters').doc(characterId).update({
      'bodyGenerationJobIds': ids,
      if (character.data['lastBodyGenerationJobId'] == jobId)
        'lastBodyGenerationJobId': ids.isEmpty ? null : ids.last,
      if (deletesSelectedImage) selectedField: replacement,
      'updatedAt': Timestamp.now(),
    });
    return getCharacter(workspaceId, characterId);
  }

  Future<Map<String, Object?>?> _latestImageReference(
    String workspaceId,
    Iterable<String> jobIds,
  ) async {
    for (final candidateJobId in jobIds.toList().reversed) {
      final snapshot = await firestore
          .collection('jobRuns')
          .doc(candidateJobId)
          .get();
      final job = snapshot.data();
      if (!snapshot.exists ||
          job == null ||
          job['workspaceId'] != workspaceId) {
        continue;
      }
      for (final artifact in _maps(job['artifacts'])) {
        final candidatePath = artifact['path'];
        final generation = artifact['generation'];
        final contentType = artifact['content_type'];
        final sizeBytes = artifact['size_bytes'];
        final sha256 = artifact['sha256'];
        if (candidatePath is String &&
            candidatePath.isNotEmpty &&
            candidatePath.startsWith(
              'workspaces/$workspaceId/runs/$candidateJobId/',
            ) &&
            generation is String &&
            RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) &&
            _validCharacterImageIdentity(contentType, sizeBytes, sha256)) {
          return {
            'jobId': candidateJobId,
            'path': candidatePath,
            'generation': generation,
            'contentType': contentType! as String,
            'sizeBytes': sizeBytes! as int,
            'sha256': sha256! as String,
          };
        }
      }
    }
    return null;
  }
}
