import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'support.dart';

const _cutClip = EditorSelection(
  laneId: 'video-lane',
  clipId: 'video-clip.s4000000',
);

EditorProject _joinedAt(EditorTransitionKind kind, {String color = '000000'}) =>
    setEditorClipTransition(
      project: sliceEditorProject(
        project: testProject(),
        at: MediaTime.seconds(4),
      ),
      selection: _cutClip,
      transition: EditorTransition(
        kind: kind,
        duration: MediaTime.seconds(1),
        color: color,
      ),
    );

String _filterGraph(EditorRenderPlan plan) {
  final index = plan.job.arguments.indexOf('-filter_complex');
  expect(index, greaterThanOrEqualTo(0));
  return plan.job.arguments[index + 1];
}

Future<EditorRenderPlan> _compile(
  WidgetTester tester,
  EditorProject project,
) async {
  final plan = await tester.runAsync(
    () => const EditorCompositionCompiler().compile(project),
  );
  expect(plan, isNotNull);
  return plan!;
}

void main() {
  testWidgets('a dissolve holds the outgoing picture and fades the next in', (
    tester,
  ) async {
    final plan = await _compile(
      tester,
      _joinedAt(EditorTransitionKind.dissolve),
    );
    final graph = _filterGraph(plan);

    expect(graph, contains('tpad=stop_duration=1.000000:stop_mode=clone'));
    expect(graph, contains('fade=t=in:st=4.000000:d=1.000000:alpha=1'));
    expect(
      () => const FfmpegSafetyPolicy().validate(plan.job),
      returnsNormally,
    );
  });

  testWidgets('a dip lays a colour over the cut and holds nothing', (
    tester,
  ) async {
    final plan = await _compile(
      tester,
      _joinedAt(EditorTransitionKind.dipToColor, color: 'FFFFFF'),
    );
    final graph = _filterGraph(plan);

    expect(graph, contains('color=c=0xFFFFFF'));
    expect(graph, contains('fade=t=in:st=0.000000:d=0.500000:alpha=1'));
    expect(graph, contains('fade=t=out:st=0.500000:d=0.500000:alpha=1'));
    expect(graph, isNot(contains('tpad=')));
    expect(
      () => const FfmpegSafetyPolicy().validate(plan.job),
      returnsNormally,
    );
  });

  testWidgets('a slide moves the next picture in from the edge', (
    tester,
  ) async {
    final plan = await _compile(
      tester,
      _joinedAt(EditorTransitionKind.slideFromRight),
    );
    final graph = _filterGraph(plan);

    expect(graph, contains('tpad=stop_duration=1.000000:stop_mode=clone'));
    expect(graph, contains("overlay=x='if(lt(t,5.000000),"));
    expect(graph, isNot(contains('fade=t=in')));
    expect(
      () => const FfmpegSafetyPolicy().validate(plan.job),
      returnsNormally,
    );
  });

  testWidgets('a project with no transition compiles as it always did', (
    tester,
  ) async {
    final plan = await _compile(tester, testProject());
    final graph = _filterGraph(plan);

    expect(graph, isNot(contains('tpad=')));
    expect(graph, isNot(contains('fade=')));
  });

  testWidgets('an opening transition fades in over the background', (
    tester,
  ) async {
    final opened = setEditorClipTransition(
      project: testProject(),
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      transition: EditorTransition(
        kind: EditorTransitionKind.dissolve,
        duration: MediaTime.seconds(1),
      ),
    );
    final plan = await _compile(tester, opened);
    final graph = _filterGraph(plan);

    expect(graph, contains('fade=t=in:st=0.000000:d=1.000000:alpha=1'));
    expect(graph, isNot(contains('tpad=')));
  });
}
