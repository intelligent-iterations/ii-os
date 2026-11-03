import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/services/video_editor_ffmpeg.dart';
import 'package:ii_os/widgets/video_editor_stage.dart';

void main() {
  testWidgets('keeps an over-render-target stored timeline open for repair', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final project = _legacyTimeline();
    for (final target in [
      videoEditorRenderTargetFor(browser: true),
      videoEditorRenderTargetFor(browser: false),
    ]) {
      expect(
        EditorCompositionCompiler.forTarget(
          target,
        ).preflight(project).isStructurallyFeasible,
        isFalse,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoEditorStage(
            project: project,
            playhead: MediaTime.zero,
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
      ),
    );
    await tester.pump();

    expect(find.byType(IiFlutterVideoEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked ripple rejection has no consumer state effects', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_ConsumerHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _ConsumerHarness(key: key)),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('editor-mark-span-start')));
    key.currentState!.setControlledPlayhead(MediaTime.seconds(4));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-mark-span-end')));
    await tester.pump();
    final state = key.currentState!;
    final project = state.project;
    final projectChanges = state.projectChanges;
    final playheadChanges = state.playheadChanges;
    final selectionChanges = state.selectionChanges;

    await tester.tap(find.byKey(const ValueKey('editor-remove-span')));
    await tester.pump();

    expect(state.editErrors, 1);
    expect(state.project, same(project));
    expect(state.projectChanges, projectChanges);
    expect(state.playheadChanges, playheadChanges);
    expect(state.selectionChanges, selectionChanges);
    expect(find.byKey(const ValueKey('editor-span-label')), findsOneWidget);
  });
}

final class _ConsumerHarness extends StatefulWidget {
  const _ConsumerHarness({super.key});

  @override
  State<_ConsumerHarness> createState() => _ConsumerHarnessState();
}

final class _ConsumerHarnessState extends State<_ConsumerHarness> {
  EditorProject project = _lockedFollowerTimeline();
  MediaTime playhead = MediaTime.seconds(2);
  EditorSelection? selection;
  int projectChanges = 0;
  int playheadChanges = 0;
  int selectionChanges = 0;
  int editErrors = 0;

  void setControlledPlayhead(MediaTime value) =>
      setState(() => playhead = value);

  @override
  Widget build(BuildContext context) => VideoEditorStage(
    project: project,
    playhead: playhead,
    selection: selection,
    busy: false,
    canUndo: false,
    onUndoRequested: () {},
    onProjectChanged: (value) => setState(() {
      projectChanges++;
      project = value;
    }),
    onPlayheadChanged: (value) => setState(() {
      playheadChanges++;
      playhead = value;
    }),
    onSelectionChanged: (value) => setState(() {
      selectionChanges++;
      selection = value;
    }),
    onAddCaptionRequested: () {},
    onRenderRequested: () {},
    onEditError: (_) => setState(() => editErrors++),
    previewBuilder: (context, project, playhead, selection) =>
        const ColoredBox(color: Colors.black),
  );
}

EditorProject _lockedFollowerTimeline() {
  final duration = MediaTime.seconds(10);
  final source = MediaSource(
    id: 'locked-integrity-source',
    byteLength: 1,
    fileExtension: 'mp4',
    openRead: () => Stream.value(const [0]),
  );
  return EditorProject(
    id: 'locked-integrity-project',
    width: 640,
    height: 360,
    framesPerSecond: 30,
    duration: duration,
    lanes: [
      EditorLane(
        id: 'video-lane',
        label: 'Video',
        kind: EditorLaneKind.video,
        clips: [
          EditorVideoClip(
            id: 'video-clip',
            timelineStart: MediaTime.zero,
            duration: MediaTime.seconds(8),
            source: source,
            sourceRange: MediaRange(
              start: MediaTime.zero,
              duration: MediaTime.seconds(8),
            ),
            sourceDuration: MediaTime.seconds(8),
          ),
        ],
      ),
      EditorLane(
        id: 'locked-caption-lane',
        label: 'Protected captions',
        kind: EditorLaneKind.captions,
        locked: true,
        clips: [
          EditorCaptionClip(
            id: 'locked-caption',
            timelineStart: MediaTime.seconds(6),
            duration: MediaTime.seconds(1),
            text: 'Keep this in place',
          ),
        ],
      ),
    ],
  );
}

EditorProject _legacyTimeline() {
  final duration = MediaTime.seconds(25 * 60);
  final source = MediaSource(
    id: 'legacy-source',
    byteLength: 1,
    fileExtension: 'mp4',
    openRead: () => Stream.value(const [0]),
  );
  return EditorProject(
    id: 'legacy-project',
    width: 640,
    height: 360,
    framesPerSecond: 30,
    duration: duration,
    lanes: [
      EditorLane(
        id: 'video-lane',
        label: 'Video',
        kind: EditorLaneKind.video,
        clips: [
          EditorVideoClip(
            id: 'video-clip',
            timelineStart: MediaTime.zero,
            duration: duration,
            source: source,
            sourceRange: MediaRange(start: MediaTime.zero, duration: duration),
            sourceDuration: duration,
          ),
        ],
      ),
    ],
  );
}
