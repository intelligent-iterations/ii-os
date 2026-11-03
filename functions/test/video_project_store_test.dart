import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/asset_retention_service.dart';
import 'package:ii_os_functions/src/video_project_store.dart';
import 'package:test/test.dart';

Map<String, Object?> _timeline({int lanes = 1, int clipsPerLane = 2}) => {
  'version': 1,
  'durationMicros': 12000000,
  'lanes': [
    for (var lane = 0; lane < lanes; lane++)
      {
        'id': 'lane-$lane',
        'clips': [
          for (var clip = 0; clip < clipsPerLane; clip++) {'id': 'clip-$clip'},
        ],
      },
  ],
};

Map<String, Object?> _media(String id) => {
  'id': id,
  'filename': 'shot.mp4',
  'contentType': 'video/mp4',
  'byteLength': 2048,
  'durationMicros': 4000000,
  'origin': {'kind': 'sourceAsset', 'assetId': 'asset-1'},
};

void main() {
  group('name', () {
    test('falls back to something a person can still find', () {
      expect(validateVideoProjectName(null), 'Untitled project');
      expect(validateVideoProjectName('   '), 'Untitled project');
      expect(validateVideoProjectName('  Trailer  '), 'Trailer');
    });

    test('refuses one too long to show anywhere', () {
      expect(
        () => validateVideoProjectName('x' * 81),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('timeline', () {
    test('keeps a timeline that fits', () {
      expect(validateVideoProjectTimeline(_timeline())['version'], 1);
    });

    test('refuses more lanes than the editor allows', () {
      expect(
        () => validateVideoProjectTimeline(_timeline(lanes: 25)),
        throwsA(isA<ApiError>()),
      );
    });

    test('refuses more clips than the editor allows', () {
      expect(
        () =>
            validateVideoProjectTimeline(_timeline(lanes: 4, clipsPerLane: 70)),
        throwsA(isA<ApiError>()),
      );
    });

    test('refuses a timeline too large to store', () {
      expect(
        () => validateVideoProjectTimeline({
          'lanes': <Object?>[],
          'padding': 'x' * (513 * 1024),
        }),
        throwsA(isA<ApiError>().having((error) => error.status, 'status', 413)),
      );
    });

    test('refuses something that is not a timeline', () {
      expect(
        () => validateVideoProjectTimeline('a timeline'),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('media', () {
    test('keeps entries that say where they live', () {
      expect(validateVideoProjectMedia([_media('media-1')]), hasLength(1));
      expect(
        validateVideoProjectMedia([
          {
            ..._media('media-2'),
            'origin': {
              'kind': 'artifact',
              'jobId': 'job-1',
              'path': 'workspaces/w/runs/job-1/video/out.mp4',
              'generation': '17',
            },
          },
        ]),
        hasLength(1),
      );
    });

    test('preserves exact decoded stream timing envelopes', () {
      final media = {
        ..._media('media-timing'),
        'hasVideo': true,
        'hasAudio': true,
        'videoTiming': {
          'presentationStartMicros': 0,
          'durationMicros': 4000000,
        },
        'audioTiming': {
          'presentationStartMicros': 175000,
          'durationMicros': 3825000,
        },
      };

      expect(validateVideoProjectMedia([media]).single, media);
    });

    test('rejects malformed decoded stream timing envelopes', () {
      final valid = {
        ..._media('media-timing'),
        'hasVideo': true,
        'videoTiming': {
          'presentationStartMicros': 0,
          'durationMicros': 4000000,
        },
      };
      for (final replacement in <Object?>[
        'not-a-map',
        {'presentationStartMicros': '0', 'durationMicros': 4000000},
        {'presentationStartMicros': 0, 'durationMicros': 4000000.5},
        {
          'presentationStartMicros': 0,
          'durationMicros': 4000000,
          'unexpected': true,
        },
        {'presentationStartMicros': 1, 'durationMicros': 4000000},
        {'presentationStartMicros': 0, 'durationMicros': 3999999},
      ]) {
        expect(
          () => validateVideoProjectMedia([
            {...valid, 'videoTiming': replacement},
          ]),
          throwsA(isA<ApiError>()),
          reason: '$replacement',
        );
      }
      expect(
        () => validateVideoProjectMedia([
          {...valid, 'hasVideo': false},
        ]),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => validateVideoProjectMedia([
          {...valid, 'durationMicros': 4000000.0},
        ]),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => validateVideoProjectMedia([
          {...valid, 'hasAudio': true},
        ]),
        throwsA(isA<ApiError>()),
      );
    });

    test('refuses an entry with no home in the workspace', () {
      expect(
        () => validateVideoProjectMedia([
          {
            ..._media('media-3'),
            'origin': {'kind': 'browserMemory'},
          },
        ]),
        throwsA(isA<ApiError>()),
      );
    });

    test('refuses a repeated identifier', () {
      expect(
        () => validateVideoProjectMedia([_media('media-1'), _media('media-1')]),
        throwsA(isA<ApiError>()),
      );
    });

    test('refuses an identifier FFmpeg would not accept', () {
      expect(
        () => validateVideoProjectMedia([_media('../escape')]),
        throwsA(isA<ApiError>()),
      );
    });

    test('refuses more media than one project may hold', () {
      expect(
        () => validateVideoProjectMedia([
          for (var index = 0; index < 33; index++) _media('media-$index'),
        ]),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('history', () {
    test('describes a save when the client says nothing', () {
      expect(validateVideoProjectChange(null), 'Saved the project');
      expect(validateVideoProjectChange(' Cut a clip '), 'Cut a clip');
    });

    test('refuses a description nobody would read', () {
      expect(
        () => validateVideoProjectChange('x' * 201),
        throwsA(isA<ApiError>()),
      );
    });

    test('keeps the newest two hundred entries and drops the rest', () {
      var history = <Object?>[];
      for (var index = 0; index < 250; index++) {
        history = boundedVideoProjectHistory(history, {
          'description': '$index',
        });
      }

      expect(history, hasLength(200));
      expect((history.first! as Map)['description'], '50');
      expect((history.last! as Map)['description'], '249');
    });
  });

  group('summary', () {
    test('counts what the project list shows without the timeline', () {
      final timeline = _timeline(lanes: 3, clipsPerLane: 4);
      expect(videoProjectClipCount(timeline), 12);
      expect(videoProjectDurationMicros(timeline), 12000000);
    });

    test('leaves out the timeline a list does not need', () {
      final summary = videoProjectSummary('project-1', {
        'name': 'Trailer',
        'durationMicros': 9000000,
        'clipCount': 4,
        'media': [_media('media-1')],
        'revision': 3,
        'updatedBy': 'user-1',
        'updatedAt': '2026-08-23T10:00:00.000Z',
        'createdAt': '2026-08-22T10:00:00.000Z',
        'timeline': _timeline(),
      });

      expect(summary['id'], 'project-1');
      expect(summary['name'], 'Trailer');
      expect(summary['clipCount'], 4);
      expect(summary['mediaCount'], 1);
      expect(summary['revision'], 3);
      expect(summary.containsKey('timeline'), isFalse);
    });

    test('gives a detail view everything needed to reopen the project', () {
      final detail = videoProjectDetail('project-1', {
        'name': 'Trailer',
        'timeline': _timeline(),
        'media': [_media('media-1')],
        'history': [
          {'description': 'Started the project'},
        ],
        'updatedAt': '2026-08-23T10:00:00.000Z',
        'createdAt': '2026-08-22T10:00:00.000Z',
      });

      expect((detail['timeline']! as Map)['version'], 1);
      expect(detail['media'], hasLength(1));
      expect(detail['history'], hasLength(1));
    });
  });

  group('what a project holds', () {
    test('holds generated media where it already lives', () {
      final graph = videoProjectAssetAttachmentGraph({
        'id': 'project-1',
        'media': [
          {
            'id': 'media-1',
            'origin': {
              'kind': 'artifact',
              'jobId': 'job-7',
              'path': 'workspaces/w/runs/job-7/video/out.mp4',
              'generation': '3',
            },
          },
        ],
      });

      expect(graph, {
        'jobRuns/job-7': {'video-project/project-1/media/media-1'},
      });
    });

    test('holds uploaded media as the asset it became', () {
      final graph = videoProjectAssetAttachmentGraph({
        'id': 'project-1',
        'media': [
          {
            'id': 'media-2',
            'origin': {'kind': 'sourceAsset', 'assetId': 'asset-9'},
          },
        ],
      });

      expect(graph, {
        'sourceAssets/asset-9': {'video-project/project-1/media/media-2'},
      });
    });

    test('holds one record once however many clips use it', () {
      final graph = videoProjectAssetAttachmentGraph({
        'id': 'project-1',
        'media': [
          {
            'id': 'media-1',
            'origin': {'kind': 'artifact', 'jobId': 'job-7'},
          },
          {
            'id': 'media-1',
            'origin': {'kind': 'artifact', 'jobId': 'job-7'},
          },
        ],
      });

      expect(graph['jobRuns/job-7'], hasLength(1));
    });

    test('holds nothing it cannot name', () {
      expect(videoProjectAssetAttachmentGraph(const {'media': []}), isEmpty);
      expect(
        videoProjectAssetAttachmentGraph(const {
          'id': 'project-1',
          'media': [
            {
              'id': 'media-1',
              'origin': {'kind': 'browserMemory'},
            },
            {
              'id': '',
              'origin': {'kind': 'sourceAsset', 'assetId': 'a'},
            },
            {
              'id': 'media-2',
              'origin': {'kind': 'sourceAsset'},
            },
          ],
        }),
        isEmpty,
      );
    });
  });
}
