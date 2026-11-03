part of 'api.dart';

extension _CharacterRoutes on IiOsApi {
  Future<Response> _characterRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length == 4 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.charactersRead);
      final listed = await characters.listCharacters(workspaceId);
      return jsonResponse(200, {
        'characters': await Future.wait(listed.map(_withCharacterThumbnail)),
      }, requestId: requestId);
    }
    if (path.length == 4 && request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
      final body = await readJsonObject(request);
      final name = body['name'];
      final creationMode = body['creationMode'];
      if (name != null && name is! String) {
        throw const ApiError(
          400,
          'invalid_character',
          'Character name must be text.',
        );
      }
      if (creationMode != null && creationMode != 'scratch') {
        throw const ApiError(
          400,
          'character_creation_flow_mismatch',
          'Create image-based characters through the from-image flow.',
        );
      }
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'character.create',
        targetType: 'character',
        execute: () async => _withCharacterThumbnail(
          await characters.createCharacter(
            workspaceId: workspaceId,
            createdBy: actor.uid,
            name: name as String? ?? 'Untitled character',
          ),
        ),
      );
    }
    if (path.length == 5 &&
        path[4] == 'from-image' &&
        request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
      final body = await readJsonObject(request);
      final name = requiredString(body, 'name', maxLength: 100);
      final sourceAssetId = requiredString(
        body,
        'sourceAssetId',
        maxLength: 64,
      );
      await workflowApi.sourceAssets.workflowReadContract(
        workspaceId: workspaceId,
        assetId: sourceAssetId,
      );
      final workspace = await store.getWorkspace(workspaceId);
      final characterId = _uuid.v4();
      final attachment = 'character/$characterId/source';
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'character.image.create',
        targetType: 'character',
        metadata: {'sourceAssetId': sourceAssetId},
        execute: () async {
          await assetRetention.protectRecord(
            workspaceId: workspaceId,
            collection: 'sourceAssets',
            recordId: sourceAssetId,
            attachment: attachment,
          );
          late Map<String, Object?> created;
          try {
            created = await characters.createImageCharacter(
              workspaceId: workspaceId,
              createdBy: actor.uid,
              name: name,
              sourceAssetId: sourceAssetId,
              characterId: characterId,
            );
          } catch (_) {
            await assetRetention.releaseRecordAttachments(
              workspaceId: workspaceId,
              collection: 'sourceAssets',
              recordId: sourceAssetId,
              attachments: {attachment},
              retentionDays: artifactRetentionDays(
                workspace.artifactStorage?.retentionDays,
              ),
            );
            rethrow;
          }
          return _withCharacterThumbnail(created);
        },
      );
    }
    if (path.length == 5 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.charactersRead);
      return jsonResponse(200, {
        'character': await _withCharacterThumbnail(
          await characters.getCharacter(workspaceId, path[4]),
        ),
      }, requestId: requestId);
    }
    if (path.length == 5 && request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'character.update',
        targetType: 'character',
        targetId: path[4],
        execute: () async => _withCharacterThumbnail(
          await characters.updateCharacter(
            workspaceId: workspaceId,
            characterId: path[4],
            updatedBy: actor.uid,
            changes: body,
          ),
        ),
      );
    }
    if (path.length == 6 && path[5] == 'images' && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.charactersRead);
      final images = await characters.listCharacterImages(workspaceId, path[4]);
      return jsonResponse(200, {
        'images': await Future.wait(images.map(_withCharacterImageGrant)),
      }, requestId: requestId);
    }
    if (path.length == 6 &&
        path[5] == 'body-images' &&
        request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.charactersRead);
      final images = await characters.listCharacterBodyImages(
        workspaceId,
        path[4],
      );
      return jsonResponse(200, {
        'images': await Future.wait(images.map(_withCharacterImageGrant)),
      }, requestId: requestId);
    }
    if (path.length == 6 &&
        path[5] == 'body-images' &&
        request.method == 'DELETE') {
      await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
      final body = await readJsonObject(request);
      final jobId = requiredString(body, 'jobId', maxLength: 200);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'character.body_image.delete',
        targetType: 'character',
        targetId: path[4],
        execute: () async {
          final before = await characters.getCharacter(workspaceId, path[4]);
          final updated = await characters.deleteCharacterBodyImage(
            workspaceId: workspaceId,
            characterId: path[4],
            jobId: jobId,
            path: requiredString(body, 'path', maxLength: 900),
          );
          final workspace = await store.getWorkspace(workspaceId);
          await assetRetention.releaseRemovedGraph(
            workspaceId: workspaceId,
            before: characterAssetAttachmentGraph(before),
            after: characterAssetAttachmentGraph(updated),
            retentionDays: artifactRetentionDays(
              workspace.artifactStorage?.retentionDays,
            ),
          );
          return _withCharacterThumbnail(updated);
        },
      );
    }
    if (path.length == 6 &&
        path[5] == 'selected-image' &&
        request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
      final body = await readJsonObject(request);
      final jobId = requiredString(body, 'jobId', maxLength: 200);
      final imagePath = requiredString(body, 'path', maxLength: 900);
      final generation = requiredString(body, 'generation', maxLength: 30);
      final workspace = await store.getWorkspace(workspaceId);
      final attachment = 'character/${path[4]}/head';
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'character.image.select',
        targetType: 'character',
        targetId: path[4],
        execute: () async {
          await characters.selectableCharacterImage(
            workspaceId: workspaceId,
            characterId: path[4],
            jobId: jobId,
            path: imagePath,
            generation: generation,
            body: false,
          );
          final acquired = await assetRetention.protectRecord(
            workspaceId: workspaceId,
            collection: 'jobRuns',
            recordId: jobId,
            attachment: attachment,
          );
          late Map<String, Object?> updated;
          try {
            updated = await characters.selectCharacterImage(
              workspaceId: workspaceId,
              characterId: path[4],
              jobId: jobId,
              path: imagePath,
              generation: generation,
              updatedBy: actor.uid,
            );
          } catch (_) {
            if (acquired) {
              await assetRetention.releaseRecordAttachments(
                workspaceId: workspaceId,
                collection: 'jobRuns',
                recordId: jobId,
                attachments: {attachment},
                retentionDays: artifactRetentionDays(
                  workspace.artifactStorage?.retentionDays,
                ),
              );
            }
            rethrow;
          }
          return _withCharacterThumbnail(updated);
        },
      );
    }
    if (path.length == 6 &&
        path[5] == 'selected-body-image' &&
        request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
      final body = await readJsonObject(request);
      final jobId = requiredString(body, 'jobId', maxLength: 200);
      final imagePath = requiredString(body, 'path', maxLength: 900);
      final generation = requiredString(body, 'generation', maxLength: 30);
      final workspace = await store.getWorkspace(workspaceId);
      final attachment = 'character/${path[4]}/body';
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'character.body_image.select',
        targetType: 'character',
        targetId: path[4],
        execute: () async {
          await characters.selectableCharacterImage(
            workspaceId: workspaceId,
            characterId: path[4],
            jobId: jobId,
            path: imagePath,
            generation: generation,
            body: true,
          );
          var acquired = false;
          if (!jobId.startsWith('source-asset:')) {
            acquired = await assetRetention.protectRecord(
              workspaceId: workspaceId,
              collection: 'jobRuns',
              recordId: jobId,
              attachment: attachment,
            );
          }
          late Map<String, Object?> updated;
          try {
            updated = await characters.selectCharacterBodyImage(
              workspaceId: workspaceId,
              characterId: path[4],
              jobId: jobId,
              path: imagePath,
              generation: generation,
              updatedBy: actor.uid,
            );
          } catch (_) {
            if (acquired) {
              await assetRetention.releaseRecordAttachments(
                workspaceId: workspaceId,
                collection: 'jobRuns',
                recordId: jobId,
                attachments: {attachment},
                retentionDays: artifactRetentionDays(
                  workspace.artifactStorage?.retentionDays,
                ),
              );
            }
            rethrow;
          }
          return _withCharacterThumbnail(updated);
        },
      );
    }
    if (path.length == 6 &&
        path[5] == 'selected-image-source' &&
        request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.charactersRead);
      final workspace = await store.getWorkspace(workspaceId);
      final character = await characters.getCharacter(workspaceId, path[4]);
      final assetId =
          await CharacterReferenceSheetComposer(
            sourceAssets: workflowApi.sourceAssets,
          ).create(
            workspaceId: workspaceId,
            actorUid: actor.uid,
            characters: [character],
            retentionDays: artifactRetentionDays(
              workspace.artifactStorage?.retentionDays,
            ),
          );
      if (assetId == null) {
        throw const ApiError(
          409,
          'character_reference_missing',
          'Select a character sheet before editing it.',
        );
      }
      return jsonResponse(200, {'assetId': assetId}, requestId: requestId);
    }
    final generated = await _characterGenerationRoute(
      request,
      requestId,
      actor,
      workspaceId,
      path,
    );
    if (generated != null) return generated;
    if (path.length == 5 && request.method == 'DELETE') {
      await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'character.delete',
        targetType: 'character',
        targetId: path[4],
        execute: () async {
          final character = await characters.getCharacter(workspaceId, path[4]);
          await characters.deleteCharacter(workspaceId, path[4]);
          final workspace = await store.getWorkspace(workspaceId);
          await assetRetention.releaseRemovedGraph(
            workspaceId: workspaceId,
            before: characterAssetAttachmentGraph(character),
            after: const {},
            retentionDays: artifactRetentionDays(
              workspace.artifactStorage?.retentionDays,
            ),
          );
          return {'id': path[4], 'deleted': true};
        },
      );
    }
    throw const ApiError(404, 'not_found', 'Character route not found.');
  }

  Future<Map<String, Object?>> _withCharacterThumbnail(
    Map<String, Object?> character,
  ) async {
    character = await characters.withLastBodyGenerationState(character);
    final selected = _characterMap(character['selectedImage']);
    if (selected == null) return character;
    final workspaceId = character['workspaceId'];
    if (workspaceId is! String) {
      return character;
    }
    final image = await characters.resolveCharacterImageReference(
      workspaceId,
      selected,
    );
    if (image == null) {
      return {
        ...character,
        'thumbnailUrl': null,
        'thumbnailImage': null,
        'thumbnailError': {
          'code': 'character_image_metadata_invalid',
          'message': 'The selected sheet metadata is unavailable.',
        },
      };
    }
    final granted = await _withCharacterImageGrant(image);
    final error = granted['readGrantError'];
    return {
      ...character,
      'thumbnailUrl': null,
      'thumbnailImage': granted,
      'thumbnailError': ?error,
    };
  }

  Future<Map<String, Object?>> _withCharacterImageGrant(
    Map<String, Object?> image,
  ) async {
    final workspaceId = image['workspaceId'];
    final jobId = image['jobId'];
    final path = image['path'];
    final generation = image['generation'];
    final sizeBytes = image['sizeBytes'];
    final sha256 = image['sha256'];
    final contentType = image['contentType'];
    final pathMatchesIdentity =
        workspaceId is String &&
        jobId is String &&
        path is String &&
        (jobId.startsWith('source-asset:')
            ? path.startsWith('workspaces/$workspaceId/')
            : path.startsWith('workspaces/$workspaceId/runs/$jobId/'));
    if (!pathMatchesIdentity ||
        generation is! String ||
        !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation) ||
        sizeBytes is! int ||
        sizeBytes <= 0 ||
        sha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        contentType is! String ||
        !const {
          'image/jpeg',
          'image/png',
          'image/webp',
        }.contains(contentType)) {
      return {
        ...image,
        'url': '',
        'readGrant': null,
        'readGrantError': {
          'code': 'character_image_metadata_invalid',
          'message': 'The sheet metadata is unavailable.',
        },
      };
    }
    try {
      final signer = await connectedDataApi.signerForWorkspace(workspaceId);
      final signed = await signer.signReadUrl(
        path,
        generation: generation,
        cacheIdentity: AssetReadGrantCacheIdentity(
          workspaceId: workspaceId,
          jobId: jobId,
          sizeBytes: sizeBytes,
          sha256: sha256,
          contentType: contentType,
        ),
      );
      return {
        ...image,
        'url': '',
        'readGrant': {
          'url': signed.url,
          'expiresAt': signed.expiresAt.toIso8601String(),
          'workspaceId': workspaceId,
          'jobId': jobId,
          'bucket': signer.connection.bucket,
          'object': path,
          'generation': generation,
          'sizeBytes': sizeBytes,
          'sha256': sha256,
          'contentType': contentType,
        },
      };
    } on ApiError catch (error) {
      return {
        ...image,
        'url': '',
        'readGrant': null,
        'readGrantError': _characterAssetError(error),
      };
    }
  }
}

Map<String, Object?> _characterAssetError(ApiError error) => {
  'code': error.code,
  'message': error.message,
};

Map<String, Object?>? _characterMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}
