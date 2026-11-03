import 'dart:convert';

import 'api_error.dart';
import 'prompt_enhancer.dart';
import 'workflow_catalog_store.dart';

const characterSheetAspectRatio = '16:9';

const characterReferenceTurnaroundPrompt =
    '''Using the provided image as the reference, edit the depicted subject into a full-body three-view character sheet.

Preserve the subject exactly as depicted in the reference image. Maintain the same identity, species, design, facial features, head shape, body characteristics, proportions, colors, patterns, textures, hair, fur, skin, clothing, accessories, and all other visible details. Do not redesign, stylize, beautify, simplify, or reinterpret the subject.

If the subject or any part of its body is cut off, obstructed, or outside the reference image, naturally complete the missing areas. Base the continuation on the subject\u2019s visible anatomy, species, proportions, design, and the most likely continuation of its clothing or appearance. Keep all inferred details conservative, plausible, and consistent with what is visible. Do not add unnecessary features, accessories, decorations, or clothing.

Show the exact same subject three times in one horizontal row as a continuous rotation:

1. Front view \u2014 facing directly forward.
2. Exact side view \u2014 rotated exactly 90 degrees, facing toward the right side of the image.
3. Back view \u2014 rotated exactly 180 degrees, facing directly away.

Show the subject\u2019s complete body in every view without cropping. Use the same neutral, natural resting position throughout, adjusted only as necessary to show the three viewpoints clearly.

The three figures must represent the same unchanged subject viewed from different angles\u2014not three variations of the subject. Keep the identity, anatomy, proportions, scale, clothing, accessories, surface details, and overall design identical across all views. Rotate the entire subject naturally as one complete form.

Arrange the three views at the same size, aligned along the same baseline, with clear and even spacing. Use an eye-level orthographic presentation with minimal perspective distortion, soft neutral studio lighting, and a plain white seamless background.

This is a character-sheet conversion of the existing subject, not a new character design.

Do not reproduce the reference pose, framing, environment, or background.
Do not change the subject\u2019s identity or appearance.
Do not invent prominent details that are unsupported by the reference.
Do not add text, labels, arrows, borders, props, scenery, or additional subjects.''';

PromptEnhancementBypass? characterPromptEnhancementBypass(String operation) {
  return switch (operation) {
    'generate' ||
    'generate-body' => PromptEnhancementBypass.characterPromptBuilder,
    'generate-from-image' => PromptEnhancementBypass.imageToCharacter,
    _ => null,
  };
}

String selectCharacterImageWorkflow(Iterable<String> workflowKeys) {
  return _selectWorkflow(
    workflowKeys,
    workflowId: 'image-create',
    errorCode: 'character_image_workflow_unavailable',
    errorMessage:
        'Enable an image generation workflow for this workspace first.',
  );
}

String selectCharacterBodyWorkflow(Iterable<String> workflowKeys) {
  return _selectWorkflow(
    workflowKeys,
    workflowId: 'image-create',
    errorCode: 'character_body_workflow_unavailable',
    errorMessage:
        'Enable an image generation workflow for this workspace first.',
  );
}

String selectCharacterReferenceWorkflow(Iterable<String> workflowKeys) {
  return _selectWorkflow(
    workflowKeys,
    workflowId: 'image-edit-qwen-2511',
    errorCode: 'character_reference_workflow_unavailable',
    errorMessage:
        'Enable the Qwen Image Edit workflow for image-based characters.',
  );
}

String selectCharacterInpaintWorkflow(Iterable<String> workflowKeys) {
  return _selectWorkflow(
    workflowKeys,
    workflowId: 'image-inpaint-qwen',
    errorCode: 'character_inpaint_workflow_unavailable',
    errorMessage:
        'Enable the Qwen area-edit workflow before editing part of a character sheet.',
  );
}

Map<String, Object?>? characterGenerationSelection({
  required String operation,
  required String characterId,
}) {
  if (operation == 'edit-sheet' || operation == 'inpaint-sheet') return null;
  return {
    'kind': 'character_image',
    'characterId': characterId,
    'body': operation != 'generate',
  };
}

Map<String, Object?>? characterGenerationReview(String operation) =>
    switch (operation) {
      'edit-sheet' => const {
        'kind': 'character_sheet_edit',
        'mode': 'wholeSheet',
      },
      'inpaint-sheet' => const {'kind': 'character_sheet_edit', 'mode': 'area'},
      _ => null,
    };

String _selectWorkflow(
  Iterable<String> workflowKeys, {
  required String workflowId,
  required String errorCode,
  required String errorMessage,
}) {
  final matches = <String>[];
  for (final key in workflowKeys) {
    try {
      if (parseWorkflowKey(key).workflowId == workflowId) {
        matches.add(key);
      }
    } on ApiError {
      // Invalid workspace entries cannot shadow a valid image workflow.
    }
  }
  if (matches.isEmpty) {
    throw ApiError(409, errorCode, errorMessage);
  }
  matches.sort();
  return matches.first;
}

Map<String, Object?> buildCharacterGenerationInput(
  Map<String, Object?> character,
) {
  _requireCreationMode(character, 'scratch');
  if (character['status'] != 'ready') {
    throw const ApiError(
      409,
      'character_not_ready',
      'Complete the character questionnaire before generating its sheet.',
    );
  }
  final prompt = character['prompt'] as String? ?? '';
  if (prompt.trim().isEmpty) {
    throw const ApiError(
      409,
      'character_prompt_missing',
      'The completed character does not have a saved prompt.',
    );
  }
  return {'prompt': prompt, 'aspect_ratio': characterSheetAspectRatio};
}

Map<String, Object?> buildCharacterBodyGenerationInput(
  Map<String, Object?> character,
) {
  _requireCreationMode(character, 'scratch');
  if (character['status'] != 'ready') {
    throw const ApiError(
      409,
      'character_not_ready',
      'Complete the character questionnaire before generating the body.',
    );
  }
  final prompt =
      ((character['bodyPrompt'] ?? character['prompt']) as String? ?? '')
          .replaceFirst(
            RegExp(r'^TEXT-TO-IMAGE FULL-BODY CHARACTER SHEET\s*'),
            '',
          )
          .trim();
  if (prompt.trim().isEmpty) {
    throw const ApiError(
      409,
      'character_body_prompt_missing',
      'The character does not have a saved body prompt.',
    );
  }
  return {'prompt': prompt, 'aspect_ratio': characterSheetAspectRatio};
}

Map<String, Object?> buildImageCharacterGenerationInput(
  Map<String, Object?> character,
) {
  _requireCreationMode(character, 'image');
  if (character['status'] != 'ready') {
    throw const ApiError(
      409,
      'character_not_ready',
      'The image-based character is not ready for generation.',
    );
  }
  final sourceAssetId = character['sourceAssetId'];
  if (sourceAssetId is! String || sourceAssetId.trim().isEmpty) {
    throw const ApiError(
      409,
      'character_source_missing',
      'The image-based character does not have its source image.',
    );
  }
  return {
    'prompt': characterReferenceTurnaroundPrompt,
    'mode': 'edit',
    'source_asset_id': sourceAssetId,
    'control_strength': 0.65,
  };
}

Map<String, Object?> buildCharacterSheetEditInput({
  required Map<String, Object?> character,
  required String sourceAssetId,
  required String prompt,
}) {
  if (character['status'] != 'ready') {
    throw const ApiError(
      409,
      'character_not_ready',
      'The character must be ready before editing a generated sheet.',
    );
  }
  if (sourceAssetId.trim().isEmpty) {
    throw const ApiError(
      409,
      'character_source_missing',
      'The selected character sheet source is missing.',
    );
  }
  if (prompt.trim().isEmpty) {
    throw const ApiError(
      400,
      'character_edit_prompt_missing',
      'Describe the change to make to the selected character sheet.',
    );
  }
  return {
    'prompt': prompt.trim(),
    'mode': 'edit',
    'source_asset_id': sourceAssetId.trim(),
    'control_strength': 0.65,
  };
}

Map<String, Object?> buildCharacterSheetInpaintInput({
  required Map<String, Object?> character,
  required String sourceAssetId,
  required String prompt,
  required String maskRegions,
}) {
  final base = buildCharacterSheetEditInput(
    character: character,
    sourceAssetId: sourceAssetId,
    prompt: prompt,
  );
  final regions = _validatedInpaintRegions(maskRegions);
  final first = regions.first;
  return {
    ...base,
    'mode': 'inpaint',
    'control_strength': 1.0,
    'mask_x': first[0],
    'mask_y': first[1],
    'mask_width': first[2],
    'mask_height': first[3],
    'mask_regions': jsonEncode(regions),
  };
}

List<List<double>> _validatedInpaintRegions(String encoded) {
  Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException {
    throw const ApiError(
      400,
      'character_inpaint_mask_invalid',
      'Select one or more valid areas to edit.',
    );
  }
  if (decoded is! List || decoded.isEmpty || decoded.length > 32) {
    throw const ApiError(
      400,
      'character_inpaint_mask_invalid',
      'Select between 1 and 32 areas to edit.',
    );
  }
  final regions = <List<double>>[];
  for (final raw in decoded) {
    if (raw is! List || raw.length != 4 || raw.any((value) => value is! num)) {
      throw const ApiError(
        400,
        'character_inpaint_mask_invalid',
        'Every edit area must be a valid rectangle.',
      );
    }
    final region = raw.cast<num>().map((value) => value.toDouble()).toList();
    final x = region[0];
    final y = region[1];
    final width = region[2];
    final height = region[3];
    if (region.any((value) => !value.isFinite || value < 0) ||
        width <= 0 ||
        height <= 0 ||
        x + width > 1.0001 ||
        y + height > 1.0001) {
      throw const ApiError(
        400,
        'character_inpaint_mask_invalid',
        'Every edit area must remain inside the image.',
      );
    }
    regions.add(region);
  }
  return regions;
}

void _requireCreationMode(Map<String, Object?> character, String expectedMode) {
  if (character['creationMode'] == expectedMode) return;
  throw ApiError(
    409,
    'character_creation_flow_mismatch',
    expectedMode == 'image'
        ? 'Use image generation only with an image-based character.'
        : 'Use interview generation only with a scratch character.',
  );
}
