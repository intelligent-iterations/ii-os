part of 'api.dart';

extension _CharacterGenerationRoutes on IiOsApi {
  Future<Response?> _characterGenerationRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length != 6 || request.method != 'POST') return null;
    final operation = path[5];
    if (!const {
      'generate',
      'generate-body',
      'generate-from-image',
      'edit-sheet',
      'inpaint-sheet',
    }.contains(operation)) {
      return null;
    }
    await store.requireAccess(actor, workspaceId, Capability.charactersWrite);
    await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
    final characterId = path[4];
    var character = await characters.getCharacter(workspaceId, characterId);
    final workspace = await store.getWorkspace(workspaceId);

    late final String workflowKey;
    late final String action;
    late final Map<String, Object?> input;
    late final Future<Map<String, Object?>> Function(String jobId) record;
    var promptEnhancementBypass = characterPromptEnhancementBypass(operation);

    switch (operation) {
      case 'generate':
        action = 'character.generate';
        input = buildCharacterGenerationInput(character);
        workflowKey = selectCharacterImageWorkflow(workspace.workflows);
        record = (jobId) => characters.recordGenerationRequested(
          workspaceId: workspaceId,
          characterId: characterId,
          jobId: jobId,
          updatedBy: actor.uid,
        );
      case 'generate-body':
        final body = await readJsonObject(request);
        if (body.isNotEmpty) {
          throw const ApiError(
            400,
            'character_creation_flow_mismatch',
            'Scratch body generation does not accept an image source.',
          );
        }
        action = 'character.body.generate';
        input = buildCharacterBodyGenerationInput(character);
        workflowKey = selectCharacterBodyWorkflow(workspace.workflows);
        record = (jobId) => characters.recordBodyGenerationRequested(
          workspaceId: workspaceId,
          characterId: characterId,
          jobId: jobId,
          updatedBy: actor.uid,
        );
      case 'generate-from-image':
        if (character['creationMode'] != 'image') {
          buildImageCharacterGenerationInput(character);
        }
        final sourceAssetId = character['sourceAssetId'] as String? ?? '';
        await workflowApi.sourceAssets.workflowReadContract(
          workspaceId: workspaceId,
          assetId: sourceAssetId,
        );
        character = await characters.prepareImageCharacter(
          workspaceId: workspaceId,
          characterId: characterId,
          updatedBy: actor.uid,
        );
        workflowKey = selectCharacterReferenceWorkflow(workspace.workflows);
        action = 'character.image.generate';
        input = buildImageCharacterGenerationInput(character);
        record = (jobId) => characters.recordImageGenerationRequested(
          workspaceId: workspaceId,
          characterId: characterId,
          jobId: jobId,
          updatedBy: actor.uid,
        );
      case 'edit-sheet':
        final body = await readJsonObject(request);
        promptEnhancementBypass = requestedPromptEnhancementBypass(
          body['promptEnhancementBypass'],
        );
        final sourceAssetId = requiredString(
          body,
          'sourceAssetId',
          maxLength: 64,
        );
        await workflowApi.sourceAssets.workflowReadContract(
          workspaceId: workspaceId,
          assetId: sourceAssetId,
        );
        workflowKey = selectCharacterReferenceWorkflow(workspace.workflows);
        action = 'character.sheet.edit';
        input = buildCharacterSheetEditInput(
          character: character,
          sourceAssetId: sourceAssetId,
          prompt: requiredString(body, 'prompt', maxLength: 4000),
        );
        record = (jobId) => characters.recordSheetEditRequested(
          workspaceId: workspaceId,
          characterId: characterId,
          jobId: jobId,
          updatedBy: actor.uid,
        );
      case 'inpaint-sheet':
        final body = await readJsonObject(request);
        promptEnhancementBypass = requestedPromptEnhancementBypass(
          body['promptEnhancementBypass'],
        );
        final sourceAssetId = requiredString(
          body,
          'sourceAssetId',
          maxLength: 64,
        );
        await workflowApi.sourceAssets.workflowReadContract(
          workspaceId: workspaceId,
          assetId: sourceAssetId,
        );
        workflowKey = selectCharacterInpaintWorkflow(workspace.workflows);
        action = 'character.sheet.inpaint';
        input = buildCharacterSheetInpaintInput(
          character: character,
          sourceAssetId: sourceAssetId,
          prompt: requiredString(body, 'prompt', maxLength: 4000),
          maskRegions: requiredString(body, 'maskRegions', maxLength: 4096),
        );
        record = (jobId) => characters.recordSheetEditRequested(
          workspaceId: workspaceId,
          characterId: characterId,
          jobId: jobId,
          updatedBy: actor.uid,
        );
      default:
        return null;
    }

    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: action,
      targetType: 'character',
      targetId: characterId,
      metadata: {'workflowKey': workflowKey},
      execute: () async {
        final job = await workflows.dispatch(
          workspace: workspace,
          actorUid: actor.uid,
          requestId: requestId,
          workflowKeyValue: workflowKey,
          input: input,
          generationSelection: characterGenerationSelection(
            operation: operation,
            characterId: characterId,
          ),
          generationReview: characterGenerationReview(operation),
          notificationDeepLink: Uri(
            pathSegments: [
              '',
              'workspaces',
              workspaceId,
              'characters',
              characterId,
            ],
            queryParameters: operation == 'generate-body'
                ? {'tab': 'body'}
                : null,
          ).toString(),
          promptEnhancementBypass: promptEnhancementBypass,
        );
        final updated = await record(job['jobId'] as String? ?? requestId);
        return {
          'character': await _withCharacterThumbnail(updated),
          'job': job,
        };
      },
    );
  }
}
