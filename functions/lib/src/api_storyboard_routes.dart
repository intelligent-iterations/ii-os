part of 'api.dart';

extension _StoryboardRoutes on IiOsApi {
  Future<Response> _storyboardRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length == 8 &&
        path[5] == 'panels' &&
        path[7] == 'images' &&
        request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsRead);
      final images = await store.listStoryboardPanelImages(
        workspaceId: workspaceId,
        storyboardId: path[4],
        panelId: path[6],
      );
      return jsonResponse(200, {
        'images': await _withStoryboardPanelImageMetadata(workspaceId, images),
      }, requestId: requestId);
    }
    if (path.length == 8 &&
        path[5] == 'panels' &&
        path[7] == 'selected-image' &&
        request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final body = await readJsonObject(request);
      final workspace = await store.getWorkspace(workspaceId);
      final jobId = requiredString(body, 'jobId', maxLength: 200);
      final imagePath = requiredString(body, 'path', maxLength: 900);
      final generation = requiredString(body, 'generation', maxLength: 100);
      final attachment = 'storyboard/${path[4]}/panel/${path[6]}/image';
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'storyboard.panel.image.select',
        targetType: 'storyboard_panel',
        targetId: path[6],
        metadata: {'storyboardId': path[4], 'jobId': jobId},
        execute: () async {
          await store.requireSelectableStoryboardPanelImage(
            workspaceId: workspaceId,
            storyboardId: path[4],
            panelId: path[6],
            jobId: jobId,
            path: imagePath,
            generation: generation,
          );
          final acquired = await assetRetention.protectRecord(
            workspaceId: workspaceId,
            collection: 'jobRuns',
            recordId: jobId,
            attachment: attachment,
          );
          late Map<String, Object?> updated;
          try {
            updated = await store.selectStoryboardPanelImage(
              workspaceId: workspaceId,
              storyboardId: path[4],
              panelId: path[6],
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
          return _withStoryboardJobs(workspace, updated);
        },
      );
    }
    if (path.length == 8 &&
        path[5] == 'panels' &&
        path[7] == 'animate' &&
        request.method == 'POST') {
      return _animateStoryboardPanel(
        request,
        requestId,
        actor,
        workspaceId,
        path,
      );
    }
    if (path.length == 9 &&
        path[5] == 'panels' &&
        path[7] == 'extend' &&
        path[8] == 'prepare-upload' &&
        request.method == 'POST') {
      return _prepareStoryboardPanelExtendUpload(
        request,
        requestId,
        actor,
        workspaceId,
        path,
      );
    }
    if (path.length == 9 &&
        path[5] == 'panels' &&
        path[7] == 'extend' &&
        path[8] == 'complete' &&
        request.method == 'POST') {
      return _completeStoryboardPanelExtend(
        request,
        requestId,
        actor,
        workspaceId,
        path,
      );
    }
    if (path.length == 4 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsRead);
      return jsonResponse(200, {
        'storyboards': await store.listStoryboards(workspaceId),
      }, requestId: requestId);
    }
    if (path.length == 4 && request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final body = await readJsonObject(request);
      final rawPanelCount = body['panelCount'];
      final panelCount = rawPanelCount == null
          ? storyboardMinimumPanels
          : rawPanelCount is num
          ? rawPanelCount.toInt()
          : -1;
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'storyboard.create',
        targetType: 'storyboard',
        execute: () => store.createStoryboard(
          workspaceId: workspaceId,
          createdBy: actor.uid,
          name: body['name'],
          overview: body['overview'] ?? '',
          panelCount: panelCount,
        ),
      );
    }
    if (path.length == 5 && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.jobsRead);
      final workspace = await store.getWorkspace(workspaceId);
      final storyboard = await store.getStoryboard(workspaceId, path[4]);
      return jsonResponse(200, {
        'storyboard': await _withStoryboardJobs(workspace, storyboard),
      }, requestId: requestId);
    }
    if (path.length == 5 && request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final body = await readJsonObject(request);
      final workspace = await store.getWorkspace(workspaceId);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'storyboard.update',
        targetType: 'storyboard',
        targetId: path[4],
        execute: () async {
          final before = await store.getStoryboard(workspaceId, path[4]);
          final updated = await store.updateStoryboard(
            workspaceId: workspaceId,
            storyboardId: path[4],
            updatedBy: actor.uid,
            changes: body,
          );
          await assetRetention.releaseRemovedGraph(
            workspaceId: workspaceId,
            before: storyboardAssetAttachmentGraph(before),
            after: storyboardAssetAttachmentGraph(updated),
            retentionDays: artifactRetentionDays(
              workspace.artifactStorage?.retentionDays,
            ),
          );
          return _withStoryboardJobs(workspace, updated);
        },
      );
    }
    if (path.length == 5 && request.method == 'DELETE') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'storyboard.delete',
        targetType: 'storyboard',
        targetId: path[4],
        execute: () async {
          final storyboard = await store.getStoryboard(workspaceId, path[4]);
          await store.deleteStoryboard(workspaceId, path[4]);
          final workspace = await store.getWorkspace(workspaceId);
          await assetRetention.releaseRemovedGraph(
            workspaceId: workspaceId,
            before: storyboardAssetAttachmentGraph(storyboard),
            after: const {},
            retentionDays: artifactRetentionDays(
              workspace.artifactStorage?.retentionDays,
            ),
          );
          return {'id': path[4], 'deleted': true};
        },
      );
    }
    if (path.length == 8 &&
        path[5] == 'panels' &&
        path[7] == 'generate' &&
        request.method == 'POST') {
      await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
      final body = await readJsonObject(request);
      final workflowKey = requiredString(body, 'workflowKey', maxLength: 400);
      final promptEnhancementBypass = requestedPromptEnhancementBypass(
        body['promptEnhancementBypass'],
      );
      final rawInput = body['input'];
      if (rawInput != null && rawInput is! Map<String, Object?>) {
        throw const ApiError(
          400,
          'invalid_job_input',
          'Storyboard generation input is invalid.',
        );
      }
      final storyboard = await store.getStoryboard(workspaceId, path[4]);
      final panels = _storyboardMaps(storyboard['panels']);
      final panelIndex = panels.indexWhere((panel) => panel['id'] == path[6]);
      if (panelIndex < 0) {
        throw const ApiError(
          404,
          'storyboard_panel_not_found',
          'Storyboard panel not found.',
        );
      }
      final panel = panels[panelIndex];
      final characterIds = (panel['characterIds'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toSet();
      final panelReferenceIds = storyboardPanelReferenceIds(
        panel['referencePanelIds'],
      );
      if (characterIds.length + panelReferenceIds.length > 3) {
        throw const ApiError(
          409,
          'storyboard_reference_limit',
          'Select up to 3 total character and panel references.',
        );
      }
      if (characterIds.isNotEmpty) {
        await store.requireAccess(
          actor,
          workspaceId,
          Capability.charactersRead,
        );
      }
      final attachedCharacters = await Future.wait(
        characterIds.map(
          (characterId) => characters.getCharacter(workspaceId, characterId),
        ),
      );
      final referenceImages = selectedCharacterReferenceImages(
        attachedCharacters,
      );
      final panelReferenceSources = storyboardPanelReferenceSources(
        panels: panels,
        referencePanelIds: panelReferenceIds,
      );
      final hasReferenceImages =
          referenceImages.isNotEmpty || panelReferenceSources.isNotEmpty;
      final parsedWorkflow = parseWorkflowKey(workflowKey);
      final usesImageEdit =
          parsedWorkflow.workflowId == 'image-edit' ||
          parsedWorkflow.workflowId.startsWith('image-edit-');
      if (hasReferenceImages && !usesImageEdit) {
        throw const ApiError(
          409,
          'storyboard_reference_workflow_required',
          'Enable an image-edit workflow to generate with selected references.',
        );
      }
      if (hasReferenceImages &&
          parsedWorkflow.workflowId != 'image-edit-qwen-2511') {
        throw const ApiError(
          409,
          'storyboard_reference_qwen_required',
          'Storyboard references must use the Qwen Image Edit workflow.',
        );
      }
      if (!hasReferenceImages && usesImageEdit) {
        throw const ApiError(
          409,
          'storyboard_reference_missing',
          'Select a character or panel image before using image edit.',
        );
      }
      if (!hasReferenceImages && parsedWorkflow.workflowId != 'image-create') {
        throw const ApiError(
          409,
          'storyboard_z_image_required',
          'Scenes without image references must use the Z-Image workflow.',
        );
      }
      final generationPrompt = storyboardGenerationPrompt(panel['prompt']);
      final workspace = await store.getWorkspace(workspaceId);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'storyboard.panel.generate',
        targetType: 'storyboard_panel',
        targetId: path[6],
        metadata: {
          'storyboardId': path[4],
          'panelId': path[6],
          'workflowKey': workflowKey,
          'characterReferenceImages': referenceImages.length,
          'panelReferenceImages': panelReferenceSources.length,
        },
        execute: () async {
          final requestedInput = {...?rawInput as Map<String, Object?>?}
            ..remove('prompt');
          final referenceAssetIds = <String>[];
          final promptImageReferences = <PromptImageReference>[];
          if (usesImageEdit) {
            for (var index = 0; index < panelReferenceSources.length; index++) {
              final source = panelReferenceSources[index];
              referenceAssetIds.add(
                await _storyboardPanelSourceAsset(
                  workspace: workspace,
                  workspaceId: workspaceId,
                  actor: actor,
                  sourceJobId: source.sourceJobId,
                  selectedImage: source.selectedImage,
                  panelId: source.panelId,
                  requestId: requestId,
                ),
              );
              final sourcePanelIndex = panels.indexWhere(
                (panel) => panel['id'] == source.panelId,
              );
              promptImageReferences.add(
                PromptImageReference(
                  imageNumber: promptImageReferences.length + 1,
                  role: index == 0 ? 'source_scene' : 'scene_reference',
                  label: 'Storyboard panel ${sourcePanelIndex + 1}',
                ),
              );
            }
            final characterAssets =
                await CharacterReferenceSheetComposer(
                  sourceAssets: workflowApi.sourceAssets,
                ).createMany(
                  workspaceId: workspaceId,
                  actorUid: actor.uid,
                  characters: attachedCharacters,
                  retentionDays: artifactRetentionDays(
                    workspace.artifactStorage?.retentionDays,
                  ),
                );
            for (final asset in characterAssets) {
              referenceAssetIds.add(asset.assetId);
              promptImageReferences.add(
                PromptImageReference(
                  imageNumber: promptImageReferences.length + 1,
                  role: 'character',
                  label: asset.name,
                ),
              );
            }
          }
          await store.recordStoryboardPanelGeneration(
            workspaceId: workspaceId,
            storyboardId: path[4],
            panelId: path[6],
            jobId: requestId,
            generationPrompt: generationPrompt,
            updatedBy: actor.uid,
          );
          Map<String, Object?> job;
          try {
            job = await workflows.dispatch(
              workspace: workspace,
              actorUid: actor.uid,
              requestId: requestId,
              workflowKeyValue: workflowKey,
              input: {
                if (usesImageEdit)
                  ...storyboardReferenceWorkflowInput(
                    requestedInput: requestedInput,
                    referenceAssetIds: referenceAssetIds,
                  )
                else
                  ...requestedInput,
                'prompt': generationPrompt,
              },
              generationSelection: {
                'kind': 'storyboard_panel_image',
                'storyboardId': path[4],
                'panelId': path[6],
              },
              notificationDeepLink: Uri(
                pathSegments: [
                  '',
                  'workspaces',
                  workspaceId,
                  'storyboards',
                  path[4],
                ],
                queryParameters: {'panel': path[6]},
              ).toString(),
              promptEnhancementPurpose:
                  PromptEnhancementPurpose.storyboardPanel,
              promptEnhancementBypass: promptEnhancementBypass,
              promptSuffix: storyboardReferencePrompt(promptImageReferences),
            );
          } on Object catch (error) {
            final code = error is ApiError
                ? error.code
                : error.runtimeType.toString();
            final message = error is ApiError
                ? error.message
                : 'The generation request could not be dispatched.';
            await store.recordStoryboardPanelGenerationFailure(
              workspaceId: workspaceId,
              storyboardId: path[4],
              panelId: path[6],
              jobId: requestId,
              code: code,
              message: message,
              updatedBy: actor.uid,
            );
            rethrow;
          }
          final updated = await store.getStoryboard(workspaceId, path[4]);
          return {
            'storyboard': await _withStoryboardJobs(workspace, updated),
            'job': job,
          };
        },
      );
    }
    throw const ApiError(404, 'not_found', 'Storyboard route not found.');
  }

  Future<Map<String, Object?>> _withStoryboardJobs(
    Workspace workspace,
    Map<String, Object?> storyboard,
  ) async {
    final panels = await Future.wait(
      _storyboardMaps(
        storyboard['panels'],
      ).map((panel) => _withStoryboardPanelJobs(workspace, panel)),
    );
    return {...storyboard, 'panels': panels};
  }

  Future<Map<String, Object?>> _withStoryboardPanelJobs(
    Workspace workspace,
    Map<String, Object?> panel,
  ) async {
    var enriched = panel;
    final jobId = panel['jobId'];
    if (jobId is String && jobId.isNotEmpty) {
      try {
        final job = await workflows.getJob(workspace, jobId);
        enriched = {
          ...enriched,
          'job': await _withStoryboardJobImageMetadata(
            workspace.id,
            jobId,
            job,
          ),
        };
      } on ApiError catch (error) {
        enriched = {
          ...enriched,
          'job': null,
          'jobError': {'code': error.code, 'message': error.message},
        };
      }
    }
    final selectedImage = storyboardSelectedPanelImage(panel);
    final selectedImageJobId = selectedImage?['jobId'];
    if (selectedImageJobId is String &&
        selectedImageJobId.isNotEmpty &&
        selectedImageJobId != jobId) {
      try {
        final selectedImageJob = await workflows.getJob(
          workspace,
          selectedImageJobId,
        );
        enriched = {
          ...enriched,
          'selectedImageJob': await _withStoryboardJobImageMetadata(
            workspace.id,
            selectedImageJobId,
            selectedImageJob,
          ),
        };
      } on ApiError catch (error) {
        enriched = {
          ...enriched,
          'selectedImageJob': null,
          'selectedImageJobError': {
            'code': error.code,
            'message': error.message,
          },
        };
      }
    }
    final videoJobId = panel['videoJobId'];
    if (videoJobId is String && videoJobId.isNotEmpty) {
      try {
        enriched = {
          ...enriched,
          'videoJob': await workflows.getJob(workspace, videoJobId),
        };
      } on ApiError catch (error) {
        enriched = {
          ...enriched,
          'videoJob': null,
          'videoJobError': {'code': error.code, 'message': error.message},
        };
      }
    }
    return enriched;
  }

  Future<List<Map<String, Object?>>> _withStoryboardPanelImageMetadata(
    String workspaceId,
    List<Map<String, Object?>> images,
  ) => Future.wait(
    images.map((image) async {
      try {
        return await connectedDataApi.resolveVerifiedArtifactMetadata(
          workspaceId: workspaceId,
          jobId: image['jobId']?.toString() ?? '',
          artifact: image,
        );
      } on ApiError {
        return image;
      }
    }),
  );

  Future<Map<String, Object?>> _withStoryboardJobImageMetadata(
    String workspaceId,
    String jobId,
    Map<String, Object?> job,
  ) async {
    final artifacts = _storyboardMaps(job['artifacts']);
    final enriched = await Future.wait(
      artifacts.map((artifact) async {
        final contentType = artifact['content_type'];
        if (contentType is! String || !contentType.startsWith('image/')) {
          return artifact;
        }
        try {
          return await connectedDataApi.resolveVerifiedArtifactMetadata(
            workspaceId: workspaceId,
            jobId: jobId,
            artifact: artifact,
          );
        } on ApiError {
          return artifact;
        }
      }),
    );
    return {...job, 'artifacts': enriched};
  }
}

List<Map<String, Object?>> _storyboardMaps(Object? value) =>
    value is List<Object?>
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.cast<String, Object?>())
          .toList()
    : <Map<String, Object?>>[];
