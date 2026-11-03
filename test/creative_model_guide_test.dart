import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/creative_model_guide.dart';
import 'package:ii_os/models/models.dart';

WorkflowTemplateModel _template(
  String workflowId, {
  String model = 'A Model',
}) => WorkflowTemplateModel(
  id: workflowId,
  workflowId: workflowId,
  version: '1',
  displayName: model,
  model: model,
  repository: 'acme/example',
  enabled: true,
  disabledReason: '',
);

/// Every generation workflow the shipped catalog offers, by the id ii-os keys
/// its guide on.
///
/// Pinned here rather than read from the catalog, because the catalog lives in
/// the customer's repository. This list is what ii-os believes it can explain,
/// and the test below is what makes adding a workflow without a sentence fail
/// loudly instead of shipping a card with a blank line where the reason goes.
const _shipped = [
  'image-create',
  'image-create-flux2-klein',
  'image-create-qwen-2512',
  'image-create-reference-flux2-klein',
  'image-create-reference-qwen-2511',
  'image-edit',
  'image-edit-flux2-klein',
  'image-edit-qwen-2511',
  'image-inpaint',
  'image-inpaint-qwen',
  'image-to-video',
  'text-to-video-minimax-h3',
  'song-create-acestep-xl-sft',
  'narration-create-chatterbox-tts',
];

void main() {
  group('creativeModelGuide', () {
    test('explains every workflow the shipped catalog offers', () {
      for (final workflowId in _shipped) {
        final guide = creativeModelGuide(_template(workflowId));
        expect(
          guide.summary,
          isNotEmpty,
          reason: '$workflowId has no sentence saying what it is for',
        );
        expect(
          guide.summary.endsWith('.'),
          isTrue,
          reason: '$workflowId reads as a fragment, not a sentence',
        );
      }
    });

    test('distinguishes the three image models from one another', () {
      final summaries = {
        for (final id in const [
          'image-create',
          'image-create-flux2-klein',
          'image-create-qwen-2512',
        ])
          creativeModelGuide(_template(id)).summary,
      };
      expect(summaries.length, 3);
    });

    test('names what makes each image model the right choice', () {
      for (final id in const [
        'image-create',
        'image-create-flux2-klein',
        'image-create-qwen-2512',
      ]) {
        expect(creativeModelGuide(_template(id)).facts, isNotEmpty);
      }
    });

    test('reference facts come from the workflow inputs', () {
      final template = WorkflowTemplateModel(
        id: 'qwen',
        workflowId: 'image-edit-qwen-2511',
        version: '1',
        displayName: 'Qwen',
        model: 'Qwen',
        repository: 'acme/example',
        enabled: true,
        disabledReason: '',
        inputs: const {
          'source_asset_id': WorkflowInputModel(type: 'string', required: true),
          'source_asset_id_2': WorkflowInputModel(
            type: 'string',
            required: false,
          ),
          'source_asset_id_3': WorkflowInputModel(
            type: 'string',
            required: false,
          ),
        },
      );

      expect(creativeModelFacts(template), contains('Up to 3 images'));
      expect(
        creativeModelFacts(
          _template('image-edit-qwen-2511'),
        ).join(' ').toLowerCase(),
        isNot(contains('reference')),
      );
    });

    test('an unknown workflow still gets a sentence, from its own name', () {
      final guide = creativeModelGuide(
        _template('image-create-unreleased', model: 'Some New Checkpoint'),
      );
      expect(guide.summary, isNotEmpty);
      expect(guide.summary, contains('Some New Checkpoint'));
    });
  });
}
