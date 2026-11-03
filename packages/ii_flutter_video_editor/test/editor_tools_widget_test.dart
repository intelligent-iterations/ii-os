import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

void main() {
  testWidgets('the blade cuts every lane at the playhead', (tester) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-slice')));
    await tester.pump();

    final project = key.currentState!.project;
    expect(project.laneById('video-lane')!.clips, hasLength(2));
    expect(project.laneById('audio-lane')!.clips, hasLength(2));
    expect(project.laneById('caption-lane')!.clips, hasLength(2));
  });

  testWidgets('the blade rests where there is nothing to cut', (tester) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(
      _app(_ToolsHarness(key: key, playhead: MediaTime.seconds(9))),
    );

    final blade = tester.widget<IconButton>(
      find.byKey(const ValueKey('editor-slice')),
    );
    expect(blade.onPressed, isNull);
  });

  testWidgets('split rests while linked media includes a locked lane', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(
      _app(
        _ToolsHarness(
          key: key,
          project: _lockedLinkedProject(),
          playhead: MediaTime.seconds(3),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();

    final split = tester.widget<IconButton>(
      find.byKey(const ValueKey('editor-cut')),
    );
    expect(split.onPressed, isNull);
    expect(key.currentState!.projectChanges, 0);
    expect(key.currentState!.selectionChanges, 1);
    expect(key.currentState!.errors, 0);
  });

  testWidgets('a marked span is taken out and the timeline closes up', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-mark-span-start')));
    await tester.pump();
    final timeline = find.byKey(const ValueKey('editor-timeline'));
    await tester.tapAt(tester.getTopLeft(timeline) + const Offset(300, 12));
    await tester.pump();
    expect(key.currentState!.playhead, MediaTime.seconds(5));

    await tester.tap(find.byKey(const ValueKey('editor-mark-span-end')));
    await tester.pump();
    expect(find.byKey(const ValueKey('editor-span-label')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-remove-span')));
    await tester.pump();

    expect(key.currentState!.project.duration, MediaTime.seconds(8));
    expect(find.byKey(const ValueKey('editor-span-label')), findsNothing);
  });

  testWidgets('a span with no end cannot be removed', (tester) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-mark-span-start')));
    await tester.pump();

    expect(find.byKey(const ValueKey('editor-remove-span')), findsNothing);
    expect(key.currentState!.project.duration, MediaTime.seconds(10));
  });

  testWidgets('picture and sound come apart when asked', (tester) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(
      _app(
        _ToolsHarness(key: key, project: testProject(linkPrimaryMedia: true)),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-detach-audio')));
    await tester.pump();

    final project = key.currentState!.project;
    expect(project.clipById('video-clip')!.linkGroupId, isNull);
    expect(project.clipById('audio-clip')!.linkGroupId, isNull);
  });

  testWidgets('detaching rests while nothing is joined', (tester) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();

    final detach = tester.widget<IconButton>(
      find.byKey(const ValueKey('editor-detach-audio')),
    );
    expect(detach.onPressed, isNull);
  });

  testWidgets('a transition is chosen from the clip it brings on', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-transition')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cross dissolve'));
    await tester.pumpAndSettle();

    final clip =
        key.currentState!.project.clipById('video-clip')! as EditorVideoClip;
    expect(clip.transition!.kind, EditorTransitionKind.dissolve);
    expect(clip.transition!.duration, MediaTime.seconds(1));
  });

  testWidgets('a chosen transition can be made longer', (tester) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-transition')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cross dissolve'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-transition')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow \u2014 2 seconds'));
    await tester.pumpAndSettle();

    final clip =
        key.currentState!.project.clipById('video-clip')! as EditorVideoClip;
    expect(clip.transition!.duration, MediaTime.seconds(2));
    expect(clip.transition!.kind, EditorTransitionKind.dissolve);
  });

  testWidgets('a transition can be taken back off', (tester) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    await tester.tap(find.byKey(const ValueKey('editor-clip-video-clip')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-transition')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cut straight in'));
    await tester.pumpAndSettle();

    final clip =
        key.currentState!.project.clipById('video-clip')! as EditorVideoClip;
    expect(clip.transition, isNull);
  });

  testWidgets('transitions rest while no picture clip is chosen', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(_app(_ToolsHarness(key: key)));

    final button = tester.widget<PopupMenuButton<Object>>(
      find.byKey(const ValueKey('editor-transition')),
    );
    expect(button.enabled, isFalse);
  });

  testWidgets('an edit that cannot happen reports instead of throwing', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(
      _app(_ToolsHarness(key: key, project: testProject(lockedVideo: true))),
    );

    await tester.tap(find.byKey(const ValueKey('editor-mark-span-start')));
    await tester.pump();
    final timeline = find.byKey(const ValueKey('editor-timeline'));
    await tester.tapAt(tester.getTopLeft(timeline) + const Offset(300, 12));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-mark-span-end')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-remove-span')));
    await tester.pump();

    expect(key.currentState!.errors, 1);
    expect(key.currentState!.project.duration, MediaTime.seconds(10));
  });

  testWidgets('a locked ripple follower rejects without callback effects', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(
      _app(_ToolsHarness(key: key, project: _lockedFollowerProject())),
    );

    await tester.tap(find.byKey(const ValueKey('editor-mark-span-start')));
    final timeline = find.byKey(const ValueKey('editor-timeline'));
    await tester.tapAt(tester.getTopLeft(timeline) + const Offset(300, 12));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-mark-span-end')));
    await tester.pump();
    final before = key.currentState!;
    final project = before.project;
    final projectChanges = before.projectChanges;
    final playheadChanges = before.playheadChanges;
    final selectionChanges = before.selectionChanges;

    await tester.tap(find.byKey(const ValueKey('editor-remove-span')));
    await tester.pump();

    expect(key.currentState!.errors, 1);
    expect(key.currentState!.project, same(project));
    expect(key.currentState!.projectChanges, projectChanges);
    expect(key.currentState!.playheadChanges, playheadChanges);
    expect(key.currentState!.selectionChanges, selectionChanges);
    expect(find.byKey(const ValueKey('editor-span-label')), findsOneWidget);
  });

  testWidgets('a failed edit rolls back locally without breaking the editor', (
    tester,
  ) async {
    final key = GlobalKey<_ToolsHarnessState>();
    await tester.pumpWidget(
      _app(
        _ToolsHarness(
          key: key,
          project: testProject(lockedVideo: true),
          handleErrors: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('editor-mark-span-start')));
    final timeline = find.byKey(const ValueKey('editor-timeline'));
    await tester.tapAt(tester.getTopLeft(timeline) + const Offset(300, 12));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-mark-span-end')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-remove-span')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(key.currentState!.project.duration, MediaTime.seconds(10));
    expect(
      find.text(
        'A locked lane would change when this span is removed. '
        'Unlock it or choose a span after its last clip.',
      ),
      findsOneWidget,
    );
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: child),
);

final class _ToolsHarness extends StatefulWidget {
  const _ToolsHarness({
    super.key,
    this.project,
    this.playhead,
    this.handleErrors = true,
  });

  final EditorProject? project;
  final MediaTime? playhead;
  final bool handleErrors;

  @override
  State<_ToolsHarness> createState() => _ToolsHarnessState();
}

final class _ToolsHarnessState extends State<_ToolsHarness> {
  late EditorProject project = widget.project ?? testProject();
  late MediaTime playhead = widget.playhead ?? MediaTime.seconds(3);
  EditorSelection? selection;
  int errors = 0;
  int projectChanges = 0;
  int playheadChanges = 0;
  int selectionChanges = 0;

  @override
  Widget build(BuildContext context) => IiFlutterVideoEditor(
    project: project,
    playhead: playhead,
    selection: selection,
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
    onEditError: widget.handleErrors ? (_) => setState(() => errors++) : null,
    previewBuilder: (context, project, position, selection) =>
        const ColoredBox(color: Colors.black),
  );
}

EditorProject _lockedFollowerProject() {
  final project = testProject();
  final lane = project.laneById('caption-lane')!;
  final caption = lane.clips.single as EditorCaptionClip;
  return project.copyWith(
    lanes: [
      ...project.lanes.take(2),
      EditorLane(
        id: lane.id,
        label: lane.label,
        kind: lane.kind,
        locked: true,
        hidden: lane.hidden,
        muted: lane.muted,
        clips: [
          EditorCaptionClip(
            id: caption.id,
            timelineStart: MediaTime.seconds(6),
            duration: MediaTime.seconds(1),
            text: caption.text,
            destination: caption.destination,
            style: caption.style,
          ),
        ],
      ),
    ],
  );
}

EditorProject _lockedLinkedProject() {
  final project = testProject(linkPrimaryMedia: true);
  final audioLane = project.laneById('audio-lane')!;
  return project.copyWith(
    lanes: [
      project.lanes.first,
      EditorLane(
        id: audioLane.id,
        label: audioLane.label,
        kind: audioLane.kind,
        locked: true,
        hidden: audioLane.hidden,
        muted: audioLane.muted,
        clips: audioLane.clips,
      ),
      project.lanes.last,
    ],
  );
}
