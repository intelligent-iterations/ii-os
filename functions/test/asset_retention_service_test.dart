import 'package:ii_os_functions/src/asset_retention_service.dart';
import 'package:test/test.dart';

void main() {
  test('character graph retains every generated sheet and its source', () {
    final graph = characterAssetAttachmentGraph({
      'id': 'character-1',
      'sourceAssetId': 'source-1',
      'generationJobIds': ['head-1', 'head-2'],
      'bodyGenerationJobIds': ['body-1'],
    });

    expect(graph, {
      'jobRuns/head-1': {'character/character-1/head'},
      'jobRuns/head-2': {'character/character-1/head'},
      'jobRuns/body-1': {'character/character-1/body'},
      'sourceAssets/source-1': {'character/character-1/source'},
    });
  });

  test('storyboard graph retains panel image history and current video', () {
    final graph = storyboardAssetAttachmentGraph({
      'id': 'storyboard-1',
      'panels': [
        {
          'id': 'panel-1',
          'jobId': 'image-2',
          'generationJobIds': ['image-1', 'image-2'],
          'videoJobId': 'video-1',
        },
      ],
    });

    expect(graph, {
      'jobRuns/image-1': {'storyboard/storyboard-1/panel/panel-1/image'},
      'jobRuns/image-2': {'storyboard/storyboard-1/panel/panel-1/image'},
      'jobRuns/video-1': {'storyboard/storyboard-1/panel/panel-1/video'},
    });
  });

  test('completion targets map to durable attachment identities', () {
    expect(
      assetAttachmentForTarget({
        'kind': 'character_image',
        'characterId': 'character-1',
        'body': true,
      }),
      'character/character-1/body',
    );
    expect(
      assetAttachmentForTarget({
        'kind': 'storyboard_panel_video',
        'storyboardId': 'storyboard-1',
        'panelId': 'panel-1',
      }),
      'storyboard/storyboard-1/panel/panel-1/video',
    );
  });
}
