import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  testWidgets('controlled editor selects and splits the chosen clip', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();
    expect(key.currentState!.selection?.clipId, 'video-clip');

    await tester.tap(find.byKey(const ValueKey('editor-cut')));
    await tester.pump();
    final clips = key.currentState!.project.lanes.first.clips;
    expect(clips, hasLength(2));
    expect(clips[0].duration, MediaTime.seconds(3));
    expect(clips[1].duration, MediaTime.seconds(5));
    expect(key.currentState!.selection?.clipId, clips[1].id);
    expect(find.byKey(ValueKey('editor-clip-${clips[1].id}')), findsOneWidget);
  });

  testWidgets('Delete removes the selected clip and Ctrl+Z restores it', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(key.currentState!.project.clipById('video-clip'), isNull);
    expect(key.currentState!.selection, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(key.currentState!.project.clipById('video-clip'), isNotNull);
    expect(key.currentState!.selection?.clipId, 'video-clip');
  });

  testWidgets('caller-owned undo replaces the local command stack', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key, useExternalUndo: true)));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(key.currentState!.externalUndoRequests, 1);
    expect(key.currentState!.project.clipById('video-clip'), isNotNull);
  });

  testWidgets('remove button deletes the selected clip', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-caption-clip')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-remove-clip')));
    await tester.pump();

    expect(key.currentState!.project.clipById('caption-clip'), isNull);
    expect(key.currentState!.selection, isNull);
  });

  testWidgets('holding a clip opens useful actions and can remove it', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));

    await tester.longPress(
      find.byKey(const ValueKey('editor-clip-video-clip')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clip actions'), findsOneWidget);
    expect(find.text('Split at playhead'), findsOneWidget);
    expect(find.text('Remove clip'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-clip-action-remove')));
    await tester.pumpAndSettle();

    expect(key.currentState!.project.clipById('video-clip'), isNull);
  });

  testWidgets('timeline scrubbing and render command emit callbacks', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));
    final timeline = find.byKey(const ValueKey('editor-timeline'));
    final origin = tester.getTopLeft(timeline);

    await tester.tapAt(origin + const Offset(240, 12));
    await tester.pump();
    expect(key.currentState!.playhead, MediaTime.seconds(4));
    expect(find.text('0:04.000'), findsOneWidget);

    final render = find.byKey(const ValueKey('editor-render'));
    await tester.ensureVisible(render);
    await tester.pump();
    await tester.tap(render);
    expect(key.currentState!.renderRequests, 1);
    final caption = find.byKey(const ValueKey('editor-add-caption'));
    await tester.ensureVisible(caption);
    await tester.pump();
    await tester.tap(caption);
    expect(key.currentState!.captionRequests, 1);
    final image = find.byKey(const ValueKey('editor-add-image-overlay'));
    await tester.ensureVisible(image);
    await tester.pump();
    await tester.tap(image);
    expect(key.currentState!.imageRequests, 1);
  });

  testWidgets('dragging a clip moves it without scrubbing the playhead', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));

    await tester.drag(
      find.byKey(const ValueKey('editor-clip-video-clip')),
      const Offset(60, 0),
    );
    await tester.pump();

    expect(
      key.currentState!.project.lanes.first.clips.single.timelineStart,
      MediaTime.seconds(1),
    );
    expect(key.currentState!.playhead, MediaTime.seconds(3));
    expect(key.currentState!.selection?.clipId, 'video-clip');
  });

  testWidgets('selected clip exposes source-aware trim handles', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));
    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('editor-clip-trim-start-video-clip')),
      const Offset(60, 0),
    );
    await tester.pump();

    final clip =
        key.currentState!.project.lanes.first.clips.single as EditorVideoClip;
    expect(clip.timelineStart, MediaTime.seconds(1));
    expect(clip.duration, MediaTime.seconds(7));
    expect(clip.sourceRange.start, MediaTime.seconds(2));
    expect(key.currentState!.playhead, MediaTime.seconds(3));
  });

  testWidgets('snap control is visible and can disable magnetic snapping', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Harness()));
    final snap = find.byKey(const ValueKey('editor-snap-toggle'));
    expect(snap, findsOneWidget);
    expect(find.byTooltip('Disable timeline snapping'), findsOneWidget);
    await tester.tap(snap);
    await tester.pump();
    expect(find.byTooltip('Enable timeline snapping'), findsOneWidget);
  });

  testWidgets('lane menu edits visibility and undo restores it', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-lane-menu-video-lane')));
    await tester.pumpAndSettle();
    final visibility = find.byKey(
      const ValueKey('editor-lane-visibility-video-lane'),
    );
    await tester.ensureVisible(visibility);
    await tester.tap(visibility);
    await tester.pumpAndSettle();
    expect(key.currentState!.project.laneById('video-lane')!.hidden, isTrue);

    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pump();
    expect(key.currentState!.project.laneById('video-lane')!.hidden, isFalse);
  });

  testWidgets('selected image overlay can be resized in the preview', (
    tester,
  ) async {
    final project = addEditorImageOverlay(
      project: testProject(),
      laneId: 'image-lane',
      clipId: 'image-clip',
      source: testSource('image-source', 'png'),
      timelineStart: MediaTime.zero,
      duration: MediaTime.seconds(6),
    );
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key, project: project)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-image-clip')));
    await tester.pump();
    expect(find.byKey(const ValueKey('editor-visual-resize')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('editor-visual-resize')),
      const Offset(24, 18),
    );
    await tester.pump();

    final clip =
        key.currentState!.project.clipById('image-clip')! as EditorVideoClip;
    expect(clip.destination.width, greaterThan(0.35));
    expect(clip.destination.height, greaterThan(0.35));
  });

  testWidgets('zoom and narrow layouts remain usable without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const _Harness()));

    for (final tool in ['editor-zoom-in', 'editor-zoom-out']) {
      final button = find.byKey(ValueKey(tool));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Captions'), findsOneWidget);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: child),
);

final class _Harness extends StatefulWidget {
  const _Harness({super.key, this.project, this.useExternalUndo = false});

  final EditorProject? project;
  final bool useExternalUndo;

  @override
  State<_Harness> createState() => _HarnessState();
}

final class _HarnessState extends State<_Harness> {
  late EditorProject project = widget.project ?? testProject();
  MediaTime playhead = MediaTime.seconds(3);
  EditorSelection? selection;
  int renderRequests = 0;
  int captionRequests = 0;
  int imageRequests = 0;
  int externalUndoRequests = 0;

  @override
  Widget build(BuildContext context) {
    return IiFlutterVideoEditor(
      project: project,
      playhead: playhead,
      selection: selection,
      onProjectChanged: (value) => setState(() => project = value),
      onPlayheadChanged: (value) => setState(() => playhead = value),
      onSelectionChanged: (value) => setState(() => selection = value),
      canUndo: widget.useExternalUndo,
      onUndoRequested: widget.useExternalUndo
          ? () => externalUndoRequests++
          : null,
      onRenderRequested: () => renderRequests++,
      onAddCaptionRequested: () => captionRequests++,
      onAddImageOverlayRequested: () => imageRequests++,
      previewBuilder: (context, project, position, selection) =>
          const ColoredBox(color: Colors.black),
    );
  }
}
