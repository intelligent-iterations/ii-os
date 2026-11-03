import 'package:ii_os_functions/src/creative_surface.dart';
import 'package:ii_os_functions/src/model_bible_chatterbox.dart';
import 'package:ii_os_functions/src/model_bible_qwen.dart';
import 'package:ii_os_functions/src/model_bibles.dart';
import 'package:test/test.dart';

void main() {
  test('every guide the resolver can reach is editable', () {
    // A selection id is either a catalog id or a composition of them. Anything
    // else would be a guide the enhancer applies and no administrator can see.
    const compositions = {
      'qwen-inpaint': ['qwen-edit', 'inpainting'],
      'flux-inpaint': ['flux', 'inpainting'],
      'z-image-inpaint': ['z-image', 'inpainting'],
      'generic-inpaint': ['generic-image-edit', 'inpainting'],
      'flux-edit': ['flux', 'generic-image-edit'],
      'z-image-edit': ['z-image', 'generic-image-edit'],
    };
    const models = [
      ('Z-Image Turbo', 'image-create'),
      ('FLUX.2 Klein 4B', 'image-create-flux2-klein'),
      ('Qwen Image 2512', 'image-create-qwen-2512'),
      ('Z-Image Turbo ControlNet', 'image-edit'),
      ('Z-Image Turbo ControlNet', 'image-inpaint'),
      ('Qwen Image Edit 2511 FP8 Mixed', 'image-edit-qwen-2511'),
      ('FLUX.2 Klein 4B Base Image Edit', 'image-edit-flux2-klein'),
      ('Qwen Image InstantX Inpaint', 'image-inpaint-qwen'),
      ('LTX 2.3', 'image-to-video'),
      ('MiniMax H3', 'text-to-video-minimax-h3'),
      ('ACE-Step 1.5', 'song-create-acestep-xl-sft'),
      ('Chatterbox Turbo TTS', 'narration-create-chatterbox-tts'),
      ('unmatched-model', 'unknown-workflow'),
    ];

    for (final (model, workflowId) in models) {
      for (final field in ['prompt', 'lyrics', 'text']) {
        final id = modelBibleSelectionFor(
          model,
          workflowId: workflowId,
          field: field,
        ).id;
        final sources = compositions[id] ?? [id];
        for (final source in sources) {
          expect(
            promptGuidesById,
            contains(source),
            reason: '$model/$workflowId/$field resolves to an uneditable $id',
          );
        }
      }
    }
  });

  test('a catalog entry names itself and carries text', () {
    expect(promptGuideCatalog, isNotEmpty);
    final ids = promptGuideCatalog.map((guide) => guide.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate guide id');
    for (final guide in promptGuideCatalog) {
      expect(guide.id, matches(RegExp(r'^[a-z0-9-]+$')));
      expect(guide.label.trim(), isNotEmpty);
      expect(guide.summary.trim(), isNotEmpty);
      expect(guide.body.trim().length, greaterThan(100));
      expect(
        guide.body.trim().length,
        lessThanOrEqualTo(promptGuideMaxLength),
        reason: '${guide.id} ships longer than an edit may be',
      );
    }
  });

  group('PromptGuideLibrary', () {
    test('an edit replaces the shipped text', () {
      const library = PromptGuideLibrary({'chatterbox-speech': 'Say it once.'});

      expect(library.body('chatterbox-speech'), 'Say it once.');
      expect(library.isCustomized('chatterbox-speech'), isTrue);
      expect(library.isCustomized('ace-step'), isFalse);
      expect(library.body('ace-step'), promptGuidesById['ace-step']!.body);
    });

    test(
      'blank and unknown entries fall back rather than blanking a guide',
      () {
        const library = PromptGuideLibrary({
          'chatterbox-speech': '   ',
          'not-a-guide': 'ignored',
        });

        expect(
          library.body('chatterbox-speech'),
          chatterboxNarrationModelBible,
        );
        expect(library.isCustomized('chatterbox-speech'), isFalse);
        expect(library.isCustomized('not-a-guide'), isFalse);
        expect(library.body('not-a-guide'), isEmpty);
      },
    );

    test('the resolver sends the edited text and flags the run', () {
      const library = PromptGuideLibrary({
        'chatterbox-speech': 'Read it exactly as written.',
      });

      final narration = modelBibleSelectionFor(
        'Chatterbox Turbo TTS',
        workflowId: 'narration-create-chatterbox-tts',
        field: 'text',
        library: library,
      );

      expect(narration.guide, 'Read it exactly as written.');
      expect(narration.customized, isTrue);
      expect(narration.modality, CreativeModality.speech);
    });

    test('a composed guide reports customization from either half', () {
      const editEdited = PromptGuideLibrary({'qwen-edit': 'Edit rules.'});
      const inpaintEdited = PromptGuideLibrary({'inpainting': 'Fill rules.'});

      final fromFamily = modelBibleSelectionFor(
        'Qwen Image InstantX Inpaint',
        workflowId: 'image-inpaint-qwen',
        library: editEdited,
      );
      final fromAddendum = modelBibleSelectionFor(
        'Qwen Image InstantX Inpaint',
        workflowId: 'image-inpaint-qwen',
        library: inpaintEdited,
      );

      expect(fromFamily.customized, isTrue);
      expect(fromFamily.guide, contains('Edit rules.'));
      expect(fromFamily.guide, contains(inpaintingModelBible.trim()));
      expect(fromAddendum.customized, isTrue);
      expect(fromAddendum.guide, contains(qwenImageEditModelBible.trim()));
      expect(fromAddendum.guide, contains('Fill rules.'));
    });

    test('defaults leave every guide untouched', () {
      expect(PromptGuideLibrary.defaults.isEmpty, isTrue);
      for (final guide in promptGuideCatalog) {
        expect(PromptGuideLibrary.defaults.isCustomized(guide.id), isFalse);
        expect(PromptGuideLibrary.defaults.body(guide.id), guide.body);
      }
    });
  });
}
