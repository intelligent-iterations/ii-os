import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/image_edit_selection.dart';
import 'package:ii_os/models/models.dart';

void main() {
  test('selects one enabled image-edit model by default', () {
    final templates = [
      _template('edit-a', 'Model A'),
      _template('edit-b', 'Model B'),
      _template('inpaint-a', 'Model A', workflowId: 'image-inpaint'),
    ];

    final targets = imageEditSubmissionTargets(
      templates: templates,
      mode: ImageEditMode.revision,
      selectedId: 'edit-b',
      useAll: false,
    );

    expect(targets.map((item) => item.id), ['edit-b']);
  });

  test('use all includes every enabled model for the selected mode', () {
    final templates = [
      _template('edit-a', 'Model A'),
      _template('edit-b', 'Model B', workflowId: 'image-edit-qwen-2511'),
      _template('edit-disabled', 'Model C', enabled: false),
      _template('inpaint-a', 'Model A', workflowId: 'image-inpaint'),
    ];

    final targets = imageEditSubmissionTargets(
      templates: templates,
      mode: ImageEditMode.revision,
      selectedId: 'edit-a',
      useAll: true,
    );

    expect(targets.map((item) => item.id), ['edit-a', 'edit-b']);
  });

  test('comparison estimate uses the slowest selected image workflow', () {
    final targets = [
      _template('edit-fast', 'Fast', baselineRuntimeSeconds: 45),
      _template('edit-slow', 'Slow', baselineRuntimeSeconds: 90),
    ];

    final estimate = imageEditRuntimeEstimate(targets);

    expect(estimate?.estimatedSeconds, 90);
  });

  test('hides legacy Z-Image inpaint and defaults to Qwen inpaint', () {
    final templates = [
      _template('edit-a', 'Model A'),
      _template('z-inpaint', 'Z-Image', workflowId: 'image-inpaint'),
      _template('qwen-inpaint', 'Qwen', workflowId: 'image-inpaint-qwen'),
    ];

    final available = imageEditTemplatesForMode(
      templates,
      ImageEditMode.inpaint,
    );

    final targets = imageEditSubmissionTargets(
      templates: templates,
      mode: ImageEditMode.inpaint,
      selectedId: null,
      useAll: true,
    );

    expect(available.map((item) => item.id), ['qwen-inpaint']);
    expect(targets.map((item) => item.id), ['qwen-inpaint']);
  });

  test('falls back to the first enabled model after a catalog change', () {
    final selected = selectedImageEditTemplate(
      templates: [
        _template('edit-disabled', 'Model A', enabled: false),
        _template('edit-b', 'Model B'),
      ],
      mode: ImageEditMode.revision,
      selectedId: 'missing',
    );

    expect(selected?.id, 'edit-b');
  });

  test('adds optional source images only to the Qwen edit contract', () {
    final qwenInput = imageEditInputForTarget(
      target: _template(
        'edit-qwen',
        'Qwen',
        workflowId: 'image-edit-qwen-2511',
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
      ),
      baseInput: {'source_asset_id': 'source-a'},
      referenceAssetIds: ['source-b', 'source-c'],
    );
    final standardInput = imageEditInputForTarget(
      target: _template(
        'edit-standard',
        'Standard',
        inputs: const {
          'source_asset_id': WorkflowInputModel(type: 'string', required: true),
        },
      ),
      baseInput: {'source_asset_id': 'source-a'},
      referenceAssetIds: ['source-b', 'source-c'],
    );

    expect(qwenInput['source_asset_id_2'], 'source-b');
    expect(qwenInput['source_asset_id_3'], 'source-c');
    expect(standardInput, isNot(contains('source_asset_id_2')));
  });

  test('reference slots and source guidance come from declared inputs', () {
    final flux = _template(
      'edit-flux',
      'Flux',
      workflowId: 'image-edit-flux2-klein',
      inputs: const {
        'source_asset_id': WorkflowInputModel(type: 'string', required: true),
        'source_asset_id_2': WorkflowInputModel(
          type: 'string',
          required: false,
        ),
      },
    );
    final zImage = _template(
      'edit-z',
      'Z-Image',
      inputs: const {
        'source_asset_id': WorkflowInputModel(type: 'string', required: true),
        'control_strength': WorkflowInputModel(type: 'number', required: true),
      },
    );

    expect(imageEditReferenceSlots(flux), 1);
    expect(imageEditSupportsSourceAdherence(flux), isFalse);
    expect(imageEditSupportsSourceAdherence(zImage), isTrue);
  });

  test('comparison exposes only the largest declared reference contract', () {
    final targets = [
      _template(
        'edit-flux',
        'Flux',
        inputs: const {
          'source_asset_id': WorkflowInputModel(type: 'string', required: true),
          'source_asset_id_2': WorkflowInputModel(
            type: 'string',
            required: false,
          ),
        },
      ),
      _template(
        'edit-qwen',
        'Qwen',
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
      ),
    ];

    expect(maximumImageEditReferenceSlots(targets), 2);
  });

  test('multiple selected areas require a declared mask-regions input', () {
    final single = _template('single', 'Single');
    final multiple = _template(
      'multiple',
      'Multiple',
      inputs: const {
        'mask_regions': WorkflowInputModel(type: 'string', required: false),
      },
    );

    expect(imageEditAllowsMultipleRegions(single), isFalse);
    expect(imageEditAllowsMultipleRegions(multiple), isTrue);
  });

  test('submits only inputs declared by the target workflow', () {
    final target = _template(
      'edit-qwen',
      'Qwen',
      workflowId: 'image-edit-qwen-2511',
      inputs: const {
        'mode': WorkflowInputModel(type: 'string', required: true),
        'source_asset_id': WorkflowInputModel(type: 'string', required: true),
        'prompt': WorkflowInputModel(type: 'string', required: true),
      },
    );

    final input = imageEditInputForTarget(
      target: target,
      baseInput: const {
        'mode': 'edit',
        'source_asset_id': 'source-a',
        'prompt': 'change it',
        'control_strength': 1.25,
        'seed': 42,
      },
      referenceAssetIds: const [],
    );

    expect(input, {
      'mode': 'edit',
      'source_asset_id': 'source-a',
      'prompt': 'change it',
    });
  });

  test('adds combined mask regions only when the target declares them', () {
    const masks = [
      Rect.fromLTWH(.1, .2, .2, .15),
      Rect.fromLTWH(.65, .55, .1, .2),
    ];
    final qwenInput = imageEditInputForTarget(
      target: _template(
        'inpaint-qwen',
        'Qwen',
        workflowId: 'image-inpaint-qwen',
        inputs: const {
          'mask_regions': WorkflowInputModel(type: 'string', required: false),
        },
      ),
      baseInput: {'source_asset_id': 'source-a'},
      referenceAssetIds: const [],
      maskRegions: masks,
    );
    final standardInput = imageEditInputForTarget(
      target: _template(
        'inpaint-standard',
        'Standard',
        workflowId: 'image-inpaint',
      ),
      baseInput: {'source_asset_id': 'source-a'},
      referenceAssetIds: const [],
      maskRegions: masks,
    );

    expect(
      qwenInput['mask_regions'],
      '[[0.1,0.2,0.2,0.15],[0.65,0.55,0.1,0.2]]',
    );
    expect(standardInput, isNot(contains('mask_regions')));
  });
}

WorkflowTemplateModel _template(
  String id,
  String model, {
  String workflowId = 'image-edit',
  bool enabled = true,
  Map<String, WorkflowInputModel> inputs = const {},
  int? baselineRuntimeSeconds,
}) => WorkflowTemplateModel(
  id: id,
  workflowId: workflowId,
  version: '1',
  displayName: '$model Edit',
  model: model,
  repository: 'acme/$id',
  enabled: enabled,
  disabledReason: enabled ? '' : 'Disabled',
  inputs: inputs,
  runtimeEstimates: baselineRuntimeSeconds == null
      ? const []
      : [
          WorkflowRuntimeEstimateModel(
            selector: const {},
            durationInput: '',
            baselineOutputSeconds: 0,
            baselineRuntimeSeconds: baselineRuntimeSeconds,
            hardware: '24 GB GPU',
            measuredAt: '2026-08-24',
          ),
        ],
);
