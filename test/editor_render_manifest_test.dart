import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_render_manifest.dart';
import 'package:ii_os/repositories/editor_render_repository.dart';
import 'package:ii_os/repositories/source_asset_repository.dart';
import 'package:ii_os/services/editor_render_dispatcher.dart';
import 'package:ii_os/services/editor_render_publisher.dart';
import 'package:ii_os/services/video_editor_ffmpeg.dart';

final _bytes = Uint8List.fromList(List<int>.filled(32, 3));

MediaSource _source(String id, String extension) => MediaSource(
  id: id,
  byteLength: _bytes.length,
  fileExtension: extension,
  openRead: () => Stream<List<int>>.value(_bytes),
);

EditorProject _project() => EditorProject(
  id: 'render-project',
  width: 640,
  height: 360,
  framesPerSecond: 30,
  duration: MediaTime.seconds(6),
  output: const MediaOutputSettings(
    videoCodec: MediaVideoCodec.mpeg4,
    audioCodec: MediaAudioCodec.aac,
    videoBitrate: 900000,
    audioBitrate: 96000,
  ),
  lanes: [
    EditorLane(
      id: 'video-lane',
      label: 'Picture',
      kind: EditorLaneKind.video,
      clips: [
        EditorVideoClip(
          id: 'video-clip',
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(6),
          source: _source('media-video', 'mp4'),
          sourceRange: MediaRange(
            start: MediaTime.zero,
            duration: MediaTime.seconds(6),
          ),
          sourceDuration: MediaTime.seconds(6),
        ),
      ],
    ),
    EditorLane(
      id: 'audio-lane',
      label: 'Sound',
      kind: EditorLaneKind.audio,
      clips: [
        EditorAudioClip(
          id: 'audio-clip',
          timelineStart: MediaTime.zero,
          duration: MediaTime.seconds(6),
          source: _source('media-audio', 'm4a'),
          sourceRange: MediaRange(
            start: MediaTime.zero,
            duration: MediaTime.seconds(6),
          ),
          sourceDuration: MediaTime.seconds(6),
        ),
      ],
    ),
  ],
);

final class _RecordingSourceAssets implements SourceAssetRepository {
  final List<String> uploaded = [];

  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async {
    uploaded.add('$filename:$contentType');
    return 'asset-${uploaded.length}';
  }
}

final class _RecordingRenders implements EditorRenderRepository {
  String? submittedManifest;
  bool? submittedGhostMode;

  @override
  Future<String> submit({
    required String workspaceId,
    required String renderManifest,
    required bool ghostMode,
  }) async {
    submittedManifest = renderManifest;
    submittedGhostMode = ghostMode;
    return 'job-9';
  }
}

Future<EditorRenderPlan> _plan() =>
    const EditorCompositionCompiler().compile(_project());

void main() {
  test('workspace dispatch defaults to the shared target compiler', () {
    final dispatcher = WorkspaceEditorRenderDispatcher(
      renders: _RecordingRenders(),
      sourceAssets: _RecordingSourceAssets(),
    );

    expect(dispatcher.compiler, same(videoEditorCompiler));
  });

  testWidgets('dispatch sends only the manifest to the dedicated render port', (
    tester,
  ) async {
    final renders = _RecordingRenders();
    final result = await tester.runAsync(
      () =>
          WorkspaceEditorRenderDispatcher(
            renders: renders,
            sourceAssets: _RecordingSourceAssets(),
          ).dispatch(
            workspaceId: 'workspace-1',
            expectedBucket: 'bucket-1',
            timeline: _project(),
            ghostMode: true,
          ),
    );

    expect(result, 'job-9');
    expect(renders.submittedGhostMode, isTrue);
    expect(jsonDecode(renders.submittedManifest!)['outputName'], 'output.mp4');
  });

  testWidgets('a render describes every file it reads', (tester) async {
    final assets = _RecordingSourceAssets();
    final manifest = await tester.runAsync(
      () async => EditorRenderPublisher(sourceAssets: assets).publish(
        workspaceId: 'workspace-1',
        expectedBucket: 'bucket-1',
        plan: await _plan(),
      ),
    );

    expect(manifest, isNotNull);
    expect(manifest!.inputs, hasLength(2));
    expect(manifest.inputs.first.name, 'input-0.mp4');
    expect(manifest.inputs.last.name, 'input-1.m4a');
    expect(assets.uploaded, ['input-0.mp4:video/mp4', 'input-1.m4a:audio/mp4']);
    for (final input in manifest.inputs) {
      expect(manifest.arguments, contains(input.name));
      expect(input.byteLength, _bytes.length);
    }
    expect(manifest.outputName, 'output.mp4');
    expect(manifest.mediaType, 'video/mp4');
    expect(manifest.expectedDuration, const Duration(seconds: 6));
  });

  testWidgets('media the workspace already holds is not sent again', (
    tester,
  ) async {
    final assets = _RecordingSourceAssets();
    final manifest = await tester.runAsync(
      () async => EditorRenderPublisher(sourceAssets: assets).publish(
        workspaceId: 'workspace-1',
        expectedBucket: 'bucket-1',
        plan: await _plan(),
        knownAssetIds: const {'media-video': 'already-stored'},
      ),
    );

    expect(assets.uploaded, ['input-1.m4a:audio/mp4']);
    expect(manifest!.inputs.first.assetId, 'already-stored');
  });

  testWidgets('a described render rebuilds into the job it came from', (
    tester,
  ) async {
    final plan = await tester.runAsync(_plan);
    final manifest = await tester.runAsync(
      () =>
          EditorRenderPublisher(sourceAssets: _RecordingSourceAssets()).publish(
            workspaceId: 'workspace-1',
            expectedBucket: 'bucket-1',
            plan: plan!,
          ),
    );

    final restored = EditorRenderManifest.fromJson(manifest!.toJson());
    final job = restored.toJob({
      for (final input in restored.inputs) input.name: _bytes,
    });

    expect(job.arguments, plan!.job.arguments);
    expect(job.outputs.single.name, plan.outputName);
    expect(() => const FfmpegSafetyPolicy().validate(job), returnsNormally);
  });

  testWidgets('a render whose bytes did not arrive is refused', (tester) async {
    final manifest = await tester.runAsync(
      () async =>
          EditorRenderPublisher(sourceAssets: _RecordingSourceAssets()).publish(
            workspaceId: 'workspace-1',
            expectedBucket: 'bucket-1',
            plan: await _plan(),
          ),
    );

    expect(
      () => manifest!.toJob({'input-0.mp4': _bytes}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => manifest!.toJob({
        for (final input in manifest.inputs)
          input.name: Uint8List.fromList(const [1, 2, 3]),
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('a render described by another version is refused', () {
    expect(
      () => EditorRenderManifest.fromJson(const {'version': 99}),
      throwsA(isA<FormatException>()),
    );
  });
}
