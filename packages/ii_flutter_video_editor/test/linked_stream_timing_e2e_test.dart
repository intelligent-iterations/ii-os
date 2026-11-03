@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import 'desktop_engine.dart';

const _fixtureRoot = 'test/fixtures/linked-offset-v1';
const _safety = FfmpegSafetyPolicy(
  maxInputBytes: 64 * 1024 * 1024,
  maxOutputBytes: 64 * 1024 * 1024,
  maxTotalInputBytes: 64 * 1024 * 1024,
  maxTotalOutputBytes: 64 * 1024 * 1024,
  maxWorkspaceBytes: 192 * 1024 * 1024,
  defaultTimeout: Duration(minutes: 2),
  maxTimeout: Duration(minutes: 3),
);

void main() {
  testWidgets(
    'linked streams keep real presentation skew and stream-local split ranges',
    (tester) async => tester.runAsync(_proveLinkedStreamTiming),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _proveLinkedStreamTiming() async {
  final fixture = File('$_fixtureRoot/linked-offset.mov');
  final probeFile = File('$_fixtureRoot/ffprobe.json');
  final provenance =
      (jsonDecode(File('$_fixtureRoot/provenance.json').readAsStringSync())
              as Map)
          .cast<String, Object?>();
  final fixtureBytes = await fixture.readAsBytes();
  final probeBytes = await probeFile.readAsBytes();
  expect(sha256.convert(fixtureBytes).toString(), provenance['mediaSha256']);
  expect(sha256.convert(probeBytes).toString(), provenance['ffprobeSha256']);
  final capturedProbe = jsonDecode(utf8.decode(probeBytes)) as Map;
  final streams = (capturedProbe['streams'] as List<Object?>)
      .map((value) => (value as Map).cast<String, Object?>())
      .toList(growable: false);
  expect(streams[0]['start_time'], '1.000000');
  expect(streams[1]['start_time'], '1.175000');

  final state = await OwnedState.create();
  UniversalFfmpeg? engine;
  try {
    final bundle = await resolveDesktopBundle();
    engine = UniversalFfmpeg(
      configuration: FfmpegConfiguration(
        safety: _safety,
        desktopBundle: bundle,
        nativeWorkspaceRoot: state.directory.uri
            .resolve('universal-workspaces')
            .toFilePath(),
      ),
    );
    final source = MediaSource(
      id: 'linked-offset-real',
      byteLength: fixtureBytes.length,
      fileExtension: 'mov',
      openRead: fixture.openRead,
    );
    final placed = addEditorSourceOnNewLanes(
      project: _emptyProject(),
      source: source,
      timelineStart: MediaTime.zero,
      video: EditorNewLanePlacement(
        laneId: 'video-lane',
        laneLabel: 'Video',
        clipId: 'video-clip',
        sourceRange: MediaRange(
          start: MediaTime.zero,
          duration: MediaTime.seconds(2),
        ),
        sourceDuration: MediaTime.seconds(2),
      ),
      audio: EditorNewLanePlacement(
        laneId: 'audio-lane',
        laneLabel: 'Audio',
        clipId: 'audio-clip',
        sourceRange: MediaRange(
          start: MediaTime.zero,
          duration: MediaTime.milliseconds(1825),
        ),
        sourceDuration: MediaTime.milliseconds(1825),
        timelineOffset: MediaTime.milliseconds(175),
      ),
      linkGroupId: 'linked-streams',
    );
    final split = splitEditorClip(
      project: placed,
      selection: const EditorSelection(
        laneId: 'video-lane',
        clipId: 'video-clip',
      ),
      at: MediaTime.seconds(1),
    ).project;
    final audio = split.laneById('audio-lane')!.clips.cast<EditorAudioClip>();
    expect(audio.first.timelineStart, MediaTime.milliseconds(175));
    expect(audio.first.sourceRange.start, MediaTime.zero);
    expect(audio.first.duration, MediaTime.milliseconds(825));
    expect(audio.last.timelineStart, MediaTime.seconds(1));
    expect(audio.last.sourceRange.start, MediaTime.milliseconds(825));
    expect(audio.last.duration, MediaTime.seconds(1));

    final plan = await const EditorCompositionCompiler().compile(
      split,
      safety: _safety,
      mediaLimits: const MediaLimits(
        maxInputBytes: 64 * 1024 * 1024,
        maxSourceBytes: 64 * 1024 * 1024,
        maxOutputBytes: 64 * 1024 * 1024,
      ),
    );
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
    final loudTone = await _meanAudioMagnitude(
      bundle.ffmpegPath,
      output.path,
      1.05,
    );
    final silenceEnd = await _initialSilenceEnd(bundle.ffmpegPath, output.path);
    final evidence =
        'before=$beforeTone quiet=$quietTone loud=$loudTone '
        'silenceEnd=$silenceEnd';
    expect(beforeTone, lessThan(80), reason: evidence);
    expect(quietTone, inInclusiveRange(80, 500), reason: evidence);
    expect(loudTone, greaterThan(quietTone * 5), reason: evidence);
    expect(loudTone, greaterThan(800), reason: evidence);
    expect(silenceEnd, closeTo(0.175, 0.035), reason: evidence);
  } finally {
    await engine?.dispose();
    await state.dispose();
  }
}

EditorProject _emptyProject() => EditorProject(
  id: 'linked-timing-project',
  width: 96,
  height: 54,
  framesPerSecond: 40,
  duration: MediaTime.seconds(2),
  output: const MediaOutputSettings(
    videoCodec: MediaVideoCodec.mpeg4,
    audioCodec: MediaAudioCodec.aac,
    videoBitrate: 500000,
    audioBitrate: 64000,
  ),
  lanes: const [],
);

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
