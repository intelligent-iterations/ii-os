import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/generation_history_repository.dart';

void main() {
  test(
    'pages history and merges live changes without rereading old pages',
    () async {
      final responses = Queue<JsonMap>.of([
        {
          'jobs': [_job('job-2', _ago(2), 'new.png')],
          'hasMore': true,
          'nextCursor': 'older-page',
          'syncAfter': '2026-07-19T12:01:00Z',
        },
        {
          'jobs': [_job('job-1', _ago(3), 'older.mp4')],
          'hasMore': false,
          'nextCursor': null,
          'syncAfter': '2026-07-19T12:02:00Z',
        },
        {
          'jobs': [_job('job-3', _ago(1), 'latest.png')],
          'hasMore': false,
          'nextCursor': null,
          'syncAfter': '2026-07-19T13:01:00Z',
        },
      ]);
      final queries = <Map<String, String>>[];
      final repository = GenerationHistoryRepository.withLoader(
        workspaceId: 'workspace-1',
        retentionDays: 30,
        // This exercises delta merging, not freshness: the window would answer
        // the refresh below without ever issuing the call under test.
        freshFor: Duration.zero,
        loader: (query) async {
          queries.add(Map.of(query));
          return responses.removeFirst();
        },
      );
      addTearDown(repository.dispose);

      await repository.loadInitial();
      expect(repository.entries.map((entry) => entry.jobId), ['job-2']);
      expect(repository.hasMore, isTrue);
      expect(queries.single, {'limit': '20', 'reconcile': 'false'});

      await repository.loadMore();
      expect(repository.entries.map((entry) => entry.jobId), [
        'job-2',
        'job-1',
      ]);
      expect(repository.hasMore, isFalse);
      expect(queries[1]['cursor'], 'older-page');

      await repository.refresh(reportError: true);
      expect(repository.entries.map((entry) => entry.jobId), [
        'job-3',
        'job-2',
        'job-1',
      ]);
      expect(queries[2]['changesSince'], '2026-07-19T12:01:00Z');
      expect(queries[2]['limit'], '50');
    },
  );

  test('skips full job pages that contain no generated media', () async {
    final responses = Queue<JsonMap>.of([
      {
        'jobs': [
          _jobWithoutMedia('job-failed-1', _ago(1)),
          _jobWithoutMedia('job-failed-2', _ago(2)),
        ],
        'hasMore': true,
        'nextCursor': 'older-page',
        'syncAfter': '2026-08-09T17:30:00Z',
      },
      {
        'jobs': [_job('job-with-media', _ago(3), 'restored.mp4')],
        'hasMore': false,
        'nextCursor': null,
        'syncAfter': '2026-08-09T17:31:00Z',
      },
    ]);
    final queries = <Map<String, String>>[];
    final repository = GenerationHistoryRepository.withLoader(
      workspaceId: 'workspace-1',
      retentionDays: 30,
      loader: (query) async {
        queries.add(Map.of(query));
        return responses.removeFirst();
      },
    );
    addTearDown(repository.dispose);

    await repository.loadInitial();

    expect(repository.entries.map((entry) => entry.jobId), ['job-with-media']);
    expect(repository.hasMore, isFalse);
    expect(queries, [
      {'limit': '20', 'reconcile': 'false'},
      {'limit': '20', 'reconcile': 'false', 'cursor': 'older-page'},
    ]);
  });

  test('a poster becomes its video preview, never its own card', () async {
    final repository = GenerationHistoryRepository.withLoader(
      workspaceId: 'workspace-1',
      retentionDays: 30,
      loader: (query) async => {
        'jobs': [_jobWithPoster('job-9', _ago(1))],
        'hasMore': false,
        'nextCursor': null,
        'syncAfter': '2026-07-19T12:01:00Z',
      },
    );
    addTearDown(repository.dispose);

    await repository.loadInitial();

    // Two artifacts, one generation: nobody asked for the poster, so it must
    // not occupy a slot in the grid beside the clip it depicts.
    final entry = repository.entries.single;
    expect(entry.isVideo, isTrue);
    expect(entry.filename, 'clip.mp4');
    expect(entry.previewArtifact?['path'], endsWith('clip-poster.png'));
  });

  test(
    'a refresh straight after a sync does not go back to the network',
    () async {
      // Several media fields on a screen each open a picker against the shared
      // repository and each asks it to refresh. The delta is cheap but not free,
      // and the second and third can only return what the first already had.
      var pages = 0;
      final history = GenerationHistoryRepository.withLoader(
        workspaceId: 'workspace-1',
        retentionDays: 30,
        loader: (query) async {
          pages++;
          return {
            'jobs': <JsonMap>[],
            'hasMore': false,
            'syncAfter': '2026-08-21T12:00:00Z',
          };
        },
      );

      await history.loadInitial();
      expect(pages, 1);

      await history.refresh();
      await history.refresh();
      expect(
        pages,
        1,
        reason: 'a refresh inside the freshness window is already answered',
      );
    },
  );

  test('a refresh past the freshness window still syncs', () async {
    var pages = 0;
    final history = GenerationHistoryRepository.withLoader(
      workspaceId: 'workspace-1',
      retentionDays: 30,
      freshFor: Duration.zero,
      loader: (query) async {
        pages++;
        return {
          'jobs': <JsonMap>[],
          'hasMore': false,
          'syncAfter': '2026-08-21T12:00:00Z',
        };
      },
    );

    await history.loadInitial();
    await history.refresh();
    expect(pages, 2, reason: 'staleness must still reach the network');
  });

  test(
    'watching loads once without creating a background read timer',
    () async {
      var pages = 0;
      final history = GenerationHistoryRepository.withLoader(
        workspaceId: 'workspace-1',
        retentionDays: 30,
        loader: (query) async {
          pages++;
          return {
            'jobs': <JsonMap>[],
            'hasMore': false,
            'syncAfter': '2026-08-21T12:00:00Z',
          };
        },
      );
      addTearDown(history.dispose);

      history.startWatching();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(pages, 1);
    },
  );
}

JsonMap _jobWithPoster(String jobId, String createdAt) => {
  'jobId': jobId,
  'status': 'completed',
  'createdAt': createdAt,
  'artifacts': [
    // Deliberately poster-first: a run reports artifacts in whatever order it
    // uploaded them, so pairing cannot depend on the video coming first.
    {
      'path': 'workspaces/workspace-1/runs/$jobId/clip-poster.png',
      'generation': '2',
      'content_type': 'image/png',
      'role': 'poster',
      'poster_for': 'workspaces/workspace-1/runs/$jobId/clip.mp4',
    },
    {
      'path': 'workspaces/workspace-1/runs/$jobId/clip.mp4',
      'generation': '1',
      'content_type': 'video/mp4',
    },
  ],
};

JsonMap _job(String jobId, String createdAt, String filename) => {
  'jobId': jobId,
  'status': 'completed',
  'createdAt': createdAt,
  'artifacts': [
    {
      'path': 'workspaces/workspace-1/runs/$jobId/$filename',
      'generation': '1',
      'content_type': filename.endsWith('.mp4') ? 'video/mp4' : 'image/png',
    },
  ],
};

JsonMap _jobWithoutMedia(String jobId, String createdAt) => {
  'jobId': jobId,
  'status': 'failed',
  'createdAt': createdAt,
  'artifacts': <Object?>[],
};

String _ago(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();
