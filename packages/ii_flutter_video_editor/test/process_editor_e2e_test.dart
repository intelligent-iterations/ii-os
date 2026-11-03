@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'desktop_engine.dart';

void main() {
  testWidgets(
    'real editor renders captions through the Universal FFmpeg process backend',
    (tester) async => tester.runAsync(_renderEditorProject),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _renderEditorProject() async {
  final state = await OwnedState.create();
  UniversalFfmpeg? engine;
  try {
    final desktopBundle = await resolveDesktopBundle();
    final ffmpeg = (
      path: desktopBundle.ffmpegPath,
      sha256: desktopBundle.ffmpegSha256,
    );
    final ffprobe = (
      path: desktopBundle.ffprobePath,
      sha256: desktopBundle.ffprobeSha256,
    );
    final sourceFile = File.fromUri(state.directory.uri.resolve('source.mp4'));
    final generated = await Process.run(ffmpeg.path, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=blue:size=160x90:rate=15',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000',
      '-t',
      '2',
      '-c:v',
      'mpeg4',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      sourceFile.path,
    ]);
    expect(generated.exitCode, 0, reason: '${generated.stderr}');
    final transparentFile = File.fromUri(
      state.directory.uri.resolve('transparent.png'),
    );
    await transparentFile.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgY'
        'AAAAAMAASsJTYQAAAAASUVORK5CYII=',
      ),
      flush: true,
    );

    const safety = FfmpegSafetyPolicy(
      maxInputBytes: 64 * 1024 * 1024,
      maxOutputBytes: 64 * 1024 * 1024,
      maxTotalInputBytes: 64 * 1024 * 1024,
      maxTotalOutputBytes: 64 * 1024 * 1024,
      maxWorkspaceBytes: 192 * 1024 * 1024,
      defaultTimeout: Duration(minutes: 2),
      maxTimeout: Duration(minutes: 3),
    );
    engine = UniversalFfmpeg(
      configuration: FfmpegConfiguration(
        safety: safety,
        desktopBundle: desktopBundle,
        nativeWorkspaceRoot: state.directory.uri
            .resolve('universal-workspaces')
            .toFilePath(),
      ),
    );
    final source = MediaSource(
      id: 'editor-live-source',
      byteLength: await sourceFile.length(),
      fileExtension: 'mp4',
      openRead: sourceFile.openRead,
    );
    final range = MediaRange(
      start: MediaTime.seconds(0.25),
      duration: MediaTime.seconds(1),
    );
    final transparent = MediaSource(
      id: 'editor-transparent-source',
      byteLength: await transparentFile.length(),
      fileExtension: 'png',
      openRead: transparentFile.openRead,
    );
    final project = EditorProject(
      id: 'editor-live-project',
      width: 160,
      height: 90,
      framesPerSecond: 15,
      duration: MediaTime.seconds(1),
      output: const MediaOutputSettings(
        videoCodec: MediaVideoCodec.mpeg4,
        audioCodec: MediaAudioCodec.aac,
        videoBitrate: 500000,
        audioBitrate: 64000,
      ),
      lanes: [
        EditorLane(
          id: 'live-video-lane',
          label: 'Video',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'live-video',
              timelineStart: MediaTime.zero,
              duration: range.duration,
              source: source,
              sourceRange: range,
              fit: MediaFit.fill,
            ),
          ],
        ),
        EditorLane(
          id: 'live-transparent-lane',
          label: 'Transparent overlay',
          kind: EditorLaneKind.video,
          clips: [
            EditorVideoClip(
              id: 'live-transparent',
              timelineStart: MediaTime.zero,
              duration: range.duration,
              source: transparent,
              sourceRange: MediaRange(
                start: MediaTime.zero,
                duration: range.duration,
              ),
              fit: MediaFit.fill,
            ),
          ],
        ),
        EditorLane(
          id: 'live-audio-lane',
          label: 'Audio',
          kind: EditorLaneKind.audio,
          clips: [
            EditorAudioClip(
              id: 'live-audio',
              timelineStart: MediaTime.milliseconds(175),
              duration: MediaTime.milliseconds(825),
              source: source,
              sourceRange: MediaRange(
                start: range.start,
                duration: MediaTime.milliseconds(825),
              ),
            ),
          ],
        ),
        EditorLane(
          id: 'live-caption-lane',
          label: 'Captions',
          kind: EditorLaneKind.captions,
          clips: [
            EditorCaptionClip(
              id: 'live-caption',
              timelineStart: MediaTime.seconds(0.25),
              duration: MediaTime.seconds(0.5),
              text: 'LOCAL',
              destination: const MediaRect(x: 0, y: 0, width: 1, height: 1),
              style: const EditorCaptionStyle(
                fontSize: 24,
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

    final plan = await const EditorCompositionCompiler().compile(
      project,
      safety: safety,
      mediaLimits: const MediaLimits(
        maxInputBytes: 64 * 1024 * 1024,
        maxSourceBytes: 64 * 1024 * 1024,
        maxOutputBytes: 64 * 1024 * 1024,
      ),
    );
    final rendered = await engine.execute(plan.job);
    final maybeOutputBytes = rendered.outputBytes[plan.outputName];
    expect(rendered.isSuccess, isTrue, reason: rendered.logs.join('\n'));
    expect(maybeOutputBytes, isNotNull);
    final outputBytes = maybeOutputBytes!;
    expect(outputBytes.length, greaterThan(1000));

    final output = File.fromUri(state.directory.uri.resolve('output.mp4'));
    await output.writeAsBytes(outputBytes, flush: true);
    final probe = await Process.run(ffprobe.path, [
      '-v',
      'error',
      '-show_entries',
      'stream=codec_type,width,height',
      '-show_entries',
      'format=duration',
      '-of',
      'json',
      output.path,
    ]);
    expect(probe.exitCode, 0, reason: '${probe.stderr}');
    final payload = jsonDecode(probe.stdout as String) as Map<String, Object?>;
    final streams = (payload['streams']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final video = streams.singleWhere(
      (stream) => stream['codec_type'] == 'video',
    );
    expect(video['width'], 160);
    expect(video['height'], 90);
    expect(streams.any((stream) => stream['codec_type'] == 'audio'), isTrue);

    final before = await _readRgbFrame(ffmpeg.path, output.path, 0.1);
    final captioned = await _readRgbFrame(ffmpeg.path, output.path, 0.5);
    expect(_bluePixelCount(before), greaterThan(160 * 90 * 9 ~/ 10));
    expect(_brightPixelCount(before), lessThan(5));
    expect(_brightPixelCount(captioned), greaterThan(25));
    expect(_brightPixelCount(captioned), lessThan(160 * 90 ~/ 3));
    expect(
      await _initialSilenceEnd(ffmpeg.path, output.path),
      closeTo(0.175, 0.035),
    );
  } finally {
    await engine?.dispose();
    await state.dispose();
  }
}

Future<double> _initialSilenceEnd(String ffmpeg, String input) async {
  final detected = await Process.run(ffmpeg, [
    '-hide_banner',
    '-loglevel',
    'info',
    '-i',
    input,
    '-af',
    'silencedetect=noise=-40dB:d=0.05',
    '-f',
    'null',
    '-',
  ]);
  expect(detected.exitCode, 0, reason: '${detected.stderr}');
  final match = RegExp(
    r'silence_end:\s*([0-9]+(?:\.[0-9]+)?)',
  ).firstMatch('${detected.stderr}');
  expect(match, isNotNull, reason: '${detected.stderr}');
  return double.parse(match!.group(1)!);
}

Future<List<int>> _readRgbFrame(
  String ffmpeg,
  String input,
  double seconds,
) async {
  final sampled = await Process.run(ffmpeg, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-ss',
    seconds.toString(),
    '-i',
    input,
    '-vf',
    'format=rgb24',
    '-frames:v',
    '1',
    '-f',
    'rawvideo',
    'pipe:1',
  ], stdoutEncoding: null);
  expect(sampled.exitCode, 0, reason: '${sampled.stderr}');
  final bytes = sampled.stdout as List<int>;
  expect(bytes, hasLength(160 * 90 * 3));
  return bytes;
}

int _bluePixelCount(List<int> rgb) {
  var count = 0;
  for (var index = 0; index < rgb.length; index += 3) {
    if (rgb[index] < 80 && rgb[index + 1] < 80 && rgb[index + 2] > 150) {
      count++;
    }
  }
  return count;
}

int _brightPixelCount(List<int> rgb) {
  var count = 0;
  for (var index = 0; index < rgb.length; index += 3) {
    if (rgb[index] > 170 && rgb[index + 1] > 170 && rgb[index + 2] > 170) {
      count++;
    }
  }
  return count;
}
