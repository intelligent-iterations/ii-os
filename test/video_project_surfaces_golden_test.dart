@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_export_target.dart';
import 'package:ii_os/models/video_project.dart';
import 'package:ii_os/widgets/video_editor_controls.dart';
import 'package:ii_os/widgets/video_editor_header.dart';
import 'package:ii_os/widgets/video_editor_stage.dart';
import 'package:ii_os/widgets/video_project_bar.dart';
import 'package:ii_os/widgets/video_project_history.dart';
import 'package:ii_os/widgets/video_project_picker.dart';

import 'golden_harness.dart';

VideoProjectSummary _summary({
  String id = 'project-1',
  String name = 'Launch trailer',
  int clipCount = 6,
}) => VideoProjectSummary(
  id: id,
  name: name,
  duration: const Duration(seconds: 42),
  clipCount: clipCount,
  mediaCount: 3,
  revision: 8,
  updatedAt: DateTime(2026, 8, 23, 14, 5),
  updatedBy: 'user-1',
);

MediaSource _source() => MediaSource(
  id: 'media-1',
  byteLength: 8,
  fileExtension: 'mp4',
  openRead: () => Stream<List<int>>.value(const [1, 2, 3, 4, 5, 6, 7, 8]),
);

MediaSource _imageSource() => MediaSource(
  id: 'brand-image',
  byteLength: 4,
  fileExtension: 'png',
  openRead: () => Stream<List<int>>.value(const [137, 80, 78, 71]),
);

EditorProject _timeline() => EditorProject(
  id: 'ii-os-project',
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.seconds(8),
  lanes: [
    EditorLane(
      id: 'video-lane',
      label: 'Opening shot',
      kind: EditorLaneKind.video,
      clips: [
        EditorVideoClip(
          id: 'video-clip',
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(8),
          source: _source(),
          sourceRange: MediaRange(
            start: MediaTime.zero,
            duration: MediaTime.seconds(8),
          ),
          sourceDuration: MediaTime.seconds(8),
        ),
      ],
    ),
  ],
);

EditorProject _layeredTimeline() => addEditorImageOverlay(
  project: _timeline(),
  laneId: 'brand-lane',
  clipId: 'brand-clip',
  source: _imageSource(),
  timelineStart: MediaTime.seconds(1),
  duration: MediaTime.seconds(5),
  laneLabel: 'Brand image',
);

void main() {
  setUpAll(() async {
    await loadIiOsFonts();
    final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await lucide.load();
  });

  testWidgets('VideoProjectBar states', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('video-project-bar-golden'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProjectBar(
                project: _summary(),
                unsavedChanges: 3,
                saving: false,
                canUndo: true,
                canRedo: false,
                onUndo: () {},
                onRedo: () {},
                onSave: () {},
                onOpen: () {},
                onNew: () {},
                onHistory: () {},
              ),
              VideoProjectBar(
                project: null,
                unsavedChanges: 0,
                saving: false,
                canUndo: false,
                canRedo: false,
                onUndo: null,
                onRedo: null,
                onSave: null,
                onOpen: () {},
                onNew: () {},
                onHistory: null,
              ),
            ],
          ),
        ),
        width: 900,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('video-project-bar-golden')),
      matchesGoldenFile('goldens/video_project_bar.png'),
    );
  });

  testWidgets('VideoProjectPicker lists what can be opened', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('video-project-picker-golden'),
          child: VideoProjectPicker(
            projects: [
              _summary(),
              _summary(id: 'project-2', name: 'Cutdown', clipCount: 0),
            ],
            openProjectId: 'project-1',
            loading: false,
            failure: null,
            onOpen: (_) {},
            onCreate: () {},
            onDelete: (_) {},
          ),
        ),
        width: 560,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('video-project-picker-golden')),
      matchesGoldenFile('goldens/video_project_picker.png'),
    );
  });

  testWidgets('VideoProjectHistory separates saved from unsaved', (
    tester,
  ) async {
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('video-project-history-golden'),
          child: VideoProjectHistory(
            saved: [
              VideoProjectChange(
                at: DateTime(2026, 8, 23, 13, 40),
                by: 'user-1',
                description: 'Added a cross dissolve',
                revision: 7,
              ),
              VideoProjectChange(
                at: DateTime(2026, 8, 23, 13, 12),
                by: 'user-1',
                description: 'Cut 2 lanes',
                revision: 6,
              ),
            ],
            unsaved: const ['Trimmed a clip', 'Removed 2.0 seconds'],
          ),
        ),
        width: 560,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('video-project-history-golden')),
      matchesGoldenFile('goldens/video_project_history.png'),
    );
  });

  testWidgets('VideoEditorStage before anything is added', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const RepaintBoundary(
          key: Key('video-editor-stage-golden'),
          child: VideoEditorEmptyStage(ghostMode: false),
        ),
        width: 560,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('video-editor-stage-golden')),
      matchesGoldenFile('goldens/video_editor_stage.png'),
    );
  });

  testWidgets('VideoEditorStage with a timeline on it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('video-editor-stage-loaded-golden'),
          child: VideoEditorStage(
            project: _timeline(),
            playhead: MediaTime.seconds(2),
            selection: null,
            busy: false,
            canUndo: false,
            onUndoRequested: () {},
            onProjectChanged: (_) {},
            onPlayheadChanged: (_) {},
            onSelectionChanged: (_) {},
            onAddCaptionRequested: () {},
            onRenderRequested: () {},
            onEditError: (_) {},
            previewBuilder: (context, project, playhead, selection) =>
                const ColoredBox(color: Colors.black),
          ),
        ),
        width: 1000,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('video-editor-stage-loaded-golden')),
      matchesGoldenFile('goldens/video_editor_stage_loaded.png'),
    );
  });

  testWidgets('VideoEditorStage with a selected image overlay', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('video-editor-stage-image-golden'),
          child: VideoEditorStage(
            project: _layeredTimeline(),
            playhead: MediaTime.seconds(2),
            selection: const EditorSelection(
              laneId: 'brand-lane',
              clipId: 'brand-clip',
            ),
            busy: false,
            canUndo: true,
            onUndoRequested: () {},
            onProjectChanged: (_) {},
            onPlayheadChanged: (_) {},
            onSelectionChanged: (_) {},
            onAddCaptionRequested: () {},
            onRenderRequested: () {},
            onEditError: (_) {},
            previewBuilder: (context, project, playhead, selection) =>
                const ColoredBox(color: Colors.black),
          ),
        ),
        width: 1000,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('video-editor-stage-image-golden')),
      matchesGoldenFile('goldens/video_editor_stage_image.png'),
    );
  });

  testWidgets('VideoEditorSummary offers where the export happens', (
    tester,
  ) async {
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('video-editor-controls-golden'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoEditorSummary(
                sourceCount: 3,
                duration: MediaTime.seconds(42),
                bitrate: 4 * 1000 * 1000,
                enabled: true,
                onBitrateChanged: (_) {},
                exportTarget: EditorExportTarget.thisDevice,
                onExportTargetChanged: (_) {},
                workspaceRenderAvailable: true,
              ),
              const SizedBox(height: 24),
              VideoEditorSummary(
                sourceCount: 1,
                duration: MediaTime.seconds(8),
                bitrate: 6 * 1000 * 1000,
                enabled: true,
                onBitrateChanged: (_) {},
                exportTarget: EditorExportTarget.workspaceMachine,
                onExportTargetChanged: (_) {},
                workspaceRenderAvailable: true,
              ),
            ],
          ),
        ),
        width: 900,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('video-editor-controls-golden')),
      matchesGoldenFile('goldens/video_editor_controls.png'),
    );
  });

  testWidgets('VideoEditorHeader while a workspace machine renders', (
    tester,
  ) async {
    await tester.pumpWidget(
      goldenHarness(
        RepaintBoundary(
          key: const Key('video-editor-header-golden'),
          child: VideoEditorHeader(
            project: _summary(),
            unsavedChanges: 2,
            saving: false,
            canUndo: true,
            canRedo: false,
            failure: null,
            renderingInWorkspace: true,
            onUndo: () {},
            onRedo: () {},
            onSave: () {},
            onOpen: () {},
            onNew: () {},
            onHistory: () {},
            onDismissFailure: () {},
            onOpenLibrary: () {},
          ),
        ),
        width: 900,
      ),
    );
    // The running card animates for as long as the work runs, so this waits a
    // fixed beat rather than for a stillness that never comes.
    await tester.pump(const Duration(milliseconds: 250));

    await expectLater(
      find.byKey(const Key('video-editor-header-golden')),
      matchesGoldenFile('goldens/video_editor_header.png'),
    );
  });
}
