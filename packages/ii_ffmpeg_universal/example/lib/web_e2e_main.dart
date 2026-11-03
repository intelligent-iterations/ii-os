import 'dart:convert';
import 'dart:typed_data';

import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:web/web.dart' as web;

const _coreScriptSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_JS_SHA256',
);
const _coreWasmSha256 = String.fromEnvironment(
  'II_FFMPEG_WEB_CORE_WASM_SHA256',
);

const _testWebBundle = FfmpegWebBundle(
  ffmpegScriptUrl: 'ffmpeg/ffmpeg.js',
  ffmpegScriptSha256:
      'ad4cfe957589995dea03fc8de1fd5e9f5cb4558a7282913172203082a65bbfaa',
  coreScriptUrl: 'ffmpeg/ffmpeg-core.js',
  coreScriptSha256: _coreScriptSha256,
  coreWasmUrl: 'ffmpeg/ffmpeg-core.wasm',
  coreWasmSha256: _coreWasmSha256,
);

Future<void> main() async {
  const isDartWasm = bool.fromEnvironment('dart.tool.dart2wasm');
  final body = web.document.body!;
  body.setAttribute('data-ii-ffmpeg-e2e', 'running');
  body.setAttribute('data-ii-dart-wasm', '$isDartWasm');
  final ffmpeg = UniversalFfmpeg(
    configuration: const FfmpegConfiguration(
      safety: FfmpegSafetyPolicy(defaultTimeout: Duration(seconds: 30)),
      webBundle: _testWebBundle,
    ),
  );
  try {
    await _verifyEngineBundleFailures();
    if (!ffmpeg.capabilities.enforcesWorkspaceLimitBeforeWrite ||
        !ffmpeg.capabilities.enforcesEngineMemoryLimit ||
        ffmpeg.capabilities.acceptsUntrustedMedia) {
      throw StateError('browser resource capabilities are inaccurate');
    }
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
      ),
    );
    if (!render.isSuccess) {
      throw StateError(
        'render exit ${render.exitCode}: ${render.logs.take(20).join(' | ')}',
      );
    }
    final video = render.outputBytes['output.mp4'];
    if (video == null || video.length < 500) {
      throw StateError('rendered output was missing or too small');
    }
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
    final probeJson = utf8.decode(probe.outputBytes['probe.json'] ?? []);
    if (!probe.isSuccess || !probeJson.contains('"duration"')) {
      throw StateError(
        'ffprobe ${probe.exitCode}: $probeJson ${probe.logs.take(20).join(' | ')}',
      );
    }
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
    if (invalidProbe.isSuccess) {
      throw StateError('invalid FFprobe input was reported as successful');
    }
    await _verifyOutputQuota();
    await _verifyPreReadOutputQuota();
    await _verifyUncapturedOutput();
    await _verifyInitializationCancellation();
    await _verifyTimeoutAndCancellation();
    if (video.length != renderedLength ||
        base64Encode(video) != renderedContent) {
      throw StateError('input bytes changed while probing');
    }
    body.setAttribute(
      'data-ii-ffmpeg-e2e',
      'pass:$renderedLength:${ffmpeg.capabilities.backend}:'
          'dart-wasm=$isDartWasm',
    );
  } catch (error) {
    final cause = error is FfmpegException ? error.cause : null;
    body.setAttribute(
      'data-ii-ffmpeg-e2e',
      'fail:$error${cause == null ? '' : ' cause=$cause'}',
    );
  } finally {
    await ffmpeg.dispose();
  }
}

Future<void> _verifyEngineBundleFailures() async {
  await _expectEngineUnavailable(const FfmpegConfiguration());
  await _expectEngineUnavailable(
    const FfmpegConfiguration(
      webBundle: FfmpegWebBundle(
        ffmpegScriptUrl: 'ffmpeg/ffmpeg.js',
        ffmpegScriptSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
        coreScriptUrl: 'ffmpeg/ffmpeg-core.js',
        coreScriptSha256: _coreScriptSha256,
        coreWasmUrl: 'ffmpeg/ffmpeg-core.wasm',
        coreWasmSha256: _coreWasmSha256,
      ),
    ),
  );
  await _expectEngineUnavailable(
    const FfmpegConfiguration(
      webBundle: FfmpegWebBundle(
        ffmpegScriptUrl: 'https://example.invalid/ffmpeg.js',
        ffmpegScriptSha256:
            'ad4cfe957589995dea03fc8de1fd5e9f5cb4558a7282913172203082a65bbfaa',
        coreScriptUrl: 'ffmpeg/ffmpeg-core.js',
        coreScriptSha256: _coreScriptSha256,
        coreWasmUrl: 'ffmpeg/ffmpeg-core.wasm',
        coreWasmSha256: _coreWasmSha256,
      ),
    ),
  );
}

Future<void> _expectEngineUnavailable(FfmpegConfiguration configuration) async {
  final ffmpeg = UniversalFfmpeg(configuration: configuration);
  try {
    await ffmpeg.initialize();
    throw StateError('an invalid browser engine bundle initialized');
  } on FfmpegException catch (error) {
    if (error.code != FfmpegErrorCode.engineUnavailable) rethrow;
  } finally {
    await ffmpeg.dispose();
  }
}

Future<void> _verifyUncapturedOutput() async {
  final ffmpeg = UniversalFfmpeg(
    configuration: const FfmpegConfiguration(webBundle: _testWebBundle),
  );
  try {
    final result = await ffmpeg.execute(
      FfmpegJob(
        id: 'web_uncaptured_output',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=16x16:d=0.1',
          '-frames:v',
          '1',
          '-f',
          'image2',
          'output.bmp',
        ],
        outputs: const [FfmpegOutput('output.bmp', captureBytes: false)],
      ),
    );
    if (!result.isSuccess || result.outputBytes.isNotEmpty) {
      throw StateError('uncaptured browser output crossed into Dart memory');
    }
  } finally {
    await ffmpeg.dispose();
  }
}

Future<void> _verifyPreReadOutputQuota() async {
  final ffmpeg = UniversalFfmpeg(
    configuration: FfmpegConfiguration(
      safety: const FfmpegSafetyPolicy(
        maxInputBytes: 64 * 1024,
        maxTotalInputBytes: 64 * 1024,
        maxOutputBytes: 4 * 1024 * 1024,
        maxTotalOutputBytes: 4 * 1024 * 1024,
        maxWorkspaceBytes: 8 * 1024 * 1024,
        defaultTimeout: Duration(seconds: 30),
      ),
      webBundle: _testWebBundle,
    ),
  );
  try {
    await ffmpeg.execute(
      FfmpegJob(
        id: 'web_pre_read_output_quota',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'testsrc2=s=320x180:r=10:d=0.5',
          '-c:v',
          'mpeg2video',
          '-f',
          'mpegts',
          'output.ts',
        ],
        outputs: const [FfmpegOutput('output.ts', maxBytes: 1024)],
      ),
    );
    throw StateError('browser pre-read output quota did not fail closed');
  } on FfmpegException catch (error) {
    if (error.code != FfmpegErrorCode.outputTooLarge) rethrow;
  } finally {
    await ffmpeg.dispose();
  }
}

Future<void> _verifyOutputQuota() async {
  final ffmpeg = UniversalFfmpeg(
    configuration: FfmpegConfiguration(
      safety: const FfmpegSafetyPolicy(
        maxInputBytes: 64 * 1024,
        maxTotalInputBytes: 64 * 1024,
        maxOutputBytes: 4 * 1024 * 1024,
        maxTotalOutputBytes: 4 * 1024 * 1024,
        maxWorkspaceBytes: 128 * 1024,
        defaultTimeout: Duration(seconds: 30),
      ),
      webBundle: _testWebBundle,
    ),
  );
  try {
    await ffmpeg.execute(
      FfmpegJob(
        id: 'web_output_quota',
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
        outputs: const [FfmpegOutput('output.ts', maxBytes: 4 * 1024 * 1024)],
      ),
    );
    throw StateError('browser output quota did not fail closed');
  } on FfmpegException catch (error) {
    if (error.code != FfmpegErrorCode.outputTooLarge) rethrow;
  } finally {
    await ffmpeg.dispose();
  }
}

Future<void> _verifyTimeoutAndCancellation() async {
  final timingOut = UniversalFfmpeg(
    configuration: const FfmpegConfiguration(webBundle: _testWebBundle),
  );
  final timedOut = await timingOut.execute(
    _slowWebJob('web_timeout', timeout: const Duration(milliseconds: 300)),
  );
  await timingOut.dispose();
  if (!timedOut.timedOut) throw StateError('web timeout was not normalized');

  final cancelling = UniversalFfmpeg(
    configuration: const FfmpegConfiguration(webBundle: _testWebBundle),
  );
  final execution = cancelling.execute(_slowWebJob('web_cancel'));
  await Future<void>.delayed(const Duration(milliseconds: 150));
  await cancelling.cancel();
  final cancelled = await execution;
  await cancelling.dispose();
  if (!cancelled.cancelled) {
    throw StateError('web cancellation was not normalized');
  }
}

FfmpegJob _slowWebJob(String id, {Duration? timeout}) => FfmpegJob(
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

Future<void> _verifyInitializationCancellation() async {
  final cancelling = UniversalFfmpeg(
    configuration: FfmpegConfiguration(
      safety: const FfmpegSafetyPolicy(defaultTimeout: Duration(seconds: 30)),
      webBundle: _testWebBundle,
    ),
  );
  final execution = cancelling.execute(
    FfmpegJob(
      id: 'cancel_during_web_initialization',
      arguments: [
        '-re',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=s=96x54:r=10:d=10',
        '-f',
        'null',
        '-',
      ],
    ),
  );
  final firstDispose = cancelling.dispose();
  final secondDispose = cancelling.dispose();
  await Future.wait([firstDispose, secondDispose]);
  final cancelled = await execution;
  if (!cancelled.cancelled) {
    throw StateError('web initialization cancellation did not join execution');
  }
}
