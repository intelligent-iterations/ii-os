import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/services/video_editor_render_readiness.dart';

void main() {
  test('inspection is target-specific and never opens a media source', () {
    var sourceReads = 0;
    final source = MediaSource(
      id: 'private-source-id',
      byteLength: 32,
      fileExtension: 'mp4',
      openRead: () {
        sourceReads++;
        return Stream.value(Uint8List(32));
      },
    );
    final project = _projectWithClips(source, 2);
    final readiness = VideoEditorRenderReadinessService(
      compiler: const EditorCompositionCompiler.forTarget(
        EditorRenderTarget(mediaLimits: MediaLimits(maxLayerCount: 1)),
      ),
    );

    final report = readiness.inspect(project);

    expect(report.isStructurallyFeasible, isFalse);
    expect(report.footprint?.emittedLayerCount, 2);
    expect(sourceReads, 0);
  });

  test('every typed issue has safe actionable host copy', () {
    final readiness = VideoEditorRenderReadinessService(
      compiler: const EditorCompositionCompiler.forTarget(EditorRenderTarget()),
    );

    for (final code in EditorRenderIssueCode.values) {
      final message = readiness.messageForIssue(
        EditorRenderIssue(
          code: code,
          message: 'provider stack private-source-id',
          laneId: 'private-lane-id',
          clipId: 'private-clip-id',
          sourceId: 'private-source-id',
          actual: 17,
          maximum: 16,
        ),
        intent: VideoEditorRenderIntent.localRender,
      );
      expect(message, isNotEmpty, reason: code.name);
      expect(message, isNot(contains('provider')), reason: code.name);
      expect(message, isNot(contains('private-')), reason: code.name);
      expect(message, endsWith('.'), reason: code.name);
    }
  });
}

EditorProject _projectWithClips(MediaSource source, int count) {
  final clips = <EditorVideoClip>[];
  for (var index = 0; index < count; index++) {
    clips.add(
      EditorVideoClip(
        id: 'clip-$index',
        timelineStart: MediaTime.seconds(index),
        duration: MediaTime.seconds(1),
        source: source,
        sourceRange: MediaRange(
          start: MediaTime.seconds(index),
          duration: MediaTime.seconds(1),
        ),
        sourceDuration: MediaTime.seconds(count),
      ),
    );
  }
  return EditorProject(
    id: 'project',
    width: 640,
    height: 360,
    framesPerSecond: 30,
    duration: MediaTime.seconds(count),
    lanes: [
      EditorLane(
        id: 'video-lane',
        label: 'Video',
        kind: EditorLaneKind.video,
        clips: clips,
      ),
    ],
  );
}
