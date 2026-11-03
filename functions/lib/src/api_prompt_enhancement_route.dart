part of 'api.dart';

extension _PromptEnhancementRoute on IiOsApi {
  Future<Response?> _promptEnhancementRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length != 5 ||
        path[3] != 'prompt-enhancement' ||
        path[4] != 'preview' ||
        request.method != 'POST') {
      return null;
    }
    // Enhancing a prompt is part of composing a generation, not part of
    // administering the workspace. Gating it on workspace management would put
    // the button in front of everyone and then refuse most of them.
    await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
    final workspace = await store.getWorkspace(workspaceId);
    final body = await readJsonObject(request);
    final originalPrompt = requiredString(body, 'prompt', maxLength: 60000);
    final workflowId = requiredString(body, 'workflowId', maxLength: 64);
    // Optional because the workflow id already settles which guide applies,
    // and some surfaces deliberately never learn the model's name: telling
    // someone editing their character sheet that it ran on "Qwen Image Edit
    // 2511 FP8 Mixed" names the mechanism, not the thing they own.
    final targetModel = switch (body['targetModel']) {
      null => '',
      final String value when value.trim().length <= 100 => value.trim(),
      _ => throw const ApiError(
        400,
        'invalid_target_model',
        'The target model is invalid.',
      ),
    };
    final field = _promptEnhancementField(body['field']);
    final modality = _promptEnhancementModality(body['modality']);
    final attachedImageCount = _promptEnhancementImageCount(
      body['attachedImageCount'],
    );
    final maxLength = _promptEnhancementMaxLength(body['maxLength']);
    final purpose = _promptEnhancementPurpose(body['purpose']);
    final requestType = switch (body['requestType']) {
      final String value when value.trim().isNotEmpty => value.trim(),
      null => _requestTypeFor(modality, field: field),
      _ => throw const ApiError(
        400,
        'invalid_request_type',
        'The request type is invalid.',
      ),
    };
    if (requestType.length > 100) {
      throw const ApiError(
        400,
        'invalid_request_type',
        'The request type is invalid.',
      );
    }
    // Only this explicit preview action may rewrite visible text. Dispatch
    // later sends whichever text the person kept without another model call.
    final context = PromptEnhancementContext(
      workflowId: workflowId,
      targetModel: targetModel,
      requestType: requestType,
      attachedImageCount: attachedImageCount,
      field: field,
      modality: modality,
      purpose: purpose,
      library: await promptGuides.library(
        workspaceId: workspaceId,
        organizationId: workspace.organizationId,
      ),
    );
    return _audited(
      requestId: requestId,
      actor: actor,
      workspaceId: workspaceId,
      action: 'prompt_enhancement.preview',
      targetType: 'workspace',
      targetId: workspaceId,
      metadata: {
        'targetModel': targetModel,
        'attachedImageCount': attachedImageCount,
        'field': field,
        'bible': context.bible.id,
      },
      execute: () async {
        final result = await promptEnhancer.enhance(
          workspace: workspace,
          originalPrompt: originalPrompt,
          context: context,
          maxPromptLength: maxLength,
        );
        return {
          'prompt': result.prompt,
          'promptEnhancement': result.toMetadata(),
        };
      },
    );
  }

  /// Moves a pasted DeepSeek key out of a workspace update and into encrypted
  /// storage, leaving behind only the fact that a key exists and its last four
  /// characters.
  Future<Map<String, Object?>> _withStoredPromptEnhancementKey(
    String workspaceId,
    AuthenticatedUser actor,
    Map<String, Object?> body,
  ) async {
    if (!body.containsKey('promptEnhancement')) return body;
    final submission = parsePromptEnhancement(body['promptEnhancement']);
    final current = (await store.getWorkspace(workspaceId)).promptEnhancement;
    var hasApiKey = current?.hasApiKey ?? false;
    var apiKeyLast4 = current?.apiKeyLast4 ?? '';
    if (submission.clearApiKey) {
      await promptEnhancementKeys.clear(workspaceId);
      hasApiKey = false;
      apiKeyLast4 = '';
    } else if (submission.hasPastedKey) {
      apiKeyLast4 = await promptEnhancementKeys.write(
        workspaceId: workspaceId,
        apiKey: submission.apiKey,
        updatedBy: actor.uid,
      );
      hasApiKey = true;
    }
    return {
      ...body,
      'promptEnhancement': promptEnhancementDocument(
        submission: submission,
        hasApiKey: hasApiKey,
        apiKeyLast4: apiKeyLast4,
      ),
    };
  }
}

String _promptEnhancementField(Object? value) {
  final field = switch (value) {
    null => 'prompt',
    final String raw => raw.trim(),
    _ => '',
  };
  if (!creativeInputLabels.containsKey(field)) {
    throw const ApiError(
      400,
      'invalid_prompt_enhancement_field',
      'That field is not one ii-os enhances.',
    );
  }
  return field;
}

/// Whether the text belongs to a storyboard panel.
///
/// A panel prompt carries continuity duty that a standalone one does not -- the
/// same characters, wardrobe, and visual language across every panel -- so the
/// preview has to be able to say so, or the rewrite a person reviews is not the
/// rewrite dispatch would have produced.
PromptEnhancementPurpose _promptEnhancementPurpose(Object? value) =>
    switch (value) {
      null || 'general' => PromptEnhancementPurpose.general,
      'storyboard_panel' => PromptEnhancementPurpose.storyboardPanel,
      _ => throw const ApiError(
        400,
        'invalid_prompt_enhancement_purpose',
        'That prompt enhancement purpose is not one ii-os supports.',
      ),
    };

CreativeModality? _promptEnhancementModality(Object? value) {
  if (value == null) return null;
  final modality = value is String ? CreativeModality.tryParse(value) : null;
  if (modality == null) {
    throw const ApiError(
      400,
      'invalid_prompt_enhancement_modality',
      'That creative modality is not one ii-os enhances.',
    );
  }
  return modality;
}

int _promptEnhancementImageCount(Object? value) {
  if (value is! num || value.toInt() != value || value < 0 || value > 10) {
    throw const ApiError(
      400,
      'invalid_attachment_count',
      'Attached image count must be between zero and ten.',
    );
  }
  return value.toInt();
}

/// The length budget of the field this text is destined for.
///
/// Sent by the caller because only it knows which workflow input the text will
/// land in, and the budgets differ by an order of magnitude -- 4,000 characters
/// for a song description against 30,000 for its lyrics. Enhancing past the
/// budget produces a prompt the dispatch would then reject.
int _promptEnhancementMaxLength(Object? value) {
  if (value == null) return 60000;
  if (value is! num || value.toInt() != value || value < 1 || value > 60000) {
    throw const ApiError(
      400,
      'invalid_prompt_max_length',
      'The prompt length budget is invalid.',
    );
  }
  return value.toInt();
}

String _requestTypeFor(CreativeModality? modality, {required String field}) =>
    switch (modality) {
      CreativeModality.speech => 'text-to-speech narration',
      CreativeModality.lyrics => 'song lyrics',
      CreativeModality.music => 'text-to-music generation',
      CreativeModality.video => 'text-to-video',
      CreativeModality.inpaint => 'image-to-image inpaint',
      CreativeModality.imageEdit => 'image-to-image edit',
      CreativeModality.image => 'text-to-image generation',
      null => field == 'lyrics' ? 'song lyrics' : 'text-to-image generation',
    };
