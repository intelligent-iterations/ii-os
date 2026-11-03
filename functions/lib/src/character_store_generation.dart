part of 'character_store.dart';

extension CharacterGenerationStore on CharacterStore {
  Future<Map<String, Object?>> withLastBodyGenerationState(
    Map<String, Object?> character,
  ) async {
    final jobId = character['lastBodyGenerationJobId'];
    if (jobId is! String || jobId.isEmpty) return character;
    final snapshot = await firestore.collection('jobRuns').doc(jobId).get();
    final job = snapshot.data();
    if (!snapshot.exists ||
        job == null ||
        job['workspaceId'] != character['workspaceId']) {
      return character;
    }
    final workflowResult = _map(job['workflowResult']);
    return {
      ...character,
      'lastBodyGenerationStatus': job['status'],
      'lastBodyGenerationErrorCode':
          workflowResult?['errorCode'] ?? job['errorCode'],
      'lastBodyGenerationUrl': job['githubUrl'],
    };
  }

  Future<Map<String, Object?>> prepareImageCharacter({
    required String workspaceId,
    required String characterId,
    required String updatedBy,
  }) async {
    final character = await _characterData(workspaceId, characterId);
    if (character.data['creationMode'] != 'image') {
      throw const ApiError(
        409,
        'character_creation_flow_mismatch',
        'Use image generation only with an image-based character.',
      );
    }
    final sourceAssetId = character.data['sourceAssetId'];
    if (sourceAssetId is! String || sourceAssetId.isEmpty) {
      throw const ApiError(
        409,
        'character_source_missing',
        'The image-based character does not have its source image.',
      );
    }
    final status = character.data['status'];
    if (status == 'ready') return getCharacter(workspaceId, characterId);
    if (status != 'draft') {
      throw const ApiError(
        409,
        'character_not_ready',
        'The image-based character is not ready for generation.',
      );
    }
    await firestore.collection('characters').doc(characterId).update({
      'status': 'ready',
      'updatedBy': updatedBy,
      'updatedAt': Timestamp.now(),
    });
    return getCharacter(workspaceId, characterId);
  }

  Future<Map<String, Object?>> recordGenerationRequested({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String updatedBy,
  }) => _recordGenerationRequested(
    workspaceId: workspaceId,
    characterId: characterId,
    jobId: jobId,
    updatedBy: updatedBy,
    expectedMode: 'scratch',
    body: false,
  );

  Future<Map<String, Object?>> recordBodyGenerationRequested({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String updatedBy,
  }) => _recordGenerationRequested(
    workspaceId: workspaceId,
    characterId: characterId,
    jobId: jobId,
    updatedBy: updatedBy,
    expectedMode: 'scratch',
    body: true,
  );

  Future<Map<String, Object?>> recordImageGenerationRequested({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String updatedBy,
  }) => _recordGenerationRequested(
    workspaceId: workspaceId,
    characterId: characterId,
    jobId: jobId,
    updatedBy: updatedBy,
    expectedMode: 'image',
    body: true,
  );

  Future<Map<String, Object?>> recordSheetEditRequested({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String updatedBy,
  }) => _recordGenerationRequested(
    workspaceId: workspaceId,
    characterId: characterId,
    jobId: jobId,
    updatedBy: updatedBy,
    body: true,
  );

  Future<Map<String, Object?>> _recordGenerationRequested({
    required String workspaceId,
    required String characterId,
    required String jobId,
    required String updatedBy,
    required bool body,
    String? expectedMode,
  }) async {
    final ref = firestore.collection('characters').doc(characterId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          data['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'character_not_found',
          'Character not found.',
        );
      }
      if (data['status'] != 'ready') {
        throw const ApiError(
          409,
          'character_not_ready',
          'The character is not ready for generation.',
        );
      }
      if (expectedMode != null && data['creationMode'] != expectedMode) {
        throw const ApiError(
          409,
          'character_creation_flow_mismatch',
          'The generation request does not match the character creation flow.',
        );
      }
      final now = Timestamp.now();
      final listField = body ? 'bodyGenerationJobIds' : 'generationJobIds';
      final lastField = body
          ? 'lastBodyGenerationJobId'
          : 'lastGenerationJobId';
      final requestedAtField = body
          ? 'lastBodyGenerationRequestedAt'
          : 'lastGenerationRequestedAt';
      final jobIds = _jobIds(data, listField: listField, lastField: lastField);
      if (!jobIds.contains(jobId)) jobIds.add(jobId);
      transaction.update(ref, {
        listField: jobIds,
        lastField: jobId,
        requestedAtField: now,
        'updatedBy': updatedBy,
        'updatedAt': now,
      });
    });
    return getCharacter(workspaceId, characterId);
  }
}
