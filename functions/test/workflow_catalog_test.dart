import 'dart:io';

import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workflow_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('WorkflowCatalog', () {
    test('parses the repository ii-os media catalog', () {
      final catalogPath =
          Platform.environment['II_OS_TEST_CATALOG_PATH'] ??
          'test/fixtures/example-catalog.yaml';
      final catalog = WorkflowCatalog.parse(
        repository: 'acme-co/example-app',
        repositoryId: 1,
        ref: 'dev',
        sha: 'abc123',
        content: File(catalogPath).readAsStringSync(),
      );

      final imageWorkflow = catalog.find('image-create');
      expect(imageWorkflow, isNotNull);
      expect(
        imageWorkflow!.dispatchWorkflow,
        '.github/workflows/z-image-turbo-text-to-image.yml',
      );
      expect(imageWorkflow.inputs, contains('prompt'));
      expect(imageWorkflow.inputs['prompt']!.maxLength, 60000);
      expect(imageWorkflow.inputs, contains('aspect_ratio'));
      expect(
        imageWorkflow.inputs['aspect_ratio']!.allowedValues,
        containsAll(const ['1:1', '3:2', '2:3']),
      );
      expect(imageWorkflow.inputs, contains('seed'));
      expect(imageWorkflow.outputs.single.kind, 'image');
      expect(imageWorkflow.workType, JobWorkType.content);
      expect(imageWorkflow.outputs.single.contentTypes, contains('image/png'));

      final editWorkflow = catalog.find('image-edit');
      expect(editWorkflow, isNotNull);
      expect(editWorkflow!.model, 'Z-Image Turbo ControlNet');
      expect(
        editWorkflow.dispatchWorkflow,
        '.github/workflows/z-image-edit.yml',
      );
      expect(editWorkflow.inputs, contains('source_asset_id'));
      expect(editWorkflow.inputs, contains('control_strength'));
      expect(editWorkflow.inputs, isNot(contains('mask_x')));

      final inpaintWorkflow = catalog.find('image-inpaint');
      expect(inpaintWorkflow, isNotNull);
      expect(
        inpaintWorkflow!.dispatchWorkflow,
        '.github/workflows/z-image-edit.yml',
      );
      expect(
        inpaintWorkflow.inputs.keys,
        containsAll(const [
          'source_asset_id',
          'mask_x',
          'mask_y',
          'mask_width',
          'mask_height',
        ]),
      );
      expect(inpaintWorkflow.inputs, isNot(contains('source_asset_id_2')));

      final qwenEditWorkflow = catalog.find('image-edit-qwen-2511');
      expect(qwenEditWorkflow, isNotNull);
      expect(qwenEditWorkflow!.model, 'Qwen Image Edit 2511 FP8 Mixed');
      expect(
        qwenEditWorkflow.dispatchWorkflow,
        '.github/workflows/qwen-image-edit.yml',
      );
      expect(
        qwenEditWorkflow.inputs.keys,
        containsAll(const [
          'source_asset_id',
          'source_asset_id_2',
          'source_asset_id_3',
        ]),
      );
      expect(qwenEditWorkflow.inputs['source_asset_id_2']!.required, isFalse);

      final qwenInpaintWorkflow = catalog.find('image-inpaint-qwen');
      expect(qwenInpaintWorkflow, isNotNull);
      expect(
        qwenInpaintWorkflow!.inputs.keys,
        containsAll(const [
          'source_asset_id',
          'mask_x',
          'mask_y',
          'mask_regions',
        ]),
      );
      expect(qwenInpaintWorkflow.inputs['mask_regions']!.maxLength, 4096);

      final videoWorkflow = catalog.find('image-to-video');
      expect(videoWorkflow, isNotNull);
      expect(videoWorkflow!.inputs, contains('source_asset_id'));
      expect(videoWorkflow.inputs, contains('orientation'));
      expect(videoWorkflow.inputs, contains('fps'));
      expect(videoWorkflow.inputs['duration_seconds']!.minimum, 2);
      expect(videoWorkflow.inputs['duration_seconds']!.maximum, 20);
      expect(videoWorkflow.inputs['duration_seconds']!.defaultNumber, 5);

      final h3Workflow = catalog.find('text-to-video-minimax-h3');
      expect(h3Workflow, isNotNull);
      expect(h3Workflow!.model, 'MiniMax H3');
      expect(
        h3Workflow.dispatchWorkflow,
        '.github/workflows/minimax-h3-text-to-video.yml',
      );
      expect(h3Workflow.inputs, isNot(contains('source_asset_id')));
      expect(h3Workflow.inputs['prompt']!.maxLength, 7000);
      expect(
        h3Workflow.inputs.keys,
        containsAll(const [
          'duration_seconds',
          'orientation',
          'fps',
          'performance_mode',
          'generation_mode',
          'reference_manifest',
          'edit_operation',
          'identity_replacement_consent',
        ]),
      );
      expect(h3Workflow.inputs['generation_mode']!.required, isTrue);
      expect(h3Workflow.inputs['reference_manifest']!.maxLength, 30000);
      expect(h3Workflow.inputs['edit_operation']!.required, isFalse);
      expect(
        h3Workflow.inputs['identity_replacement_consent']!.required,
        isFalse,
      );
      expect(h3Workflow.inputs['duration_seconds']!.minimum, 4);
      expect(h3Workflow.inputs['duration_seconds']!.maximum, 15);
      expect(h3Workflow.inputs['duration_seconds']!.defaultNumber, 15);
      expect(h3Workflow.runtimeEstimates, hasLength(2));
      expect(
        h3Workflow.runtimeEstimateFor(const {
          'duration_seconds': '15',
          'performance_mode': 'quality',
        }),
        containsPair('estimatedSeconds', 1953),
      );
      expect(
        h3Workflow.runtimeEstimateFor(const {
          'duration_seconds': '5',
          'performance_mode': 'turbo',
        }),
        containsPair('estimatedSeconds', 300),
      );
      expect(h3Workflow.outputs.single.kind, 'video');

      final songWorkflow = catalog.find('song-create-acestep-xl-sft');
      expect(songWorkflow, isNotNull);
      expect(songWorkflow!.model, 'ACE-Step 1.5 Comfy Turbo / XL SFT');
      expect(songWorkflow.inputs, contains('lyrics'));
      expect(songWorkflow.inputs, contains('instrumental'));
      expect(songWorkflow.inputs, contains('duration_seconds'));
      expect(songWorkflow.inputs, contains('generation_profile'));
      expect(songWorkflow.outputs.single.kind, 'audio');
      expect(songWorkflow.outputs.single.contentTypes, contains('audio/mpeg'));

      final narrationWorkflow = catalog.find('narration-create-chatterbox-tts');
      expect(narrationWorkflow, isNotNull);
      expect(narrationWorkflow!.model, 'Chatterbox Turbo TTS');
      expect(
        narrationWorkflow.dispatchWorkflow,
        '.github/workflows/narration-generation.yml',
      );
      expect(narrationWorkflow.inputs, contains('text'));
      expect(narrationWorkflow.inputs['text']!.maxLength, 6000);
      expect(narrationWorkflow.inputs, contains('voice_model'));
      expect(narrationWorkflow.inputs, contains('voice_reference_asset_id'));
      expect(narrationWorkflow.inputs, contains('voice_clone_consent'));
      expect(narrationWorkflow.outputs.single.kind, 'audio');
      expect(
        narrationWorkflow.outputs.single.contentTypes,
        contains('audio/wav'),
      );
    });

    test('parses every generation id the dashboard dispatches', () {
      final catalog = WorkflowCatalog.parse(
        repository: 'acme-co/example-app',
        repositoryId: 1,
        ref: 'dev',
        sha: 'abc123',
        content: File('test/fixtures/example-catalog.yaml').readAsStringSync(),
      );

      final upscale = catalog.find('seedvr2-video-upscale')!;
      expect(
        upscale.dispatchWorkflow,
        '.github/workflows/seedvr2-video-upscale.yml',
      );
      expect(upscale.inputs['target_resolution']!.minimum, 1080);
      expect(upscale.inputs['quality_preset']!.allowedValues, ['quality']);
      expect(upscale.inputs['preserve_audio']!.required, isTrue);
      expect(upscale.outputs.single.contentTypes, ['video/mp4']);

      for (final id in const [
        'image-edit-flux2-klein',
        'image-create-reference-flux2-klein',
      ]) {
        final flux = catalog.find(id)!;
        expect(
          flux.dispatchWorkflow,
          '.github/workflows/flux2-klein-image-edit.yml',
          reason: id,
        );
        expect(flux.inputs.keys, containsAll(['source_asset_id_2', 'prompt']));
        expect(flux.inputs, isNot(contains('source_asset_id_3')), reason: id);
        expect(flux.outputs.single.kind, 'image', reason: id);
      }

      final reference = catalog.find('image-create-reference-qwen-2511')!;
      expect(
        reference.dispatchWorkflow,
        '.github/workflows/qwen-image-edit.yml',
      );
      expect(reference.inputs['mode']!.allowedValues, ['edit']);
      expect(reference.inputs, contains('source_asset_id_3'));

      final classification = catalog.find('classification-open-jev-9b')!;
      expect(classification.inputs.keys, ['state', 'questions']);
      expect(classification.outputs.single.kind, 'decisions');
      expect(classification.outputs.single.contentTypes, ['application/json']);
      expect(classification.outputs.single.maxBytes, 1048576);

      final render = catalog.find('video-editor-render')!;
      expect(render.inputs.keys, ['render_manifest']);
      expect(render.inputs['render_manifest']!.maxLength, 60000);
      expect(
        render.outputs.single.contentTypes,
        containsAll(['video/mp4', 'video/webm']),
      );
      expect(
        render.validateInputs(const {'render_manifest': '{"version":1}'}),
        {'render_manifest': '{"version":1}'},
      );
    });

    test('workflow kit binds each mobile update to its wrapper workflow', () {
      final catalog = WorkflowCatalog.parse(
        repository: 'acme-co/example-app',
        repositoryId: 2,
        ref: 'main',
        sha: 'abc123',
        content: File(
          '../examples/implementation/.ii-os/catalog.yaml',
        ).readAsStringSync(),
      );

      // The app dispatches `<repository>#mobile-update-{android,ios}`.
      final android = catalog.find('mobile-update-android')!;
      final ios = catalog.find('mobile-update-ios')!;
      expect(
        android.dispatchWorkflow,
        '.github/workflows/mobile-update-android.yml',
      );
      expect(ios.dispatchWorkflow, '.github/workflows/mobile-update-ios.yml');
      for (final workflow in [android, ios]) {
        expect(workflow.inputs, isEmpty);
        expect(workflow.workType, JobWorkType.runtime);
        expect(workflow.validateInputs(const {}), isEmpty);
        expect(
          File(
            '../examples/implementation/${workflow.dispatchWorkflow}',
          ).existsSync(),
          isTrue,
          reason: workflow.dispatchWorkflow,
        );
      }
    });

    test('parses a bounded catalog and validates dispatch inputs', () {
      final catalog = WorkflowCatalog.parse(
        repository: 'acme/media',
        repositoryId: 12345,
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog,
      );

      expect(catalog.repository, 'acme/media');
      expect(catalog.repositoryId, 12345);
      expect(catalog.workflows, hasLength(2));
      final workflow = catalog.find('image-create')!;
      expect(workflow.model, 'Example Image Model');
      expect(workflow.workType, JobWorkType.content);
      expect(workflow.dispatchWorkflow, '.github/workflows/image-create.yaml');
      expect(
        workflow.validateInputs({
          'prompt': '  a product photo  ',
          'aspect_ratio': '1:1',
          'seed': 42,
        }),
        {'prompt': 'a product photo', 'aspect_ratio': '1:1', 'seed': '42'},
      );
    });

    test('accepts supported workflow contract version 2', () {
      final catalog = WorkflowCatalog.parse(
        repository: 'acme/media',
        repositoryId: 12345,
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog.replaceFirst(
          'contract_version: 1',
          'contract_version: 2',
        ),
      );

      expect(catalog.find('image-create')!.contractVersion, 2);
    });

    test('rejects unsupported future workflow contract versions', () {
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          repositoryId: 12345,
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst(
            'contract_version: 1',
            'contract_version: 3',
          ),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
    });

    test('accepts bounded work types and rejects unknown values', () {
      final runtimeCatalog = WorkflowCatalog.parse(
        repository: 'acme/media',
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog.replaceFirst(
          '    model: Example Image Model',
          '    model: Example Image Model\n    work_type: host',
        ),
      );
      expect(runtimeCatalog.find('image-create')!.workType, JobWorkType.host);

      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst(
            '    model: Example Image Model',
            '    model: Example Image Model\n    work_type: mystery',
          ),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
    });

    test('round trips the stored catalog representation', () {
      final catalog = WorkflowCatalog.parse(
        repository: 'acme/media',
        repositoryId: 12345,
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog,
      );

      final restored = WorkflowCatalog.fromJson(catalog.toJson());

      expect(restored.repository, catalog.repository);
      expect(restored.repositoryId, catalog.repositoryId);
      expect(restored.ref, catalog.ref);
      expect(
        restored.workflows.first.toJson(),
        catalog.workflows.first.toJson(),
      );
    });

    test('rejects undeclared and missing inputs', () {
      final workflow = WorkflowCatalog.parse(
        repository: 'acme/media',
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog,
      ).find('image-create')!;

      expect(
        () => workflow.validateInputs({'prompt': 'ok', 'command': 'rm -rf'}),
        throwsA(_apiError('invalid_job_input')),
      );
      expect(
        () => workflow.validateInputs({'aspect_ratio': '1:1'}),
        throwsA(_apiError('invalid_job_input')),
      );
    });

    test('enforces catalog-declared numeric bounds', () {
      final workflow = WorkflowCatalog.parse(
        repository: 'acme/media',
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog,
      ).find('image-to-video')!;

      expect(workflow.inputs['duration_seconds']!.minimum, 2);
      expect(workflow.inputs['duration_seconds']!.maximum, 20);
      expect(workflow.inputs['duration_seconds']!.defaultNumber, 5);
      expect(
        workflow.validateInputs({
          'source_image_url': 'https://example.com/source.png',
          'prompt': 'move',
          'duration_seconds': 8,
        })['duration_seconds'],
        '8',
      );
      expect(
        () => workflow.validateInputs({
          'source_image_url': 'https://example.com/source.png',
          'prompt': 'move',
          'duration_seconds': 21,
        }),
        throwsA(_apiError('invalid_job_input')),
      );
    });

    test('rejects unsafe workflow paths and reserved request inputs', () {
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst(
            '.github/workflows/image-create.yaml',
            '../outside.yaml',
          ),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst('prompt:\n', 'ii_request_id:\n'),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
    });

    test('rejects string input limits above the dispatch ceiling', () {
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst(
            'max_length: 8000',
            'max_length: 60001',
          ),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
    });

    test('enforces a bounded string vocabulary', () {
      final workflow = WorkflowCatalog.parse(
        repository: 'acme/media',
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog,
      ).find('image-create')!;

      expect(
        workflow.validateInputs({
          'prompt': 'sky',
          'aspect_ratio': '16:9',
        })['aspect_ratio'],
        '16:9',
      );
      expect(
        () =>
            workflow.validateInputs({'prompt': 'sky', 'aspect_ratio': '21:9'}),
        throwsA(_apiError('invalid_job_input')),
      );
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst(
            'allowed_values: ["1:1", "16:9"]',
            'allowed_values: ["1:1", "1:1"]',
          ),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
    });

    test('rejects invalid numeric ranges and defaults', () {
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst('minimum: 2', 'minimum: 21'),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst('default: 5', 'default: 21'),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
    });

    test('rejects runtime estimates bound to undeclared inputs', () {
      expect(
        () => WorkflowCatalog.parse(
          repository: 'acme/media',
          ref: 'dev',
          sha: 'abc123',
          content: _validCatalog.replaceFirst(
            '    outputs:\n      - kind: video',
            '    runtime_estimates:\n'
                '      - selector:\n'
                '          missing_profile: fast\n'
                '        duration_input: duration_seconds\n'
                '        baseline_output_seconds: 5\n'
                '        baseline_runtime_seconds: 60\n'
                '        hardware: Example GPU\n'
                '        measured_at: 2026-08-15\n'
                '    outputs:\n'
                '      - kind: video',
          ),
        ),
        throwsA(_apiError('workflow_catalog_invalid')),
      );
    });

    test('accepts a fixed runtime estimate without a duration input', () {
      final catalog = WorkflowCatalog.parse(
        repository: 'acme/media',
        ref: 'dev',
        sha: 'abc123',
        content: _validCatalog.replaceFirst(
          '    outputs:\n      - kind: image',
          '    runtime_estimates:\n'
              '      - baseline_runtime_seconds: 45\n'
              '        hardware: Example GPU\n'
              '        measured_at: 2026-08-24\n'
              '    outputs:\n'
              '      - kind: image',
        ),
      );

      expect(
        catalog.find('image-create')?.runtimeEstimateFor(const {}),
        containsPair('estimatedSeconds', 45),
      );
    });
  });
}

Matcher _apiError(String code) =>
    isA<ApiError>().having((error) => error.code, 'code', code);

const _validCatalog = '''
schema_version: 1
workflows:
  - id: image-create
    name: Image Create
    model: Example Image Model
    contract_version: 1
    dispatch_workflow: .github/workflows/image-create.yaml
    inputs:
      prompt:
        type: string
        required: true
        max_length: 8000
      aspect_ratio:
        type: string
        required: true
        max_length: 8
        allowed_values: ["1:1", "16:9"]
      seed:
        type: number
        required: false
    outputs:
      - kind: image
        content_types: [image/png, image/jpeg]
        max_bytes: 52428800
  - id: image-to-video
    name: Image to Video
    contract_version: 1
    dispatch_workflow: .github/workflows/image-to-video.yaml
    inputs:
      source_image_url:
        type: string
        required: true
        max_length: 2048
      prompt:
        type: string
        required: true
        max_length: 8000
      duration_seconds:
        type: number
        required: true
        minimum: 2
        maximum: 20
        default: 5
    outputs:
      - kind: video
        content_types: [video/mp4, video/webm]
        max_bytes: 2147483648
''';
