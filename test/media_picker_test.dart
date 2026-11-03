import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/generation_history_repository.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/media_library_grid.dart';
import 'package:ii_os/widgets/media_picker.dart';
import 'package:ii_os/widgets/media_upload_pane.dart';

JsonMap _job(String id) => {
  'jobId': id,
  'repository': 'acme/media',
  'status': 'completed',
  'submittedAt': '2026-08-16T12:00:00Z',
  'generationMetadata': {'model': 'Z-Image', 'prompt': 'a rooftop at dusk'},
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
      loader: (_) async => {'jobs': [_job('job-a')], 'hasMore': false},
    );

Future<void> _open(
  WidgetTester tester, {
  bool allowUpload = true,
  String? contentTypePrefix,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: IiOsTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showMediaPicker(
              context: context,
              history: _history(),
              loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
              allowUpload: allowUpload,
              contentTypePrefix: contentTypePrefix,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  // Not pumpAndSettle: a tile whose preview is in flight spins forever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('opens on the library, because reuse is the common case',
      (tester) async {
    await _open(tester);
    expect(find.byType(MediaLibraryGrid), findsOneWidget);
    expect(find.byType(MediaUploadPane), findsNothing);
  });

  testWidgets('switches to upload and back', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(find.byType(MediaUploadPane), findsOneWidget);
    expect(find.byType(MediaLibraryGrid), findsNothing);

    await tester.tap(find.text('Library'));
    await tester.pump();
    expect(find.byType(MediaLibraryGrid), findsOneWidget);
  });

  testWidgets('offers no upload tab when the field cannot accept one',
      (tester) async {
    // A tab that leads nowhere is worse than no tab: it reads as a capability.
    await _open(tester, allowUpload: false);
    expect(find.text('Upload'), findsNothing);
    expect(find.byType(MediaLibraryGrid), findsOneWidget);
  });

  testWidgets('hides the kind filter when the field already fixed the kind',
      (tester) async {
    await _open(tester, contentTypePrefix: 'image/');
    expect(find.text('Videos'), findsNothing);
    expect(find.text('Audio'), findsNothing);
  });
}
