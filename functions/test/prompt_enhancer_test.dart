import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ii_os_functions/src/creative_surface.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/model_bible_chatterbox.dart';
import 'package:ii_os_functions/src/model_bible_generic.dart';
import 'package:ii_os_functions/src/model_bible_ltx.dart';
import 'package:ii_os_functions/src/model_bible_lyrics.dart';
import 'package:ii_os_functions/src/model_bible_minimax_h3.dart';
import 'package:ii_os_functions/src/model_bible_qwen.dart';
import 'package:ii_os_functions/src/model_bibles.dart';
import 'package:ii_os_functions/src/prompt_enhancer.dart';
import 'package:test/test.dart';

/// Collapses the hard wrapping in a guide so an assertion can name a phrase
/// without also pinning where the line happens to break.
String _flat(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  test('resolves a bible by modality first and model family second', () {
    expect(
      modelBibleSelectionFor('Qwen Image Edit 2511 FP8 Mixed').id,
      'qwen-edit',
    );
    expect(
      modelBibleSelectionFor(
        'Qwen Image 2512',
        workflowId: 'image-create-qwen-2512',
      ).id,
      'qwen-image',
    );
    final qwenInpaint = modelBibleSelectionFor(
      'Qwen Image InstantX Inpaint',
      workflowId: 'image-inpaint-qwen',
    );
    expect(qwenInpaint.id, 'qwen-inpaint');
    expect(qwenInpaint.guide, contains(qwenImageEditModelBible.trim()));
    expect(qwenInpaint.guide, contains(inpaintingModelBible.trim()));
    expect(
      modelBibleSelectionFor(
        'Z-Image Turbo ControlNet',
        workflowId: 'image-inpaint',
      ).guide,
      contains(inpaintingModelBible.trim()),
    );
    expect(
      modelBibleSelectionFor(
        'FLUX Fill',
        workflowId: 'image-inpaint-flux',
      ).guide,
      contains(inpaintingModelBible.trim()),
    );
    expect(
      modelBibleSelectionFor('FLUX.2 Klein 4B').guide,
      contains('How FLUX reads a prompt'),
    );
    final ltx = modelBibleSelectionFor('LTX 2.3', workflowId: 'image-to-video');
    expect(ltx.id, 'ltx-video');
    final aceStep = modelBibleSelectionFor(
      'ACE-Step 1.5 Comfy Turbo / XL SFT',
      workflowId: 'song-create-acestep-xl-sft',
    );
    expect(aceStep.id, 'ace-step');
    expect(aceStep.guide, contains('music caption'));
    expect(ltx.guide, ltxVideoModelBible);
    final h3 = modelBibleSelectionFor(
      'MiniMax H3',
      workflowId: 'text-to-video-minimax-h3',
    );
    expect(h3.id, 'minimax-h3-video');
    expect(h3.guide, minimaxH3VideoModelBible);
  });

  test(
    'grounds narration and lyrics in their own modality, not an image guide',
    () {
      final narration = modelBibleSelectionFor(
        'Chatterbox Turbo TTS',
        workflowId: 'narration-create-chatterbox-tts',
        field: 'text',
      );
      expect(narration.id, 'chatterbox-speech');
      expect(narration.modality, CreativeModality.speech);
      expect(narration.guide, chatterboxNarrationModelBible);
      expect(narration.guide, isNot(contains('Z\u2011Image')));

      final lyrics = modelBibleSelectionFor(
        'ACE-Step 1.5 Comfy Turbo / XL SFT',
        workflowId: 'song-create-acestep-xl-sft',
        field: 'lyrics',
      );
      expect(lyrics.id, 'ace-step-lyrics');
      expect(lyrics.modality, CreativeModality.lyrics);
      expect(lyrics.guide, aceStepLyricsModelBible);
    },
  );

  test('falls back within the modality rather than across it', () {
    final unknownImage = modelBibleSelectionFor('unmatched-model');
    expect(unknownImage.id, 'generic-image');
    expect(unknownImage.guide, genericImageModelBible);
    expect(unknownImage.isModelSpecific, isFalse);

    final unknownSpeech = modelBibleSelectionFor(
      'unmatched-narrator',
      workflowId: 'read-aloud',
      field: 'text',
      modality: CreativeModality.speech,
    );
    expect(unknownSpeech.id, 'generic-speech');
    expect(unknownSpeech.guide, genericSpeechModelBible);
    expect(unknownSpeech.isModelSpecific, isFalse);

    final unknownVideo = modelBibleSelectionFor(
      'unmatched-video-model',
      workflowId: 'text-to-video-unknown',
    );
    expect(unknownVideo.id, 'generic-video');
    expect(unknownVideo.guide, genericVideoModelBible);
  });

  test('classifies song workflows as text-to-music generation', () {
    final context = PromptEnhancementContext.fromWorkflow(
      workflowId: 'song-create-acestep-xl-sft',
      targetModel: 'ACE-Step 1.5 Comfy Turbo / XL SFT',
      input: const {'prompt': 'dream pop with layered guitars'},
    );

    expect(context.requestType, 'text-to-music generation');
  });

  test(
    'disabled enhancement returns the original prompt without cloud access',
    () async {
      final result = await DeepSeekPromptEnhancer().enhance(
        workspace: const Workspace(
          id: 'workspace-1',
          name: 'Workspace',
          environment: 'dev',
          githubInstallationId: null,
          repositories: [],
          projects: [],
          workflows: [],
          artifactStorage: null,
        ),
        originalPrompt: '  Keep my prompt  ',
        context: const PromptEnhancementContext(
          workflowId: 'image-create',
          targetModel: 'Example image model',
          requestType: 'text-to-image generation',
          attachedImageCount: 0,
        ),
        maxPromptLength: 4000,
      );

      expect(result.prompt, 'Keep my prompt');
      expect(result.status, 'disabled');
      expect(result.bible, 'generic-image');
    },
  );

  test('bypasses built-in prompts without reading a secret', () {
    var secretRead = false;
    final enhancer = DeepSeekPromptEnhancer(
      secretReader: (_) async {
        secretRead = true;
        return 'unused';
      },
    );
    final result = enhancer.bypass(
      originalPrompt: '  Preserve this built-in prompt  ',
      context: const PromptEnhancementContext(
        workflowId: 'image-edit-qwen-2511',
        targetModel: 'Qwen Image Edit 2511 FP8 Mixed',
        requestType: 'image-to-image edit',
        attachedImageCount: 1,
      ),
      reason: PromptEnhancementBypass.imageToCharacter,
    );

    expect(result.prompt, 'Preserve this built-in prompt');
    expect(result.status, 'skipped');
    expect(result.bible, 'qwen-edit');
    expect(result.skipReason, 'image_to_character');
    expect(result.toMetadata()['skipReason'], 'image_to_character');
    expect(secretRead, isFalse);
  });

  test('builds a V4 Flash request with image attachment context', () {
    const context = PromptEnhancementContext(
      workflowId: 'image-edit-qwen-2511',
      targetModel: 'Qwen Image Edit 2511 FP8 Mixed',
      requestType: 'image-to-image edit',
      attachedImageCount: 2,
    );
    final request = buildDeepSeekPromptRequest(
      originalPrompt: 'Keep the subject; replace the sign with "OPEN".',
      context: context,
    );

    expect(request['model'], deepSeekPromptEnhancementModel);
    expect(request['thinking'], {'type': 'disabled'});
    final messages = request['messages']! as List<Object?>;
    final system = messages.first! as Map<String, Object?>;
    final user = messages.last! as Map<String, Object?>;
    expect(system['content'], contains(qwenImageEditModelBible.trim()));
    expect(
      system['content'],
      isNot(contains('Affirmative-description requirement')),
    );
    expect(
      system['content'],
      contains('Preserve meaningful constraints, exclusions, and negation'),
    );
    expect(system['content'], contains('Preserve character names'));
    expect(system['content'], contains('exactly as written'));
    expect(user['content'], contains('image-to-image edit'));
    expect(user['content'], contains('2 images'));
    expect(user['content'], contains('image pixels and their contents are'));
    expect(
      user['content'],
      contains(jsonEncode('Keep the subject; replace the sign with "OPEN".')),
    );
  });

  test('adds identity and style continuity rules only for storyboards', () {
    const storyboardContext = PromptEnhancementContext(
      workflowId: 'image-edit-qwen-2511',
      targetModel: 'Qwen Image Edit 2511 FP8 Mixed',
      requestType: 'image-to-image edit',
      attachedImageCount: 2,
      purpose: PromptEnhancementPurpose.storyboardPanel,
    );
    const generalContext = PromptEnhancementContext(
      workflowId: 'image-edit-qwen-2511',
      targetModel: 'Qwen Image Edit 2511 FP8 Mixed',
      requestType: 'image-to-image edit',
      attachedImageCount: 2,
    );

    String systemPrompt(PromptEnhancementContext context) {
      final request = buildDeepSeekPromptRequest(
        originalPrompt: 'Jenny takes a sip.',
        context: context,
      );
      final messages = request['messages']! as List<Object?>;
      return (messages.first! as Map<String, Object?>)['content']! as String;
    }

    final storyboardSystem = systemPrompt(storyboardContext);
    expect(storyboardSystem, contains('Storyboard-specific rules'));
    expect(storyboardSystem, contains("named character's identity"));
    expect(storyboardSystem, contains('action assignments intact'));
    expect(storyboardSystem, contains('visual language as continuity'));
    expect(storyboardSystem, contains('explicitly requests one'));
    expect(storyboardSystem, contains('requested scene itself'));
    expect(
      systemPrompt(generalContext),
      isNot(contains('Storyboard-specific')),
    );
  });

  test('derives image-conditioned context from normalized workflow inputs', () {
    final context = PromptEnhancementContext.fromWorkflow(
      workflowId: 'image-edit-qwen-2511',
      targetModel: 'Qwen Image Edit 2511 FP8 Mixed',
      input: const {
        'source_asset_id': 'source-a',
        'source_asset_id_2': 'source-b',
        'source_asset_id_3': 'source-c',
        'prompt': 'Edit the images',
      },
    );

    expect(context.requestType, 'image-to-image edit');
    expect(context.attachedImageCount, 3);
  });

  test('counts image entries in a MiniMax H3 reference manifest', () {
    final context = PromptEnhancementContext.fromWorkflow(
      workflowId: 'text-to-video-minimax-h3',
      targetModel: 'MiniMax H3',
      input: {
        'reference_manifest': jsonEncode({
          'schema_version': 1,
          'mode': 'reference_to_video',
          'references': const [
            {'kind': 'image'},
            {'kind': 'video'},
            {'kind': 'image'},
          ],
        }),
        'prompt': 'Use all of the references.',
      },
    );

    expect(context.attachedImageCount, 2);
  });

  test('carries storyboard purpose into normalized workflow context', () {
    final context = PromptEnhancementContext.fromWorkflow(
      workflowId: 'image-edit-qwen-2511',
      targetModel: 'Qwen Image Edit 2511 FP8 Mixed',
      input: const {
        'source_asset_id': 'source-a',
        'prompt': 'Jenny takes a sip.',
      },
      purpose: PromptEnhancementPurpose.storyboardPanel,
    );

    expect(context.purpose, PromptEnhancementPurpose.storyboardPanel);
  });

  test('uses LTX context for image-to-video and text-to-video', () {
    final imageToVideo = PromptEnhancementContext.fromWorkflow(
      workflowId: 'image-to-video',
      targetModel: 'LTX 2.3',
      input: const {
        'source_asset_id': 'source-a',
        'prompt': 'The subject begins walking.',
      },
    );
    final textToVideo = PromptEnhancementContext.fromWorkflow(
      workflowId: 'text-to-video-ltx',
      targetModel: 'LTX 2.3',
      input: const {'prompt': 'A train crosses the valley.'},
    );

    expect(imageToVideo.requestType, 'image-to-video');
    expect(imageToVideo.attachedImageCount, 1);
    expect(textToVideo.requestType, 'text-to-video');
    expect(textToVideo.attachedImageCount, 0);
  });

  test('sends the complete LTX guide with video enhancement requests', () {
    const context = PromptEnhancementContext(
      workflowId: 'image-to-video',
      targetModel: 'LTX 2.3',
      requestType: 'image-to-video',
      attachedImageCount: 1,
    );
    final request = buildDeepSeekPromptRequest(
      originalPrompt: 'The subject begins walking.',
      context: context,
    );
    final messages = request['messages']! as List<Object?>;
    final system = messages.first! as Map<String, Object?>;
    final user = messages.last! as Map<String, Object?>;

    expect(system['content'], contains(ltxVideoModelBible.trim()));
    expect(user['content'], contains('Request type: image-to-video'));
    expect(user['content'], contains('1 image'));
  });

  test('sends the complete MiniMax H3 guide for text-to-video', () {
    const context = PromptEnhancementContext(
      workflowId: 'text-to-video-minimax-h3',
      targetModel: 'MiniMax H3',
      requestType: 'text-to-video',
      attachedImageCount: 0,
    );
    final request = buildDeepSeekPromptRequest(
      originalPrompt: 'A chrome hummingbird wakes in a dark laboratory.',
      context: context,
    );
    final messages = request['messages']! as List<Object?>;
    final system = messages.first! as Map<String, Object?>;
    final user = messages.last! as Map<String, Object?>;

    expect(system['content'], contains(minimaxH3VideoModelBible.trim()));
    expect(system['content'], contains('integrated_multimodal_description'));
    expect(system['content'], contains('overall_soundscape'));
    expect(system['content'], contains('non_diegetic_music'));
    expect(user['content'], contains('Request type: text-to-video'));
    expect(user['content'], contains('0 images'));
  });

  test('accepts only a non-empty plain enhanced prompt', () {
    expect(
      enhancedPromptFromResponse(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '```text\nA precise prompt\n```'},
            },
          ],
        }),
      ),
      'A precise prompt',
    );
    expect(
      enhancedPromptFromResponse(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'Enhanced prompt: A precise prompt'},
            },
          ],
        }),
      ),
      'A precise prompt',
    );
    expect(enhancedPromptFromResponse('{}'), isNull);
    expect(enhancedPromptFromResponse('not-json'), isNull);
  });

  test('accepts natural constraints and negation in enhanced text', () {
    String response(String prompt) => jsonEncode({
      'choices': [
        {
          'message': {'content': prompt},
        },
      ],
    });

    for (final prompt in [
      'A clean portrait, no watermark',
      'A portrait without background clutter',
      'Avoid blurry details',
      'Do not include text',
      'negative_prompt: blur, artifacts',
      'Negative prompts: blur, artifacts',
      'A presentation free of branding',
      '\u201cA clean portrait, no watermark\u201d',
    ]) {
      expect(
        enhancedPromptFromResponse(response(prompt)),
        prompt.replaceAll(RegExp(r'^\u201C|\u201D$'), ''),
        reason: prompt,
      );
    }
    expect(
      enhancedPromptFromResponse(
        response('A notebook on a table, crisp focus, clean presentation'),
      ),
      'A notebook on a table, crisp focus, clean presentation',
    );
    expect(
      enhancedPromptFromResponse(
        response('A sign reading "NO EXIT" in clean block lettering'),
      ),
      'A sign reading "NO EXIT" in clean block lettering',
    );
  });

  group('a field whose words reach the audience', () {
    const narration = PromptEnhancementContext(
      workflowId: 'narration-create-chatterbox-tts',
      targetModel: 'Chatterbox Turbo TTS',
      requestType: 'text-to-speech narration',
      attachedImageCount: 0,
      field: 'text',
      modality: CreativeModality.speech,
    );
    const lyrics = PromptEnhancementContext(
      workflowId: 'song-create-acestep-xl-sft',
      targetModel: 'ACE-Step 1.5 Comfy Turbo / XL SFT',
      requestType: 'song lyrics',
      attachedImageCount: 0,
      field: 'lyrics',
      modality: CreativeModality.lyrics,
    );

    String systemPrompt(PromptEnhancementContext context) {
      final request = buildDeepSeekPromptRequest(
        originalPrompt: 'Do not open the valve until the light turns green.',
        context: context,
      );
      return ((request['messages']! as List<Object?>).first
              as Map<String, Object?>)['content']!
          as String;
    }

    String userPrompt(PromptEnhancementContext context) {
      final request = buildDeepSeekPromptRequest(
        originalPrompt: 'Do not open the valve until the light turns green.',
        context: context,
      );
      return ((request['messages']! as List<Object?>).last
              as Map<String, Object?>)['content']!
          as String;
    }

    test('is never held to the affirmative-description rule', () {
      for (final context in [narration, lyrics]) {
        final system = systemPrompt(context);
        expect(
          system,
          isNot(contains('Affirmative-description requirement')),
          reason: context.field,
        );
        expect(
          _flat(system),
          contains('delivered to an audience as written'),
          reason: context.field,
        );
        expect(
          _flat(system),
          contains('must survive the rewrite unchanged in meaning'),
          reason: context.field,
        );
      }
    });

    test('carries its own guide, not a neighbouring modality', () {
      expect(systemPrompt(narration), contains(chatterboxNarrationModelBible));
      expect(systemPrompt(lyrics), contains(aceStepLyricsModelBible));
    });

    test('is not told about image attachments it has none of', () {
      final user = userPrompt(narration);
      expect(user, isNot(contains('Attached images')));
      expect(_flat(user), contains("keeping the author's words"));
      expect(user, contains('Field: text'));
    });

    test('never picks up the storyboard continuity rules', () {
      const storyboardNarration = PromptEnhancementContext(
        workflowId: 'narration-create-chatterbox-tts',
        targetModel: 'Chatterbox Turbo TTS',
        requestType: 'text-to-speech narration',
        attachedImageCount: 0,
        field: 'text',
        modality: CreativeModality.speech,
        purpose: PromptEnhancementPurpose.storyboardPanel,
      );

      expect(
        systemPrompt(storyboardNarration),
        isNot(contains('Storyboard-specific')),
      );
    });

    test('response parsing keeps authored negation', () {
      String response(String prompt) => jsonEncode({
        'choices': [
          {
            'message': {'content': prompt},
          },
        ],
      });

      const script = 'Do not open the valve until the light turns green.';
      expect(enhancedPromptFromResponse(response(script)), script);
      expect(
        enhancedPromptFromResponse(
          response('[Verse]\nI never said I would go'),
        ),
        '[Verse]\nI never said I would go',
      );
    });
  });

  group('credential resolution', () {
    Workspace workspaceWith(PromptEnhancementConfig? config) => Workspace(
      id: 'workspace-1',
      name: 'Workspace',
      environment: 'dev',
      githubInstallationId: null,
      repositories: const [],
      projects: const [],
      workflows: const [],
      artifactStorage: null,
      promptEnhancement: config,
    );

    const context = PromptEnhancementContext(
      workflowId: 'image-create',
      targetModel: 'Z-Image Turbo',
      requestType: 'text-to-image generation',
      attachedImageCount: 0,
    );

    http.Client clientCapturing(List<String> authorizations) =>
        MockClient((request) async {
          authorizations.add(request.headers['authorization'] ?? '');
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'A calm studio portrait, crisp focus'},
                },
              ],
            }),
            200,
          );
        });

    test(
      'prefers a key pasted into ii-os over a Secret Manager version',
      () async {
        final authorizations = <String>[];
        var secretRead = false;
        final result =
            await DeepSeekPromptEnhancer(
              httpClient: clientCapturing(authorizations),
              secretReader: (_) async {
                secretRead = true;
                return 'sk-from-secret-manager';
              },
              storedKeyReader: (_) async => 'sk-pasted-into-ii-os',
            ).enhance(
              workspace: workspaceWith(
                const PromptEnhancementConfig(
                  enabled: true,
                  apiKeySecretVersion:
                      'projects/p/secrets/deepseek-api-key/versions/latest',
                  hasApiKey: true,
                  apiKeyLast4: '9xyz',
                ),
              ),
              originalPrompt: 'a portrait',
              context: context,
              maxPromptLength: 4000,
            );

        expect(result.status, 'enhanced');
        expect(authorizations.single, 'Bearer sk-pasted-into-ii-os');
        expect(secretRead, isFalse);
      },
    );

    test('falls back to Secret Manager when the stored key is gone', () async {
      final authorizations = <String>[];
      final result =
          await DeepSeekPromptEnhancer(
            httpClient: clientCapturing(authorizations),
            secretReader: (_) async => 'sk-from-secret-manager',
            storedKeyReader: (_) async => null,
          ).enhance(
            workspace: workspaceWith(
              const PromptEnhancementConfig(
                enabled: true,
                apiKeySecretVersion:
                    'projects/p/secrets/deepseek-api-key/versions/latest',
                hasApiKey: true,
                apiKeyLast4: '9xyz',
              ),
            ),
            originalPrompt: 'a portrait',
            context: context,
            maxPromptLength: 4000,
          );

      expect(result.status, 'enhanced');
      expect(authorizations.single, 'Bearer sk-from-secret-manager');
    });

    test('keeps the original text when no credential resolves', () async {
      final result =
          await DeepSeekPromptEnhancer(
            httpClient: MockClient((_) async => http.Response('{}', 200)),
            secretReader: (_) async => throw StateError('denied'),
            storedKeyReader: (_) async => null,
          ).enhance(
            workspace: workspaceWith(
              const PromptEnhancementConfig(
                enabled: true,
                apiKeySecretVersion:
                    'projects/p/secrets/deepseek-api-key/versions/latest',
                hasApiKey: true,
                apiKeyLast4: '9xyz',
              ),
            ),
            originalPrompt: '  a portrait  ',
            context: context,
            maxPromptLength: 4000,
          );

      expect(result.prompt, 'a portrait');
      expect(result.status, 'fallback');
      expect(result.fallbackReason, 'key_unavailable');
    });
  });

  test('metadata names the guide and whether it was written for the model', () {
    final specific = PromptEnhancementResult(
      prompt: 'x',
      status: 'enhanced',
      targetModel: 'Chatterbox Turbo TTS',
      bible: 'chatterbox-speech',
      modality: CreativeModality.speech,
    ).toMetadata();

    expect(specific['bible'], 'chatterbox-speech');
    expect(specific['modality'], 'speech');
    expect(specific['modelSpecific'], isTrue);
    expect(specific['providerModel'], deepSeekPromptEnhancementModel);
  });
}
