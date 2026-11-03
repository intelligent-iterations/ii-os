import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/image_workflow_capabilities.dart';
import 'package:ii_os/models/models.dart';

void main() {
  test('normalizes declared image shapes for the shared form', () {
    expect(generatedImageSeed(DateTime.fromMicrosecondsSinceEpoch(9)), '9');
    expect(initialImageAspectRatio(const []), '1:1');
    expect(initialImageAspectRatio(const ['3:2', '1:1']), '3:2');
    expect(imageAspectDimensions('3:2'), (width: 3, height: 2));
    expect(imageAspectDimensions('invalid'), (width: 1, height: 1));
  });

  test('separates text generation from generation with references', () {
    final text = _template('image-create-qwen', const {
      'prompt': WorkflowInputModel(type: 'string', required: true),
    });
    final reference = _template('image-create-reference-qwen', const {
      'source_asset_id': WorkflowInputModel(type: 'string', required: true),
      'source_asset_id_2': WorkflowInputModel(type: 'string', required: false),
      'source_asset_id_3': WorkflowInputModel(type: 'string', required: false),
    });

    expect(
      imageGenerationTemplatesForMode([
        text,
        reference,
      ], ImageGenerationMode.prompt),
      [text],
    );
    expect(
      imageGenerationTemplatesForMode([
        text,
        reference,
      ], ImageGenerationMode.references),
      [reference],
    );
    expect(imageCapabilities(reference).maximumReferenceImages, 3);
  });

  test('derives controls and ratios from the declared workflow contract', () {
    final template = _template('image-create', const {
      'aspect_ratio': WorkflowInputModel(
        type: 'string',
        required: true,
        allowedValues: ['1:1', '3:2', '2:3'],
      ),
      'control_strength': WorkflowInputModel(type: 'number', required: true),
    });
    final capabilities = imageCapabilities(template);

    expect(capabilities.aspectRatios, ['1:1', '3:2', '2:3']);
    expect(capabilities.supportsSourceAdherence, isTrue);
  });

  test('does not invent gaps in an ordered reference contract', () {
    final template = _template('image-create-reference', const {
      'source_asset_id': WorkflowInputModel(type: 'string', required: true),
      'source_asset_id_3': WorkflowInputModel(type: 'string', required: false),
    });

    expect(imageCapabilities(template).maximumReferenceImages, 1);
  });
}

WorkflowTemplateModel _template(
  String workflowId,
  Map<String, WorkflowInputModel> inputs,
) => WorkflowTemplateModel(
  id: 'acme/media#$workflowId',
  workflowId: workflowId,
  version: '1',
  displayName: workflowId,
  model: workflowId,
  repository: 'acme/media',
  enabled: true,
  disabledReason: '',
  inputs: inputs,
);
