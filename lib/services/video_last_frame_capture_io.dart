import 'dart:typed_data';

import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';

import 'video_editor_ffmpeg.dart';
import 'video_last_frame_capture_limits.dart';

const _inputName = 'source-video';
const _outputName = 'last-frame.png';

/// How long a single frame decode may take before it is abandoned.
///
/// Well below the editor's render timeout: this seeks to the end of one file
/// and decodes one frame, so a run that takes minutes is a stuck run, not a
/// slow one.
const _captureTimeout = Duration(minutes: 2);

/// Captures the last decodable frame from already verified local [videoBytes].
///
/// The native counterpart of the browser canvas path. It runs through
/// [UniversalFfmpeg] rather than binding an FFmpeg plugin directly, because
/// that package owns media execution, the disposable workspace, the transfer
/// limits, and the deadline -- a second binding here would be a second set of
/// those controls to keep correct.
///
/// [contentType] is accepted for parity with the web implementation, which
/// needs it to build a Blob. FFmpeg probes the container itself, so it is not
/// used to select a demuxer here.
Future<Uint8List> captureVideoLastFrame(
  Uint8List videoBytes, {
  required String contentType,
}) async {
  final ffmpeg = UniversalFfmpeg(
    configuration: videoEditorFfmpegConfiguration(),
  );
  try {
    return readCapturedFrame(
      await ffmpeg.execute(videoLastFrameJob(videoBytes)),
    );
  } finally {
    // The runtime owns the disposable workspace this job wrote into, so
    // disposing it is what removes the decoded frame from the device.
    await ffmpeg.dispose();
  }
}

/// The single-frame job handed to the runtime.
///
/// Split out so the wiring is testable without an FFmpeg engine: a device is
/// the only place the engine runs, and a job that names the wrong output or
/// forgets its ceiling would otherwise only fail there.
FfmpegJob videoLastFrameJob(Uint8List videoBytes) => FfmpegJob(
  id: 'video-last-frame',
  arguments: videoLastFrameFfmpegArguments(
    inputName: _inputName,
    outputName: _outputName,
  ),
  inputs: [FfmpegBytesInput(_inputName, videoBytes)],
  outputs: const [FfmpegOutput(_outputName, maxBytes: maxVideoLastFrameBytes)],
  timeout: _captureTimeout,
  overwriteOutput: true,
);

/// Validates a finished run and returns the frame.
///
/// Split from the execution for the same reason: every branch here is a way
/// the engine can come back wrong, and none of them are reachable from a test
/// that has to launch FFmpeg first.
Uint8List readCapturedFrame(FfmpegResult result) {
  if (result.timedOut) {
    throw StateError('Decoding a frame from the source video timed out.');
  }
  if (!result.isSuccess) {
    throw StateError('FFmpeg could not decode a frame from the source video.');
  }
  final bytes = result.outputBytes[_outputName];
  if (bytes == null || bytes.isEmpty) {
    throw StateError('FFmpeg did not produce a video frame.');
  }
  if (bytes.length > maxVideoLastFrameBytes) {
    throw const FormatException('The extracted frame is too large.');
  }
  if (!hasPngSignature(bytes)) {
    throw StateError('FFmpeg returned an invalid PNG frame.');
  }
  return bytes;
}
