import 'dart:math' as math;

import 'configuration.dart';
import 'exception.dart';
import 'job.dart';

int effectiveOutputLimit(
  FfmpegJob job,
  FfmpegOutput output,
  FfmpegSafetyPolicy safety,
) {
  final configured = output.maxBytes ?? safety.maxOutputBytes;
  if (job.operation == FfmpegOperation.ffprobe) {
    return math.min(configured, FfmpegSafetyPolicy.maxManagedProbeOutputBytes);
  }
  return configured;
}

int executionOutputLimit(
  FfmpegJob job,
  FfmpegOutput output,
  FfmpegSafetyPolicy safety, {
  int? hardOutputBytes,
  int? workspaceBytesAlreadyUsed,
}) {
  final outputCount = job.outputs.length;
  if (outputCount == 0 || !job.outputs.contains(output)) {
    throw const FfmpegException(
      FfmpegErrorCode.invalidJob,
      'An execution output limit requires a declared output.',
    );
  }
  final usedWorkspace =
      workspaceBytesAlreadyUsed ??
      job.inputs.whereType<FfmpegBytesInput>().fold<int>(
        0,
        (total, input) => total + input.bytes.length,
      );
  final availableWorkspace = safety.maxWorkspaceBytes - usedWorkspace;
  if (availableWorkspace <= 0) {
    throw const FfmpegException(
      FfmpegErrorCode.outputTooLarge,
      'The managed workspace has no capacity for declared outputs.',
    );
  }
  final workspaceShare = availableWorkspace ~/ outputCount;
  final totalOutputShare = safety.maxTotalOutputBytes ~/ outputCount;
  if (workspaceShare <= 0 || totalOutputShare <= 0) {
    throw const FfmpegException(
      FfmpegErrorCode.outputTooLarge,
      'The managed output count exceeds the available byte budget.',
    );
  }
  return math.min(
    hardOutputBytes ?? safety.maxOutputBytes,
    math.min(
      effectiveOutputLimit(job, output, safety),
      math.min(workspaceShare, totalOutputShare),
    ),
  );
}

/// Adds engine-enforced constraints after the caller's managed argv has passed
/// validation. These options are package-owned and never accepted from callers.
List<String> constrainManagedExecution(
  FfmpegJob job,
  FfmpegSafetyPolicy safety, {
  int? hardOutputBytes,
  int? workspaceBytesAlreadyUsed,
  int outputOvershootReserveBytes = 0,
  int? maxEngineAllocationBytes,
}) {
  final arguments = List<String>.of(job.arguments);
  if (outputOvershootReserveBytes < 0 ||
      (maxEngineAllocationBytes != null && maxEngineAllocationBytes <= 0)) {
    throw const FfmpegException(
      FfmpegErrorCode.invalidJob,
      'Engine execution constraints must be positive.',
    );
  }
  final reserve = job.operation == FfmpegOperation.ffmpeg
      ? outputOvershootReserveBytes * job.outputs.length
      : 0;
  final usedWithReserve =
      (workspaceBytesAlreadyUsed ??
          job.inputs.whereType<FfmpegBytesInput>().fold<int>(
            0,
            (total, input) => total + input.bytes.length,
          )) +
      reserve;
  if (usedWithReserve > safety.maxWorkspaceBytes) {
    throw FfmpegException(
      FfmpegErrorCode.outputTooLarge,
      'The managed workspace cannot reserve $reserve bytes of native muxer '
      'headroom.',
    );
  }

  final outputLimits = <String, int>{
    for (final output in job.outputs)
      output.name: executionOutputLimit(
        job,
        output,
        safety,
        hardOutputBytes: hardOutputBytes,
        workspaceBytesAlreadyUsed: usedWithReserve,
      ),
  };

  final constrained = <String>[
    if (job.operation == FfmpegOperation.ffmpeg) ...const [
      '-filter_threads',
      '1',
      '-filter_complex_threads',
      '1',
    ],
    if (maxEngineAllocationBytes != null) ...[
      '-max_alloc',
      '$maxEngineAllocationBytes',
    ],
  ];
  for (final argument in arguments) {
    if (argument == '-i') {
      // A URL hidden inside a playlist/container never appears in caller argv.
      // Pair the explicit safe demuxer requirement with a protocol allowlist so
      // nested HTTP/RTSP/etc. opens fail inside FFmpeg as well.
      constrained.addAll([
        '-threads',
        '1',
        '-protocol_whitelist',
        'file',
        '-max_pixels',
        '${safety.maxDecodedPixels}',
      ]);
    }
    final outputLimit = outputLimits[argument];
    if (job.operation == FfmpegOperation.ffmpeg && outputLimit != null) {
      // FFmpeg may finish the current muxer packet after crossing -fs, so the
      // workspace monitor and bounded post-read remain mandatory second lines.
      constrained.addAll(['-threads', '1', '-fs', '$outputLimit']);
    }
    constrained.add(argument);
  }
  return constrained;
}
