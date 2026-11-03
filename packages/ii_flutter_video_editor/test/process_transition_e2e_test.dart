@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

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

void main() {
  testWidgets(
    'a real dissolve blends the two pictures it joins',
    (tester) async => tester.runAsync(
      () => _renderTransition(EditorTransitionKind.dissolve, (frames) {
        final blended = frames.at(1.3);
        expect(blended.blue, greaterThan(60), reason: 'blue is still there');
        expect(blended.red, greaterThan(60), reason: 'red has arrived');
        expect(blended.blue, lessThan(210));
        expect(blended.red, lessThan(210));
        expect(frames.at(0.5).blue, greaterThan(150));
        expect(frames.at(0.5).red, lessThan(60));
        expect(frames.at(1.9).red, greaterThan(150));
        expect(frames.at(1.9).blue, lessThan(60));
      }),
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'a real dip passes the picture through its colour',
    (tester) async => tester.runAsync(
      () => _renderTransition(EditorTransitionKind.dipToColor, (frames) {
        final dipped = frames.at(1.0);
        expect(dipped.red, greaterThan(200));
        expect(dipped.green, greaterThan(200));
        expect(dipped.blue, greaterThan(200));
        expect(frames.at(0.5).blue, greaterThan(150));
        expect(frames.at(1.9).red, greaterThan(150));
      }, color: 'FFFFFF'),
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'a real slide brings the next picture across the frame',
    (tester) async => tester.runAsync(
      () => _renderTransition(EditorTransitionKind.slideFromRight, (frames) {
        final travelling = frames.at(1.3);
        expect(travelling.blueAtColumn(20), greaterThan(150));
        expect(travelling.redAtColumn(140), greaterThan(150));
        expect(frames.at(1.9).redAtColumn(20), greaterThan(150));
      }),
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _renderTransition(
  EditorTransitionKind kind,
  void Function(_Frames frames) verify, {
  String color = '000000',
}) async {
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
    final plan = await const EditorCompositionCompiler().compile(
      _joinedProject(blue, red, kind, color),
      safety: _safety,
      mediaLimits: const MediaLimits(
        maxInputBytes: 64 * 1024 * 1024,
        maxSourceBytes: 64 * 1024 * 1024,
        maxOutputBytes: 64 * 1024 * 1024,
      ),
    );
    final rendered = await engine.execute(plan.job);
    expect(rendered.isSuccess, isTrue, reason: rendered.logs.join('\n'));
    final bytes = rendered.outputBytes[plan.outputName];
    expect(bytes, isNotNull);
    final output = File.fromUri(state.directory.uri.resolve('output.mp4'));
    await output.writeAsBytes(bytes!, flush: true);
    verify(_Frames(bundle.ffmpegPath, output.path));
  } finally {
    await engine?.dispose();
    await state.dispose();
  }
}

EditorProject _joinedProject(
  MediaSource blue,
  MediaSource red,
  EditorTransitionKind kind,
  String color,
) => EditorProject(
  id: 'transition-live-project',
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
      id: 'live-video-lane',
      label: 'Video',
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
            kind: kind,
            duration: MediaTime.milliseconds(600),
            color: color,
          ),
        ),
      ],
    ),
  ],
);

Future<MediaSource> _solidSource(
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
  return MediaSource(
    id: 'transition-$color-source',
    byteLength: await file.length(),
    fileExtension: 'mp4',
    openRead: file.openRead,
  );
}

final class _Frames {
  _Frames(this.ffmpeg, this.output);

  final String ffmpeg;
  final String output;
  final Map<double, _Frame> _cache = {};

  _Frame at(double seconds) =>
      _cache[seconds] ?? (_cache[seconds] = _read(seconds));

  _Frame _read(double seconds) {
    final sampled = Process.runSync(ffmpeg, [
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
    final bytes = (sampled.stdout as List<int>);
    expect(bytes, hasLength(_width * _height * 3), reason: 'frame at $seconds');
    return _Frame(bytes);
  }
}

final class _Frame {
  const _Frame(this.rgb);

  final List<int> rgb;

  int get red => _channelAt(_width ~/ 2, 0);
  int get green => _channelAt(_width ~/ 2, 1);
  int get blue => _channelAt(_width ~/ 2, 2);

  int redAtColumn(int column) => _channelAt(column, 0);
  int blueAtColumn(int column) => _channelAt(column, 2);

  int _channelAt(int column, int channel) {
    final row = _height ~/ 2;
    return rgb[(row * _width + column) * 3 + channel];
  }
}
