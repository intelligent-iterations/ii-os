import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';

import 'package:ii_ffmpeg_universal_example/desktop_bundle_stub.dart'
    if (dart.library.io) 'package:ii_ffmpeg_universal_example/desktop_bundle_io.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late FfmpegConfiguration configuration;
  String? nativeWorkspaceRoot;

  setUpAll(() async {
    FfmpegDesktopBundle? desktopBundle;
    if (Platform.isLinux || Platform.isMacOS) {
      desktopBundle = await loadExampleDesktopBundle();
      if (desktopBundle == null) {
        throw StateError('The application-bundled desktop engine is missing.');
      }
    }
    nativeWorkspaceRoot = exampleIntegrationNativeWorkspaceRoot();
    configuration = FfmpegConfiguration(
      safety: const FfmpegSafetyPolicy(defaultTimeout: Duration(seconds: 30)),
      desktopBundle: desktopBundle,
      nativeWorkspaceRoot: nativeWorkspaceRoot,
    );
  });

  tearDownAll(() async {
    await cleanupExampleIntegrationNativeWorkspaceRoot(nativeWorkspaceRoot);
    // Keep this line in bounded integration logs as cleanup proof.
    debugPrint('owned native workspace cleanup complete');
  });

  testWidgets('native engine initializes without recursive waiting', (
    tester,
  ) async {
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    await ffmpeg.initialize().timeout(const Duration(seconds: 30));
    final firstDispose = ffmpeg.dispose();
    final secondDispose = ffmpeg.dispose();
    expect(identical(firstDispose, secondDispose), isTrue);
    await Future.wait([firstDispose, secondDispose]);
  });

  testWidgets('real ffmpeg.wasm renders an MP4 and probes its bytes', (
    tester,
  ) async {
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    addTearDown(ffmpeg.dispose);

    final render = await ffmpeg.execute(
      FfmpegJob(
        id: 'live_web_render',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=c=purple:s=96x54:r=10:d=0.2',
          '-c:v',
          'mpeg4',
          '-frames:v',
          '2',
          '-f',
          'mp4',
          'output.mp4',
        ],
        outputs: const [FfmpegOutput('output.mp4')],
        expectedDuration: const Duration(milliseconds: 200),
      ),
    );

    expect(render.isSuccess, isTrue, reason: render.logs.join('\n'));
    final video = render.outputBytes['output.mp4'];
    expect(video, isNotNull);
    expect(video!.length, greaterThan(500));
    final renderedLength = video.length;
    final renderedContent = base64Encode(video);

    final probe = await ffmpeg.execute(
      FfmpegJob(
        id: 'live_web_probe',
        operation: FfmpegOperation.ffprobe,
        arguments: const [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'json',
          '-f',
          'mov',
          '-i',
          'input.mp4',
          '-o',
          'probe.json',
        ],
        inputs: [FfmpegBytesInput('input.mp4', video)],
        outputs: const [FfmpegOutput('probe.json')],
      ),
    );

    expect(probe.isSuccess, isTrue, reason: probe.logs.join('\n'));
    expect(
      utf8.decode(probe.outputBytes['probe.json']!),
      contains('"duration"'),
    );
    expect(video.length, renderedLength, reason: 'input bytes were detached');
    expect(
      base64Encode(video),
      renderedContent,
      reason: 'input bytes changed while probing',
    );

    final invalidProbe = await ffmpeg.execute(
      FfmpegJob(
        id: 'live_web_invalid_probe',
        operation: FfmpegOperation.ffprobe,
        arguments: const [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'json',
          '-f',
          'mov',
          '-i',
          'invalid.mp4',
          '-o',
          'invalid-probe.json',
        ],
        inputs: [
          FfmpegBytesInput('invalid.mp4', Uint8List.fromList([0, 1, 2, 3])),
        ],
        outputs: const [FfmpegOutput('invalid-probe.json')],
      ),
    );
    expect(
      invalidProbe.isSuccess,
      isFalse,
      reason: 'invalid media must not be promoted from FFprobe -1 to success',
    );
  });

  testWidgets('real engine cancellation joins native completion', (
    tester,
  ) async {
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    addTearDown(ffmpeg.dispose);
    final execution = ffmpeg.execute(_slowJob('live_cancel'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await ffmpeg.cancel().timeout(const Duration(seconds: 30));
    final result = await execution.timeout(const Duration(seconds: 30));
    expect(result.cancelled, isTrue, reason: result.logs.join('\n'));
    expect(result.timedOut, isFalse);
  });

  testWidgets('real engine reports output quota failures consistently', (
    tester,
  ) async {
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    addTearDown(ffmpeg.dispose);

    await expectLater(
      ffmpeg.execute(_outputQuotaJob('live_output_quota')),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.outputTooLarge,
        ),
      ),
    );
  });

  testWidgets('real engine timeout joins native completion', (tester) async {
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    addTearDown(ffmpeg.dispose);
    final result = await ffmpeg
        .execute(
          _slowJob('live_timeout', timeout: const Duration(milliseconds: 300)),
        )
        .timeout(const Duration(seconds: 30));
    expect(result.timedOut, isTrue, reason: result.logs.join('\n'));
  });

  testWidgets('concurrent dispose cancels and joins a real engine', (
    tester,
  ) async {
    final ffmpeg = UniversalFfmpeg(configuration: configuration);
    final execution = ffmpeg.execute(_slowJob('live_dispose'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final firstDispose = ffmpeg.dispose();
    final secondDispose = ffmpeg.dispose();
    expect(identical(firstDispose, secondDispose), isTrue);
    await Future.wait([
      firstDispose,
      secondDispose,
    ]).timeout(const Duration(seconds: 30));
    final result = await execution.timeout(const Duration(seconds: 30));
    expect(result.cancelled, isTrue, reason: result.logs.join('\n'));
  });

  testWidgets('two real instances complete without evicting native sessions', (
    tester,
  ) async {
    final first = UniversalFfmpeg(configuration: configuration);
    final second = UniversalFfmpeg(configuration: configuration);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    final results = await Future.wait([
      first.execute(_shortRenderJob('live_concurrent_first')),
      second.execute(_shortRenderJob('live_concurrent_second')),
    ]).timeout(const Duration(seconds: 60));

    expect(results, everyElement(isA<FfmpegResult>()));
    expect(results.every((result) => result.isSuccess), isTrue);
    expect(
      results.every((result) => result.outputBytes['output.mp4']!.isNotEmpty),
      isTrue,
    );
  });
}

FfmpegJob _slowJob(String id, {Duration? timeout}) => FfmpegJob(
  id: id,
  timeout: timeout,
  arguments: const [
    '-re',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=s=96x54:r=10:d=10',
    '-f',
    'null',
    '-',
  ],
);

FfmpegJob _outputQuotaJob(String id) => FfmpegJob(
  id: id,
  arguments: const [
    '-f',
    'lavfi',
    '-i',
    'testsrc2=s=640x360:r=30:d=1',
    '-c:v',
    'mpeg2video',
    '-f',
    'mpegts',
    'output.ts',
  ],
  outputs: const [FfmpegOutput('output.ts', maxBytes: 1024)],
);

FfmpegJob _shortRenderJob(String id) => FfmpegJob(
  id: id,
  arguments: const [
    '-f',
    'lavfi',
    '-i',
    'color=c=blue:s=64x36:r=10:d=0.2',
    '-c:v',
    'mpeg4',
    '-frames:v',
    '2',
    '-f',
    'mp4',
    'output.mp4',
  ],
  outputs: const [FfmpegOutput('output.mp4')],
);
