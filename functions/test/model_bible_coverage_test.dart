import 'package:ii_os_functions/src/creative_surface.dart';
import 'package:ii_os_functions/src/model_bibles.dart';
import 'package:test/test.dart';

/// One creative field of one shipped workflow, and the guide it must resolve to.
final class _Coverage {
  const _Coverage({
    required this.workflowId,
    required this.model,
    required this.field,
    required this.outputKind,
    required this.modality,
    required this.bible,
  });

  final String workflowId;
  final String model;
  final String field;
  final String outputKind;
  final CreativeModality modality;
  final String bible;

  @override
  String toString() => '$workflowId.$field';
}

/// Every creative field in the generation catalog ii-os ships against.
///
/// Pinned here rather than parsed from a catalog file because the catalog lives
/// in the customer's repository, not this one -- ii-os reads it over the GitHub
/// API at dispatch time. This table is the contract that ii-os believes it
/// covers, and the test below is what makes adding a workflow without a guide
/// fail loudly rather than silently fall through to a neighbouring modality.
const List<_Coverage> _catalog = [
  _Coverage(
    workflowId: 'image-create',
    model: 'Z-Image Turbo',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.image,
    bible: 'z-image',
  ),
  _Coverage(
    workflowId: 'image-create-flux2-klein',
    model: 'FLUX.2 Klein 4B',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.image,
    bible: 'flux',
  ),
  _Coverage(
    workflowId: 'image-create-qwen-2512',
    model: 'Qwen Image 2512',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.image,
    bible: 'qwen-image',
  ),
  _Coverage(
    workflowId: 'image-edit',
    model: 'Z-Image Turbo ControlNet',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.imageEdit,
    bible: 'z-image-edit',
  ),
  _Coverage(
    workflowId: 'image-inpaint',
    model: 'Z-Image Turbo ControlNet',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.inpaint,
    bible: 'z-image-inpaint',
  ),
  _Coverage(
    workflowId: 'image-edit-qwen-2511',
    model: 'Qwen Image Edit 2511 FP8 Mixed',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.imageEdit,
    bible: 'qwen-edit',
  ),
  _Coverage(
    workflowId: 'image-edit-flux2-klein',
    model: 'FLUX.2 Klein 4B Base Image Edit',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.imageEdit,
    bible: 'flux-edit',
  ),
  _Coverage(
    workflowId: 'image-inpaint-qwen',
    model: 'Qwen Image InstantX Inpaint',
    field: 'prompt',
    outputKind: 'image',
    modality: CreativeModality.inpaint,
    bible: 'qwen-inpaint',
  ),
  _Coverage(
    workflowId: 'image-to-video',
    model: 'LTX 2.3',
    field: 'prompt',
    outputKind: 'video',
    modality: CreativeModality.video,
    bible: 'ltx-video',
  ),
  _Coverage(
    workflowId: 'text-to-video-minimax-h3',
    model: 'MiniMax H3',
    field: 'prompt',
    outputKind: 'video',
    modality: CreativeModality.video,
    bible: 'minimax-h3-video',
  ),
  _Coverage(
    workflowId: 'song-create-acestep-xl-sft',
    model: 'ACE-Step 1.5 Comfy Turbo / XL SFT',
    field: 'prompt',
    outputKind: 'audio',
    modality: CreativeModality.music,
    bible: 'ace-step',
  ),
  _Coverage(
    workflowId: 'song-create-acestep-xl-sft',
    model: 'ACE-Step 1.5 Comfy Turbo / XL SFT',
    field: 'lyrics',
    outputKind: 'audio',
    modality: CreativeModality.lyrics,
    bible: 'ace-step-lyrics',
  ),
  _Coverage(
    workflowId: 'narration-create-chatterbox-tts',
    model: 'Chatterbox Turbo TTS',
    field: 'text',
    outputKind: 'audio',
    modality: CreativeModality.speech,
    bible: 'chatterbox-speech',
  ),
];

void main() {
  group('every shipped creative field is rule-grounded', () {
    for (final entry in _catalog) {
      test('$entry resolves to ${entry.bible}', () {
        final selection = modelBibleSelectionFor(
          entry.model,
          workflowId: entry.workflowId,
          field: entry.field,
          modality: creativeModalityFor(
            field: entry.field,
            workflowId: entry.workflowId,
            model: entry.model,
            outputKinds: [entry.outputKind],
          ),
        );

        expect(selection.modality, entry.modality);
        expect(selection.id, entry.bible);
        expect(
          selection.isModelSpecific,
          isTrue,
          reason: '$entry falls back to a generic guide',
        );
        expect(selection.guide.trim(), isNotEmpty);
      });
    }
  });

  test('modality is inferred from the workflow, not the field name alone', () {
    for (final entry in _catalog) {
      expect(
        creativeModalityFor(
          field: entry.field,
          workflowId: entry.workflowId,
          model: entry.model,
          outputKinds: [entry.outputKind],
        ),
        entry.modality,
        reason: entry.toString(),
      );
    }
  });

  test('a script is never rewritten under a guide for pictures', () {
    for (final entry in _catalog.where((item) => !item.modality.isDirection)) {
      final guide = modelBibleSelectionFor(
        entry.model,
        workflowId: entry.workflowId,
        field: entry.field,
      ).guide.toLowerCase();

      expect(guide, isNot(contains('shot scale')), reason: entry.toString());
      expect(guide, isNot(contains('depth of field')), reason: '$entry');
      expect(
        guide,
        anyOf(contains('sung'), contains('spoken')),
        reason: '$entry',
      );
    }
  });

  test('every creative input the catalog uses has a label', () {
    for (final entry in _catalog) {
      expect(
        creativeInputLabels,
        contains(entry.field),
        reason:
            '${entry.field} carries creative intent but no enhance affordance '
            'would be offered for it',
      );
    }
  });
}
