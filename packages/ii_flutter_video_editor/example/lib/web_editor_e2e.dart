import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:web/web.dart' as web;

const _ffmpegScriptSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_FFMPEG_JS_SHA256',
);
const _coreScriptSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_JS_SHA256',
);
const _coreWasmSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_WASM_SHA256',
);

const _webBundle = FfmpegWebBundle(
  ffmpegScriptUrl: 'ffmpeg/ffmpeg.js',
  ffmpegScriptSha256: _ffmpegScriptSha256,
  coreScriptUrl: 'ffmpeg/ffmpeg-core.js',
  coreScriptSha256: _coreScriptSha256,
  coreWasmUrl: 'ffmpeg/ffmpeg-core.wasm',
  coreWasmSha256: _coreWasmSha256,
);

const _safety = FfmpegSafetyPolicy(
  maxInputBytes: 16 * 1024 * 1024,
  maxOutputBytes: 16 * 1024 * 1024,
  maxTotalInputBytes: 16 * 1024 * 1024,
  maxTotalOutputBytes: 16 * 1024 * 1024,
  maxWorkspaceBytes: 48 * 1024 * 1024,
  defaultTimeout: Duration(seconds: 45),
  maxTimeout: Duration(minutes: 2),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const isDartWasm = bool.fromEnvironment('dart.tool.dart2wasm');
  final body = web.document.body!;
  body.setAttribute('data-ii-video-editor-e2e', 'running');
  body.setAttribute('data-ii-dart-wasm', '$isDartWasm');
  final engine = UniversalFfmpeg(
    configuration: const FfmpegConfiguration(
      safety: _safety,
      webBundle: _webBundle,
    ),
  );
  try {
    final seed = await engine.execute(
      FfmpegJob(
        id: 'web-editor-seed',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=c=black:s=96x64:r=10:d=0.4',
          '-c:v',
          'mpeg4',
          '-frames:v',
          '4',
          '-f',
          'mp4',
          'seed.mp4',
        ],
        outputs: const [FfmpegOutput('seed.mp4')],
      ),
    );
    final seedBytes = seed.outputBytes['seed.mp4'];
    if (!seed.isSuccess || seedBytes == null || seedBytes.length < 500) {
      throw StateError('browser seed render failed: ${seed.logs.take(20)}');
    }
    final source = MediaSource(
      id: 'web-editor-source',
      byteLength: seedBytes.length,
      fileExtension: 'mp4',
      openRead: () => Stream<List<int>>.value(seedBytes),
    );
    final project = EditorProject(
      id: 'web-editor-project',
      width: 96,
      height: 64,
      framesPerSecond: 10,
      duration: MediaTime.seconds(0.4),
      output: const MediaOutputSettings(
        videoCodec: MediaVideoCodec.mpeg4,
        audioCodec: MediaAudioCodec.aac,
        videoBitrate: 100000,
        audioBitrate: 32000,
      ),
      lanes: [
        EditorLane(
          id: 'web-video-lane',
          label: 'Video',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'web-video-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(0.4),
              source: source,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: MediaTime.seconds(0.4),
              ),
              fit: MediaFit.fill,
            ),
          ],
        ),
        EditorLane(
          id: 'web-caption-lane',
          label: 'Caption',
          kind: EditorLaneKind.captions,
          clips: [
            EditorCaptionClip(
              id: 'web-caption-clip',
              timelineStart: MediaTime.zero,
              duration: MediaTime.seconds(0.4),
              text: 'LOCAL',
              destination: const MediaRect.full(),
              style: const EditorCaptionStyle(
                fontSize: 18,
                horizontalPadding: 2,
                verticalPadding: 2,
                backgroundColor: 0x00000000,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ],
    );
    final split = splitEditorClip(
      project: project,
      selection: const EditorSelection(
        laneId: 'web-video-lane',
        clipId: 'web-video-clip',
      ),
      at: MediaTime.seconds(0.2),
    );
    if (split.project.lanes.first.clips.length != 2) {
      throw StateError('browser split did not preserve two clips');
    }
    final plan = await const EditorCompositionCompiler().compile(
      split.project,
      safety: _safety,
      mediaLimits: const MediaLimits(
        maxInputBytes: 16 * 1024 * 1024,
        maxSourceBytes: 16 * 1024 * 1024,
        maxOutputBytes: 16 * 1024 * 1024,
      ),
    );
    final rendered = await engine.execute(plan.job);
    final output = rendered.outputBytes[plan.outputName];
    if (!rendered.isSuccess || output == null || output.length < 1000) {
      throw StateError(
        'browser editor render failed: ${rendered.logs.take(20)}',
      );
    }
    final frame = await engine.execute(
      FfmpegJob(
        id: 'web-editor-frame',
        arguments: const [
          '-ss',
          '0.1',
          '-f',
          'mov',
          '-i',
          'edited.mp4',
          '-frames:v',
          '1',
          '-f',
          'image2',
          'frame.png',
        ],
        inputs: [FfmpegBytesInput('edited.mp4', output)],
        outputs: const [FfmpegOutput('frame.png')],
      ),
    );
    final png = frame.outputBytes['frame.png'];
    if (!frame.isSuccess || png == null) {
      throw StateError('browser frame decode failed: ${frame.logs.take(20)}');
    }
    final rgba = await _decodeRgba(png);
    var glyphPixels = 0;
    for (var index = 0; index < rgba.length; index += 4) {
      if (rgba[index] > 170 && rgba[index + 1] > 170 && rgba[index + 2] > 170) {
        glyphPixels++;
      }
    }
    if (glyphPixels <= 12 || glyphPixels >= 96 * 64 ~/ 3) {
      throw StateError('browser caption pixels are invalid: $glyphPixels');
    }
    body.setAttribute(
      'data-ii-video-editor-e2e',
      'pass:${output.length}:glyphs=$glyphPixels:dart-wasm=$isDartWasm',
    );
  } catch (error) {
    body.setAttribute('data-ii-video-editor-e2e', 'fail:$error');
  } finally {
    await engine.dispose();
  }
}

Future<Uint8List> _decodeRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  ui.Image? image;
  try {
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('browser frame pixels are absent');
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}
