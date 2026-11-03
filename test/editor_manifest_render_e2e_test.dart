@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/editor_render_manifest.dart';
import 'package:ii_os/repositories/source_asset_repository.dart';
import 'package:ii_os/services/editor_manifest_renderer.dart';
import 'package:ii_os/services/editor_render_publisher.dart';

import 'desktop_engine.dart';

const _width = 160;
const _height = 90;
const _safety = FfmpegSafetyPolicy(
  maxInputBytes: 64 * 1024 * 1024,
  maxOutputBytes: 64 * 1024 * 1024,
  maxTotalInputBytes: 64 * 1024 * 1024,
  maxTotalOutputBytes: 64 * 1024 * 1024,
  maxWorkspaceBytes: 192 * 1024 * 1024,
  defaultTimeout: Duration(minutes: 2),
  maxTimeout: Duration(minutes: 3),
);

final class _StubSourceAssets implements SourceAssetRepository {
  int uploads = 0;

  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async => 'asset-${++uploads}';
}

void main() {
  testWidgets(
    'a render described here comes out as a video somewhere else',
    (tester) async => tester.runAsync(_renderThroughAManifest),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _renderThroughAManifest() async {
  final state = await OwnedState.create();
  UniversalFfmpeg? engine;
  try {
    final bundle = await resolveDesktopBundle();
    final blue = await _solidSource(bundle, state, 'blue');
    final red = await _solidSource(bundle, state, 'red');
    engine = UniversalFfmpeg(
      configuration: FfmpegConfiguration(
        safety: _safety,
        desktopBundle: bundle,
        nativeWorkspaceRoot: state.directory.uri
            .resolve('universal-workspaces')
            .toFilePath(),
      ),
    );

    // What the browser does: compile the timeline, then describe the render.
    final plan = await const EditorCompositionCompiler().compile(
      _joinedProject(blue.source, red.source),
      safety: _safety,
      mediaLimits: const MediaLimits(
        maxInputBytes: 64 * 1024 * 1024,
        maxSourceBytes: 64 * 1024 * 1024,
        maxOutputBytes: 64 * 1024 * 1024,
      ),
    );
    final assets = _StubSourceAssets();
    final manifest = await EditorRenderPublisher(sourceAssets: assets).publish(
      workspaceId: 'workspace-1',
      expectedBucket: 'bucket-1',
      plan: plan,
    );
    expect(assets.uploads, 2, reason: 'both clips go to the workspace');

    // What the other machine does: read the description, fetch the files it
    // names, and run it. Nothing here has ever seen a timeline.
    final delivered = EditorRenderManifest.fromJson(
      jsonDecode(jsonEncode(manifest.toJson())) as Map<String, Object?>,
    );
    final fetched = <String, Uint8List>{
      for (final input in delivered.inputs)
        input.name: input.assetId == 'asset-1' ? blue.bytes : red.bytes,
    };
    final rendered = await renderEditorManifest(
      manifest: delivered,
      inputs: fetched,
      engine: engine,
      safety: _safety,
    );

    expect(rendered.length, greaterThan(1000));
    final output = File.fromUri(state.directory.uri.resolve('output.mp4'));
    await output.writeAsBytes(rendered, flush: true);
    final probe = await Process.run(bundle.ffprobePath, [
      '-v',
      'error',
      '-show_entries',
      'stream=codec_type,width,height',
      '-of',
      'json',
      output.path,
    ]);
    expect(probe.exitCode, 0, reason: '${probe.stderr}');
    final streams =
        ((jsonDecode(probe.stdout as String)
                    as Map<String, Object?>)['streams']!
                as List<Object?>)
            .cast<Map<String, Object?>>();
    final video = streams.singleWhere(
      (stream) => stream['codec_type'] == 'video',
    );
    expect(video['width'], _width);
    expect(video['height'], _height);

    // The transition the timeline asked for is in the pixels, so the machine
    // rendered the edit rather than one of its halves.
    final opening = await _centrePixel(bundle.ffmpegPath, output.path, 0.5);
    expect(opening.$3, greaterThan(150), reason: 'the first clip is blue');
    expect(opening.$1, lessThan(60));
    final closing = await _centrePixel(bundle.ffmpegPath, output.path, 1.9);
    expect(closing.$1, greaterThan(150), reason: 'the second clip is red');
    expect(closing.$3, lessThan(60));
    final blended = await _centrePixel(bundle.ffmpegPath, output.path, 1.3);
    expect(blended.$1, greaterThan(60), reason: 'red has arrived');
    expect(blended.$3, greaterThan(60), reason: 'blue is still there');
    expect(blended.$1, lessThan(210));
    expect(blended.$3, lessThan(210));
  } finally {
    await engine?.dispose();
    await state.dispose();
  }
}

EditorProject _joinedProject(MediaSource blue, MediaSource red) =>
    EditorProject(
      id: 'manifest-render-project',
      width: _width,
      height: _height,
      framesPerSecond: 15,
      duration: MediaTime.seconds(2),
      output: const MediaOutputSettings(
        videoCodec: MediaVideoCodec.mpeg4,
        audioCodec: MediaAudioCodec.aac,
        videoBitrate: 900000,
        audioBitrate: 64000,
      ),
      lanes: [
        EditorLane(
          id: 'video-lane',
          label: 'Picture',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'first-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(1),
              source: blue,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(1),
              ),
              fit: MediaFit.fill,
            ),
            EditorVideoClip(
              id: 'second-clip',
              timelineStart: MediaTime.seconds(1),
              duration: MediaTime.seconds(1),
              source: red,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(1),
              ),
              fit: MediaFit.fill,
              transition: EditorTransition(
                kind: EditorTransitionKind.dissolve,
                duration: MediaTime.milliseconds(600),
              ),
            ),
          ],
        ),
      ],
    );

Future<({MediaSource source, Uint8List bytes})> _solidSource(
  FfmpegDesktopBundle bundle,
  OwnedState state,
  String color,
) async {
  final file = File.fromUri(state.directory.uri.resolve('$color.mp4'));
  final generated = await Process.run(bundle.ffmpegPath, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'color=c=$color:size=${_width}x$_height:rate=15',
    '-t',
    '2',
    '-c:v',
    'mpeg4',
    '-pix_fmt',
    'yuv420p',
    file.path,
  ]);
  expect(generated.exitCode, 0, reason: '${generated.stderr}');
  final bytes = await file.readAsBytes();
  return (
    source: MediaSource(
      id: 'manifest-$color-source',
      byteLength: bytes.length,
      fileExtension: 'mp4',
      openRead: file.openRead,
    ),
    bytes: bytes,
  );
}

Future<(int, int, int)> _centrePixel(
  String ffmpeg,
  String output,
  double seconds,
) async {
  final sampled = await Process.run(ffmpeg, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    output,
    '-ss',
    seconds.toString(),
    '-vf',
    'format=rgb24',
    '-frames:v',
    '1',
    '-f',
    'rawvideo',
    'pipe:1',
  ], stdoutEncoding: null);
  expect(sampled.exitCode, 0, reason: '${sampled.stderr}');
  final rgb = sampled.stdout as List<int>;
  expect(rgb, hasLength(_width * _height * 3));
  final index = ((_height ~/ 2) * _width + _width ~/ 2) * 3;
  return (rgb[index], rgb[index + 1], rgb[index + 2]);
}
