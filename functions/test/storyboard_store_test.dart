import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/storyboard_store.dart';
import 'package:test/test.dart';

void main() {
  test('storyboard overview accepts 150 words and rejects 151', () {
    final allowed = List.filled(150, 'scene').join(' ');
    final rejected = '$allowed extra';

    expect(validateStoryboardOverview(allowed), allowed);
    expect(
      () => validateStoryboardOverview(rejected),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'storyboard_overview_too_long',
        ),
      ),
    );
  });

  test('panel generation prompt is only the trimmed scene prompt', () {
    expect(
      storyboardGenerationPrompt(
        '  The courier reaches the submerged train station.  ',
      ),
      'The courier reaches the submerged train station.',
    );
    expect(
      () => storyboardGenerationPrompt('   '),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'invalid_storyboard_panel_prompt',
        ),
      ),
    );
  });

  test(
    'panel updates preserve requested order and generated media metadata',
    () {
      final panels = validateStoryboardPanels(
        <Object?>[
          {
            'id': 'panel-3',
            'prompt': 'Third scene moved first.',
            'characterIds': <Object?>[],
            'referencePanelIds': ['panel-1'],
          },
          {
            'id': 'panel-1',
            'prompt': 'First scene moved second.',
            'characterIds': <Object?>[],
          },
          {
            'id': 'panel-2',
            'prompt': 'Second scene moved last.',
            'characterIds': <Object?>[],
          },
        ],
        <Object?>[
          {
            'id': 'panel-1',
            'jobId': 'image-1',
            'generationJobIds': ['image-old-1', 'image-1'],
            'selectedImage': {
              'jobId': 'image-old-1',
              'path': 'workspaces/w/runs/image-old-1/panel.png',
              'generation': '41',
              'content_type': 'image/png',
            },
            'videoJobId': 'video-1',
            'videoDurationSeconds': 5,
          },
          {
            'id': 'panel-2',
            'jobId': 'image-2',
            'videoJobId': 'video-2',
            'videoDurationSeconds': 7,
          },
          {
            'id': 'panel-3',
            'jobId': 'image-3',
            'videoJobId': 'video-3',
            'videoDurationSeconds': 9,
          },
        ],
      );

      expect(panels.map((panel) => panel['id']), [
        'panel-3',
        'panel-1',
        'panel-2',
      ]);
      expect(panels.map((panel) => panel['videoJobId']), [
        'video-3',
        'video-1',
        'video-2',
      ]);
      expect(panels.map((panel) => panel['videoDurationSeconds']), [9, 5, 7]);
      expect(panels[1]['generationJobIds'], ['image-old-1', 'image-1']);
      expect(panels.first['referencePanelIds'], ['panel-1']);
      expect(
        (panels[1]['selectedImage'] as Map<String, Object?>)['jobId'],
        'image-old-1',
      );
    },
  );

  test('character and panel references share one limit of three', () {
    expect(
      () => validateStoryboardPanels(<Object?>[
        {
          'id': 'panel-1',
          'prompt': 'First scene.',
          'characterIds': ['a', 'b'],
          'referencePanelIds': ['panel-2', 'panel-3'],
        },
        {
          'id': 'panel-2',
          'prompt': 'Second scene.',
          'characterIds': <Object?>[],
        },
        {
          'id': 'panel-3',
          'prompt': 'Third scene.',
          'characterIds': <Object?>[],
        },
      ], const <Object?>[]),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'storyboard_reference_limit',
        ),
      ),
    );
  });

  test('panel references must stay inside their storyboard', () {
    expect(
      () => validateStoryboardPanels(<Object?>[
        {
          'id': 'panel-1',
          'prompt': 'First scene.',
          'characterIds': <Object?>[],
          'referencePanelIds': ['missing-panel'],
        },
        {
          'id': 'panel-2',
          'prompt': 'Second scene.',
          'characterIds': <Object?>[],
        },
        {
          'id': 'panel-3',
          'prompt': 'Third scene.',
          'characterIds': <Object?>[],
        },
      ], const <Object?>[]),
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
