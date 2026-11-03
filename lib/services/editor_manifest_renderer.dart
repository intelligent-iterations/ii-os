import 'dart:typed_data';

import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';

import '../models/editor_render_manifest.dart';

/// A render that was described correctly but did not produce a video.
final class EditorManifestRenderFailure implements Exception {
  const EditorManifestRenderFailure(this.message, {this.logs = const []});

  final String message;
  final List<String> logs;

  @override
  String toString() => 'EditorManifestRenderFailure: $message';
}

/// Runs a render the editor described, wherever this code happens to be.
///
/// This is the whole of what a workspace machine does with an export: put the
/// files where the arguments expect them, check the arguments against the same
/// allowlist the browser checks against, and run them. The machine never sees
/// a timeline, so there is no second compiler to drift from the first.
///
/// The safety check is not a formality. The arguments arrive from a client, so
/// they are treated as a claim about what to run rather than permission to run
/// it: [FfmpegSafetyPolicy] admits a fixed set of filters and options, no file
/// or font options, no protocols, and no absolute paths.
Future<Uint8List> renderEditorManifest({
  required EditorRenderManifest manifest,
  required Map<String, Uint8List> inputs,
  required UniversalFfmpeg engine,
  FfmpegSafetyPolicy safety = const FfmpegSafetyPolicy(),
}) async {
  final job = manifest.toJob(inputs);
  safety.validate(job);
  final result = await engine.execute(job);
  final bytes = result.outputBytes[manifest.outputName];
  if (!result.isSuccess || bytes == null || bytes.isEmpty) {
    throw EditorManifestRenderFailure(
      'The render did not produce a video (exit code ${result.exitCode}).',
      logs: result.logs.take(12).toList(growable: false),
    );
  }
  return bytes;
}
