import 'dart:convert';

import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/character_generation.dart';
import 'package:ii_os_functions/src/prompt_enhancer.dart';
import 'package:test/test.dart';

void main() {
  test('bypasses enhancement only for built-in character prompts', () {
    expect(
      characterPromptEnhancementBypass('generate'),
      PromptEnhancementBypass.characterPromptBuilder,
    );
    expect(
      characterPromptEnhancementBypass('generate-body'),
      PromptEnhancementBypass.characterPromptBuilder,
    );
    expect(
      characterPromptEnhancementBypass('generate-from-image'),
      PromptEnhancementBypass.imageToCharacter,
    );
    expect(characterPromptEnhancementBypass('edit-sheet'), isNull);
    expect(characterPromptEnhancementBypass('inpaint-sheet'), isNull);
  });

  test('sheet edits require review while ordinary generations auto-select', () {
    expect(
      characterGenerationSelection(
        operation: 'generate-body',
        characterId: 'character-1',
      ),
      {'kind': 'character_image', 'characterId': 'character-1', 'body': true},
    );
    expect(
      characterGenerationSelection(
        operation: 'edit-sheet',
        characterId: 'character-1',
      ),
      isNull,
    );
    expect(
      characterGenerationSelection(
        operation: 'inpaint-sheet',
        characterId: 'character-1',
      ),
      isNull,
    );
    expect(characterGenerationReview('edit-sheet'), {
      'kind': 'character_sheet_edit',
      'mode': 'wholeSheet',
    });
    expect(characterGenerationReview('inpaint-sheet'), {
      'kind': 'character_sheet_edit',
      'mode': 'area',
    });
    expect(characterGenerationReview('generate-body'), isNull);
  });

  test('selects an enabled image-create workflow deterministically', () {
    expect(
      selectCharacterImageWorkflow(const [
        'broken',
        'zeta/media#image-create',
        'acme/media#image-create',
        'acme/media#image-to-video',
      ]),
      'acme/media#image-create',
    );
  });

  test('requires an enabled image-create workflow', () {
    expect(
      () => selectCharacterImageWorkflow(const ['acme/media#image-to-video']),
      throwsA(_apiError('character_image_workflow_unavailable')),
    );
  });

  test('selects the image-create workflow for body generation', () {
    expect(
      selectCharacterBodyWorkflow(const [
        'zeta/media#image-edit',
        'acme/media#image-edit',
        'acme/media#image-create',
      ]),
      'acme/media#image-create',
    );
  });

  test('selected workflow metadata is JSON serializable', () {
    final workflowKey = selectCharacterReferenceWorkflow(const [
      'acme/media#image-edit-qwen-2511',
    ]);

    expect(jsonEncode({'workflowKey': workflowKey}), contains(workflowKey));
  });

  test('character inpainting selects only the Qwen inpaint workflow', () {
    expect(
      selectCharacterInpaintWorkflow(const [
        'acme/media#image-inpaint',
        'zeta/media#image-inpaint-qwen',
        'acme/media#image-inpaint-qwen',
      ]),
      'acme/media#image-inpaint-qwen',
    );
    expect(
      () => selectCharacterInpaintWorkflow(const ['acme/media#image-inpaint']),
      throwsA(_apiError('character_inpaint_workflow_unavailable')),
    );
  });

  test('builds one Qwen inpaint input for disconnected character areas', () {
    for (final creationMode in const ['scratch', 'image']) {
      expect(
        buildCharacterSheetInpaintInput(
          character: {'creationMode': creationMode, 'status': 'ready'},
          sourceAssetId: 'selected-sheet',
          prompt: 'Make the chest marking consistent across all views.',
          maskRegions: '[[0.1,0.2,0.2,0.15],[0.65,0.55,0.1,0.2]]',
        ),
        {
          'prompt': 'Make the chest marking consistent across all views.',
          'mode': 'inpaint',
          'source_asset_id': 'selected-sheet',
          'control_strength': 1.0,
          'mask_x': 0.1,
          'mask_y': 0.2,
          'mask_width': 0.2,
          'mask_height': 0.15,
          'mask_regions': '[[0.1,0.2,0.2,0.15],[0.65,0.55,0.1,0.2]]',
        },
        reason: creationMode,
      );
    }
  });

  test('rejects malformed or out-of-bounds character inpaint masks', () {
    const character = {'creationMode': 'scratch', 'status': 'ready'};
    for (final masks in const [
      '[]',
      'not-json',
      '[[0.9,0.9,0.2,0.2]]',
      '[[0.1,0.1,0,0.2]]',
    ]) {
      expect(
        () => buildCharacterSheetInpaintInput(
          character: character,
          sourceAssetId: 'selected-sheet',
          prompt: 'Change this area.',
          maskRegions: masks,
        ),
        throwsA(_apiError('character_inpaint_mask_invalid')),
        reason: masks,
      );
    }
  });

  test('builds a 16:9 job input from the current saved prompt', () {
    expect(
      buildCharacterGenerationInput(const {
        'creationMode': 'scratch',
        'status': 'ready',
        'prompt': 'Permanent specification\n\nCharacter: Example hero.',
      }),
      {
        'prompt': 'Permanent specification\n\nCharacter: Example hero.',
        'aspect_ratio': '16:9',
      },
    );
  });

  test('rejects draft characters', () {
    expect(
      () => buildCharacterGenerationInput(const {
        'creationMode': 'scratch',
        'status': 'draft',
        'prompt': 'Partial prompt',
      }),
      throwsA(_apiError('character_not_ready')),
    );
  });

  test('builds text-to-image body input without a source asset', () {
    expect(
      buildCharacterBodyGenerationInput(const {
        'creationMode': 'scratch',
        'status': 'ready',
        'bodyPrompt': 'TEXT-TO-IMAGE FULL-BODY CHARACTER SHEET\nHEAD: details',
      }),
      {'prompt': 'HEAD: details', 'aspect_ratio': '16:9'},
    );
  });

  test('body generation requires a completed character', () {
    expect(
      () => buildCharacterBodyGenerationInput(const {
        'creationMode': 'scratch',
        'status': 'draft',
        'bodyPrompt': 'Body prompt',
      }),
      throwsA(_apiError('character_not_ready')),
    );
  });

  test('scratch generation rejects image-based characters', () {
    expect(
      () => buildCharacterBodyGenerationInput(const {
        'creationMode': 'image',
        'status': 'ready',
        'bodyPrompt': 'Interview prompt',
      }),
      throwsA(_apiError('character_creation_flow_mismatch')),
    );
  });

  test('builds image generation input only from its stored source', () {
    expect(
      buildImageCharacterGenerationInput(const {
        'creationMode': 'image',
        'status': 'ready',
        'sourceAssetId': 'source-123',
      }),
      {
        'prompt': characterReferenceTurnaroundPrompt,
        'mode': 'edit',
        'source_asset_id': 'source-123',
        'control_strength': 0.65,
      },
    );
  });

  test('keeps the approved image-to-character conversion prompt verbatim', () {
    expect(
      characterReferenceTurnaroundPrompt,
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
Do not add text, labels, arrows, borders, props, scenery, or additional subjects.''',
    );
  });

  test('image generation rejects scratch characters', () {
    expect(
      () => buildImageCharacterGenerationInput(const {
        'creationMode': 'scratch',
        'status': 'ready',
        'sourceAssetId': 'source-123',
      }),
      throwsA(_apiError('character_creation_flow_mismatch')),
    );
  });
}

Matcher _apiError(String code) =>
    isA<ApiError>().having((error) => error.code, 'code', code);
