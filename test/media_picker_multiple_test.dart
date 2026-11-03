import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/picked_media.dart';
import 'package:ii_os/repositories/generation_history_repository.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/media_picker.dart';

// Picker behavior needs retained entries; a fixed calendar date eventually
// expires under the repository's real retention policy. Keep equal timestamps
// so this fixture preserves its original ordering semantics.
final _fixtureSubmittedAt = DateTime.now()
    .toUtc()
    .subtract(const Duration(days: 1))
    .toIso8601String();

JsonMap _job(String id, String prompt) => {
  'jobId': id,
  'repository': 'acme/media',
  'status': 'completed',
  'submittedAt': _fixtureSubmittedAt,
  'generationMetadata': {'model': 'Z-Image', 'prompt': prompt},
  'artifacts': [
    {
      'path': 'workspaces/w/runs/$id/media/$id.png',
      'content_type': 'image/png',
      'generation': '1786900000000000',
    },
  ],
};

GenerationHistoryRepository _history() =>
    GenerationHistoryRepository.withLoader(
      workspaceId: 'w',
      retentionDays: 30,
      loader: (_) async => {
        'jobs': [
          _job('job-a', 'a rooftop at dusk'),
          _job('job-b', 'a calm ocean wave'),
          _job('job-c', 'the dancer, wide shot'),
        ],
        'hasMore': false,
      },
    );

Future<void> _settleDialog(WidgetTester tester) async {
  // Not pumpAndSettle: a tile whose preview is in flight spins forever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a multiple picker returns every asset that was chosen', (
    tester,
  ) async {
    // The video editor takes several files at once. Until the library could do
    // the same, "add generated media" and "add local media" had to stay two
    // different controls with two different capabilities.
    List<PickedMedia>? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async => picked = await showMediaPickerMultiple(
                context: context,
                history: _history(),
                loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _settleDialog(tester);

    await tester.tap(find.text('a rooftop at dusk'));
    await tester.pump();
    await tester.tap(find.text('a calm ocean wave'));
    await tester.pump();

    // A count on the confirm button, so the number chosen is visible without
    // counting ticks across a grid.
    expect(find.text('Add 2'), findsOneWidget);
    await tester.tap(find.text('Add 2'));
    await _settleDialog(tester);

    expect(picked, isNotNull);
    expect(picked!.map((one) => one.entry!.jobId), ['job-a', 'job-b']);
  });

  testWidgets('tapping a chosen asset again removes it', (tester) async {
    List<PickedMedia>? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async => picked = await showMediaPickerMultiple(
                context: context,
                history: _history(),
                loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _settleDialog(tester);

    await tester.tap(find.text('a rooftop at dusk'));
    await tester.pump();
    await tester.tap(find.text('a rooftop at dusk'));
    await tester.pump();

    expect(
      find.textContaining('Add '),
      findsNothing,
      reason: 'nothing is chosen, so there is nothing to confirm',
    );
    expect(picked, isNull);
  });

  testWidgets('a single picker still returns on the first tap', (tester) async {
    // One asset should never cost a second tap on a confirm button.
    PickedMedia? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async => picked = await showMediaPicker(
                context: context,
                history: _history(),
                loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _settleDialog(tester);

    await tester.tap(find.text('a calm ocean wave'));
    await _settleDialog(tester);

    expect(picked?.entry?.jobId, 'job-b');
  });
}
