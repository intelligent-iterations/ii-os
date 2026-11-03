@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/services/editor_media_source.dart';
import 'package:ii_os/services/video_editor_ffmpeg.dart';
import 'package:ii_os/services/video_editor_project.dart';

import 'desktop_engine.dart';

const _fixture =
    'test/fixtures/video_editor/media/linked-offset-v1/linked-offset.mov';

void main() {
  testWidgets(
    'real delayed audio survives probe, placement, compile, and decode',
    (tester) async => tester.runAsync(_proveLinkedTiming),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _proveLinkedTiming() async {
  final state = await OwnedState.create();
  UniversalFfmpeg? engine;
  try {
    final bundle = await resolveDesktopBundle();
    engine = UniversalFfmpeg(
      configuration: FfmpegConfiguration(
        safety: videoEditorSafety,
        desktopBundle: bundle,
        nativeWorkspaceRoot: state.directory.uri
            .resolve('universal-workspaces')
            .toFilePath(),
      ),
    );
    final bytes = await File(_fixture).readAsBytes();
    final media = await prepareLocalEditorMedia(
      ffmpeg: engine,
      id: 'linked-offset-real',
      filename: 'linked-offset.mov',
      path: _fixture,
      bytes: bytes,
      expectedContentType: 'video/mp4',
    );

    expect(media.videoTiming!.presentationStart, Duration.zero);
    expect(media.videoTiming!.duration, const Duration(seconds: 2));
    expect(
      media.audioTiming!.presentationStart,
      const Duration(milliseconds: 175),
    );
    expect(media.audioTiming!.duration, const Duration(milliseconds: 1825));

    final project = addLocalMediaToNewLanes(
      projectId: 'real-linked-timing',
      project: null,
      media: media,
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
      linkGroupId: 'linked-streams',
      browserOutput: false,
      videoBitrate: 500000,
    );
    final audio = project.clipById('audio-clip')! as EditorAudioClip;
    expect(audio.timelineStart, MediaTime.milliseconds(175));
    expect(audio.sourceRange.start, MediaTime.zero);

    final split = splitEditorClip(
      project: project,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      at: MediaTime.seconds(1),
    ).project;
    final audioClips = split
        .laneById('audio-lane')!
        .clips
        .cast<EditorAudioClip>();
    expect(audioClips, hasLength(2));
    expect(audioClips.first.timelineStart, MediaTime.milliseconds(175));
    expect(audioClips.first.sourceRange.start, MediaTime.zero);
    expect(audioClips.first.duration, MediaTime.milliseconds(825));
    expect(audioClips.last.timelineStart, MediaTime.seconds(1));
    expect(audioClips.last.sourceRange.start, MediaTime.milliseconds(825));
    expect(audioClips.last.duration, MediaTime.seconds(1));

    final plan = await videoEditorCompiler.compile(split);
    final rendered = await engine.execute(plan.job);
    expect(rendered.isSuccess, isTrue, reason: rendered.logs.join('\n'));
    final outputBytes = rendered.outputBytes[plan.outputName];
    expect(outputBytes, isNotNull);
    final output = File.fromUri(state.directory.uri.resolve(plan.outputName));
    await output.writeAsBytes(outputBytes!, flush: true);

    final red = await _centrePixel(bundle.ffmpegPath, output.path, 0.10);
    final blue = await _centrePixel(bundle.ffmpegPath, output.path, 0.30);
    final blueAfterSplit = await _centrePixel(
      bundle.ffmpegPath,
      output.path,
      1.05,
    );
    expect(red.$1, greaterThan(150));
    expect(red.$3, lessThan(80));
    expect(blue.$1, lessThan(80));
    expect(blue.$3, greaterThan(150));
    expect(blueAfterSplit.$1, lessThan(80));
    expect(blueAfterSplit.$3, greaterThan(150));

    final beforeTone = await _meanAudioMagnitude(
      bundle.ffmpegPath,
      output.path,
      0.10,
    );
    final quietTone = await _meanAudioMagnitude(
      bundle.ffmpegPath,
      output.path,
      0.30,
    );
    final loudToneAfterSplit = await _meanAudioMagnitude(
      bundle.ffmpegPath,
      output.path,
      1.05,
    );
    final silenceEnd = await _initialSilenceEnd(bundle.ffmpegPath, output.path);
    final audioEvidence =
        'before=$beforeTone quiet=$quietTone loud=$loudToneAfterSplit '
        'silenceEnd=$silenceEnd';
    expect(beforeTone, lessThan(80), reason: audioEvidence);
    expect(quietTone, inInclusiveRange(80, 500), reason: audioEvidence);
    expect(
      loudToneAfterSplit,
      greaterThan(quietTone * 5),
      reason: audioEvidence,
    );
    expect(loudToneAfterSplit, greaterThan(800), reason: audioEvidence);
    expect(silenceEnd, closeTo(0.175, 0.035));
  } finally {
    await engine?.dispose();
    await state.dispose();
  }
}

Future<(int, int, int)> _centrePixel(
  String ffmpeg,
  String input,
  double seconds,
) async {
  final sampled = await Process.run(ffmpeg, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-ss',
    '$seconds',
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
  final rgb = sampled.stdout as List<int>;
  expect(rgb, hasLength(96 * 54 * 3));
  final index = ((54 ~/ 2) * 96 + 96 ~/ 2) * 3;
  return (rgb[index], rgb[index + 1], rgb[index + 2]);
}

Future<double> _meanAudioMagnitude(
  String ffmpeg,
  String input,
  double seconds,
) async {
  final sampled = await Process.run(ffmpeg, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-ss',
    '$seconds',
    '-i',
    input,
    '-t',
    '0.04',
    '-map',
    '0:a:0',
    '-ac',
    '1',
    '-ar',
    '16000',
    '-f',
    's16le',
    'pipe:1',
  ], stdoutEncoding: null);
  expect(sampled.exitCode, 0, reason: '${sampled.stderr}');
  final bytes = Uint8List.fromList(sampled.stdout as List<int>);
  final samples = ByteData.sublistView(bytes);
  var total = 0;
  for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
    total += samples.getInt16(offset, Endian.little).abs();
  }
  return total / math.max(1, bytes.length ~/ 2);
}

Future<double> _initialSilenceEnd(String ffmpeg, String input) async {
  final detected = await Process.run(ffmpeg, [
    '-hide_banner',
    '-loglevel',
    'info',
    '-i',
    input,
    '-af',
    'silencedetect=noise=-60dB:d=0.05',
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
