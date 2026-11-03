import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/prompt_enhancer.dart';
import 'package:ii_os_functions/src/storyboard_references.dart';
import 'package:test/test.dart';

void main() {
  test('combined references occupy only the three Qwen source slots', () {
    final input = storyboardReferenceWorkflowInput(
      requestedInput: const {
        'mode': 'injected',
        'source_asset_id': 'injected-source',
        'source_asset_id_2': 'injected-source-2',
        'source_asset_id_3': 'injected-source-3',
        'control_strength': 0.7,
      },
      referenceAssetIds: const [
        'character-asset',
        'panel-asset-1',
        'panel-asset-2',
      ],
    );

    expect(input['mode'], 'edit');
    expect(input['source_asset_id'], 'character-asset');
    expect(input['source_asset_id_2'], 'panel-asset-1');
    expect(input['source_asset_id_3'], 'panel-asset-2');
    expect(input['control_strength'], 0.7);
  });

  test('builds an exact scene and named-character image map', () {
    final prompt = storyboardReferencePrompt(const [
      PromptImageReference(
        imageNumber: 1,
        role: 'source_scene',
        label: 'Storyboard panel 2',
      ),
      PromptImageReference(imageNumber: 2, role: 'character', label: 'Jenny'),
    ]);

    expect(prompt, contains('Image 1 is the source scene'));
    expect(prompt, contains('Image 2 refers to "Jenny"'));
    expect(prompt, contains('semantic metadata'));
    expect(prompt, contains('purely visual composition by default'));
    expect(prompt, contains('exact identity and design nuances'));
    expect(prompt, contains('primary art-style anchor'));
    expect(prompt, contains('source scene\u2019s composition'));
    expect(prompt, contains('established identity and design authoritative'));
    expect(hasNegativePromptLanguage(prompt), isFalse);
  });

  test('maps only exact character object names without alias inference', () {
    final references = const [
      PromptImageReference(
        imageNumber: 1,
        role: 'character',
        label: 'Samantha',
      ),
      PromptImageReference(imageNumber: 2, role: 'character', label: 'Sam Lee'),
    ];
    final prompt = storyboardReferencePrompt(references);

    expect(prompt, contains('- Image 1 refers to "Samantha".'));
    expect(prompt, contains('- Image 2 refers to "Sam Lee".'));
    expect(prompt, isNot(contains('Resolved character-name aliases')));
    expect(prompt, isNot(contains('Character role bindings')));
    expect(prompt, isNot(contains('"Sam"')));
    expect(prompt, isNot(contains('"Lee"')));
    expect(prompt, contains('actions, positions, interactions, and props'));
    expect(prompt, contains('primary art-style anchor for the whole scene'));
    expect(prompt, contains('medium, linework, rendering'));
    expect(prompt, contains('complete scene composition'));
  });

  test('rejects a reference map that can drift from source image order', () {
    expect(
      () => storyboardReferencePrompt(const [
        PromptImageReference(imageNumber: 2, role: 'character', label: 'Jenny'),
      ]),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'storyboard_reference_map_invalid',
        ),
      ),
    );
  });

  test('panel references preserve selection order and historical images', () {
    final sources = storyboardPanelReferenceSources(
      panels: const [
        {'id': 'panel-1', 'jobId': 'job-current-1'},
        {
          'id': 'panel-2',
          'jobId': 'job-current-2',
          'selectedImage': {
            'jobId': 'job-historical-2',
            'path': 'workspaces/w/runs/job-historical-2/panel.png',
            'generation': '42',
            'content_type': 'image/png',
          },
        },
      ],
      referencePanelIds: const ['panel-2', 'panel-1'],
    );

    expect(sources.map((source) => source.panelId), ['panel-2', 'panel-1']);
    expect(sources.map((source) => source.sourceJobId), [
      'job-historical-2',
      'job-current-1',
    ]);
    expect(sources.first.selectedImage?['generation'], '42');
    expect(sources.last.selectedImage, isNull);
  });

  test('panel references require an existing generated panel', () {
    expect(
      () => storyboardPanelReferenceSources(
        panels: const [
          {'id': 'panel-1'},
        ],
        referencePanelIds: const ['panel-1'],
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'storyboard_panel_reference_image_required',
        ),
      ),
    );
    expect(
      () => storyboardPanelReferenceSources(
        panels: const [
          {'id': 'panel-1', 'jobId': 'job-1'},
        ],
        referencePanelIds: const ['missing'],
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'storyboard_panel_reference_not_found',
        ),
      ),
    );
  });
}
