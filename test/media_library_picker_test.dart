import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/generation_history.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/generation_history_repository.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/media_picker.dart';
import 'package:ii_os/widgets/media_library_tile.dart';

// Picker behavior needs retained entries; a fixed calendar date eventually
// expires under the repository's real retention policy. Keep equal timestamps
// so this fixture preserves its original ordering semantics.
final _fixtureSubmittedAt = DateTime.now()
    .toUtc()
    .subtract(const Duration(days: 1))
    .toIso8601String();

JsonMap _job(
  String id,
  String contentType,
  String extension, {
  String prompt = '',
  bool withPoster = false,
}) => {
  'jobId': id,
  'repository': 'acme/media',
  'status': 'completed',
  'submittedAt': _fixtureSubmittedAt,
  if (prompt.isNotEmpty)
    'generationMetadata': {'model': 'Z-Image Turbo', 'prompt': prompt},
  'artifacts': [
    {
      'path': 'workspaces/workspace-1/runs/$id/media/$id.$extension',
      'content_type': contentType,
      'generation': '1786900000000000',
    },
    if (withPoster)
      {
        'path': 'workspaces/workspace-1/runs/$id/media/$id-poster.png',
        'content_type': 'image/png',
        'generation': '1786900000000001',
        'role': 'poster',
        'poster_for': 'workspaces/workspace-1/runs/$id/media/$id.$extension',
      },
  ],
};

GenerationHistoryRepository _history(
  List<JsonMap> jobs, {
  bool hasMore = false,
  void Function(Map<String, String> query)? onQuery,
}) => GenerationHistoryRepository.withLoader(
  workspaceId: 'workspace-1',
  retentionDays: 30,
  loader: (query) async {
    onQuery?.call(query);
    return {
      'jobs': jobs,
      'hasMore': hasMore,
      'syncAfter': '2026-08-16T12:02:00Z',
    };
  },
);

Future<void> _open(
  WidgetTester tester,
  GenerationHistoryRepository history, {
  String? contentTypePrefix,
  HistoryPreviewLoader? loadPreview,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: IiOsTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showMediaPicker(
              context: context,
              history: history,
              loadPreview:
                  loadPreview ??
                  (_) => Completer<VerifiedArtifactMedia>().future,
              contentTypePrefix: contentTypePrefix,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  // Not pumpAndSettle: a tile whose preview is still in flight shows an
  // indeterminate spinner, and an animation that never stops never settles.
  await _openDialog(tester);
}

/// Advances past the dialog route transition without waiting for quiet.
Future<void> _openDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('shows every generated asset as a tile, not a text row', (
    tester,
  ) async {
    final history = _history([
      _job('image-job', 'image/png', 'png', prompt: 'A fictional dancer'),
      _job('video-job', 'video/mp4', 'mp4', withPoster: true),
    ]);
    addTearDown(history.dispose);

    await _open(tester, history);

    expect(find.byType(MediaLibraryTile), findsNWidgets(2));
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('narrowing to one kind hides the others', (tester) async {
    final history = _history([
      _job('image-job', 'image/png', 'png', prompt: 'A fictional dancer'),
      _job('video-job', 'video/mp4', 'mp4', withPoster: true),
    ]);
    addTearDown(history.dispose);

    await _open(tester, history, contentTypePrefix: 'video/');

    expect(find.byType(MediaLibraryTile), findsOneWidget);
    // A locked picker offers no filter to change what it was opened for.
    expect(find.byType(SegmentedButton<Object?>), findsNothing);
  });

  testWidgets('an image picker pages past newer videos before showing empty', (
    tester,
  ) async {
    final responses = Queue<JsonMap>.of([
      {
        'jobs': [_job('video-job', 'video/mp4', 'mp4', withPoster: true)],
        'hasMore': true,
        'nextCursor': 'older-page',
        'syncAfter': '2026-08-16T12:02:00Z',
      },
      {
        'jobs': [
          _job('image-job', 'image/png', 'png', prompt: 'The older image'),
        ],
        'hasMore': false,
        'syncAfter': '2026-08-16T12:02:00Z',
      },
    ]);
    final queries = <Map<String, String>>[];
    final history = GenerationHistoryRepository.withLoader(
      workspaceId: 'workspace-1',
      retentionDays: 30,
      loader: (query) async {
        queries.add(Map.of(query));
        return responses.removeFirst();
      },
    );
    addTearDown(history.dispose);
    final requested = <String>[];

    await _open(
      tester,
      history,
      contentTypePrefix: 'image/',
      loadPreview: (entry) {
        requested.add(entry.jobId);
        return Completer<VerifiedArtifactMedia>().future;
      },
    );

    expect(find.text('The older image'), findsOneWidget);
    expect(requested, ['image-job']);
    expect(queries, hasLength(2));
    expect(queries.last['cursor'], 'older-page');
  });

  testWidgets(
    'an image picker fills from older pages after another picker cached video',
    (tester) async {
      final responses = Queue<JsonMap>.of([
        {
          'jobs': [_job('video-job', 'video/mp4', 'mp4', withPoster: true)],
          'hasMore': true,
          'nextCursor': 'older-page',
          'syncAfter': '2026-08-16T12:02:00Z',
        },
        {
          'jobs': [
            _job(
              'image-job',
              'image/png',
              'png',
              prompt: 'The cached library image',
            ),
          ],
          'hasMore': false,
          'syncAfter': '2026-08-16T12:02:00Z',
        },
      ]);
      final history = GenerationHistoryRepository.withLoader(
        workspaceId: 'workspace-1',
        retentionDays: 30,
        loader: (_) async => responses.removeFirst(),
      );
      addTearDown(history.dispose);
      await history.loadInitial();

      await _open(tester, history, contentTypePrefix: 'image/');

      expect(find.text('The cached library image'), findsOneWidget);
    },
  );

  testWidgets(
    'a video picker pages past newer images without loading their previews',
    (tester) async {
      final responses = Queue<JsonMap>.of([
        {
          'jobs': [
            _job('image-job', 'image/png', 'png', prompt: 'A newer image'),
          ],
          'hasMore': true,
          'nextCursor': 'older-page',
          'syncAfter': '2026-08-16T12:02:00Z',
        },
        {
          'jobs': [
            _job(
              'video-job',
              'video/mp4',
              'mp4',
              prompt: 'The older video',
              withPoster: true,
            ),
          ],
          'hasMore': false,
          'syncAfter': '2026-08-16T12:02:00Z',
        },
      ]);
      final history = GenerationHistoryRepository.withLoader(
        workspaceId: 'workspace-1',
        retentionDays: 30,
        loader: (_) async => responses.removeFirst(),
      );
      addTearDown(history.dispose);
      final requested = <String>[];

      await _open(
        tester,
        history,
        contentTypePrefix: 'video/',
        loadPreview: (entry) {
          requested.add(entry.jobId);
          return Completer<VerifiedArtifactMedia>().future;
        },
      );

      expect(find.text('The older video'), findsOneWidget);
      expect(requested, ['video-job']);
    },
  );

  testWidgets('changing the universal filter lazily fills the selected kind', (
    tester,
  ) async {
    final responses = Queue<JsonMap>.of([
      {
        'jobs': [
          _job('image-job', 'image/png', 'png', prompt: 'The newer image'),
        ],
        'hasMore': true,
        'nextCursor': 'older-page',
        'syncAfter': '2026-08-16T12:02:00Z',
      },
      {
        'jobs': [
          _job(
            'video-job',
            'video/mp4',
            'mp4',
            prompt: 'The filtered video',
            withPoster: true,
          ),
        ],
        'hasMore': false,
        'syncAfter': '2026-08-16T12:02:00Z',
      },
    ]);
    final history = GenerationHistoryRepository.withLoader(
      workspaceId: 'workspace-1',
      retentionDays: 30,
      loader: (_) async => responses.removeFirst(),
    );
    addTearDown(history.dispose);
    final requested = <String>[];

    await _open(
      tester,
      history,
      loadPreview: (entry) {
        requested.add(entry.jobId);
        return Completer<VerifiedArtifactMedia>().future;
      },
    );
    expect(find.text('The newer image'), findsOneWidget);

    await tester.tap(find.text('Videos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('The newer image'), findsNothing);
    expect(find.text('The filtered video'), findsOneWidget);
    expect(requested, ['image-job', 'video-job']);
  });

  testWidgets(
    'a filtered picker keeps each automatic scan bounded and can continue',
    (tester) async {
      final responses = Queue<JsonMap>.of([
        for (var page = 0; page < 6; page++)
          {
            'jobs': [_job('video-$page', 'video/mp4', 'mp4', withPoster: true)],
            'hasMore': true,
            'nextCursor': 'page-${page + 1}',
            'syncAfter': '2026-08-16T12:02:00Z',
          },
        {
          'jobs': [
            _job(
              'image-job',
              'image/png',
              'png',
              prompt: 'The much older image',
            ),
          ],
          'hasMore': false,
          'syncAfter': '2026-08-16T12:02:00Z',
        },
      ]);
      final queries = <Map<String, String>>[];
      final history = GenerationHistoryRepository.withLoader(
        workspaceId: 'workspace-1',
        retentionDays: 30,
        loader: (query) async {
          queries.add(Map.of(query));
          return responses.removeFirst();
        },
      );
      addTearDown(history.dispose);

      await _open(tester, history, contentTypePrefix: 'image/');

      expect(find.text('Look further back'), findsOneWidget);
      expect(queries, hasLength(6));
      expect(find.text('The much older image'), findsNothing);

      await tester.tap(find.text('Look further back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('The much older image'), findsOneWidget);
      expect(queries, hasLength(7));
    },
  );

  testWidgets('an entry with no preview never asks for one', (tester) async {
    // Audio has nothing to render, so a loader would spin for ever. The tile
    // has to know that before it starts.
    final history = _history([_job('audio-job', 'audio/mpeg', 'mp3')]);
    addTearDown(history.dispose);
    var requested = 0;

    await _open(
      tester,
      history,
      loadPreview: (_) {
        requested++;
        return Completer<VerifiedArtifactMedia>().future;
      },
    );

    expect(find.byType(MediaLibraryTile), findsOneWidget);
    expect(requested, 0);
  });

  testWidgets('a preview is only fetched for a tile that gets built', (
    tester,
  ) async {
    // Sixty assets, a viewport that holds far fewer: the grid builds what it
    // shows, so the picker must not download the whole library to open.
    final history = _history([
      for (var index = 0; index < 60; index++)
        _job('job-$index', 'image/png', 'png', prompt: 'Asset $index'),
    ]);
    addTearDown(history.dispose);
    final requested = <String>{};

    await _open(
      tester,
      history,
      loadPreview: (entry) {
        requested.add(entry.jobId);
        return Completer<VerifiedArtifactMedia>().future;
      },
    );

    expect(requested, isNotEmpty);
    expect(
      requested.length,
      lessThan(60),
      reason: 'opening the picker downloaded every asset in the library',
    );
  });

  testWidgets('picking a tile returns that entry', (tester) async {
    final history = _history([
      _job('image-job', 'image/png', 'png', prompt: 'A fictional dancer'),
    ]);
    addTearDown(history.dispose);
    HistoryEntryModel? picked;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                picked = (await showMediaPicker(
                  context: context,
                  history: history,
                  loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
                ))?.entry;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _openDialog(tester);
    await tester.tap(find.byType(MediaLibraryTile).first);
    await _openDialog(tester);

    expect(picked?.jobId, 'image-job');
  });

  testWidgets(
    'a video with a poster asks for its preview when its tile appears',
    (tester) async {
      // The live picker rendered every tile empty and issued no request at
      // all, while the asset library showed the same assets with posters. The
      // property that matters is not "eventually loads" but "asked at all".
      final asked = <String>[];
      await _open(
        tester,
        _history([
          _job(
            'job-a',
            'video/mp4',
            'mp4',
            prompt: 'a calm ocean wave',
            withPoster: true,
          ),
          _job(
            'job-b',
            'video/mp4',
            'mp4',
            prompt: 'the dancer performs',
            withPoster: true,
          ),
        ]),
        loadPreview: (entry) {
          asked.add(entry.jobId);
          return Completer<VerifiedArtifactMedia>().future;
        },
      );

      expect(
        asked,
        containsAll(<String>['job-a', 'job-b']),
        reason: 'every visible tile with a poster must request it',
      );
    },
  );
}
