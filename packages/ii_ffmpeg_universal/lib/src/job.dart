import 'dart:typed_data';

enum FfmpegOperation { ffmpeg, ffprobe }

sealed class FfmpegInput {
  const FfmpegInput(this.name);

  final String name;
}

/// In-memory media. This is the portable input type and is required on web.
final class FfmpegBytesInput extends FfmpegInput {
  FfmpegBytesInput(super.name, Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final Uint8List bytes;
}

/// A device-local path. Browser backends reject this input type.
final class FfmpegPathInput extends FfmpegInput {
  const FfmpegPathInput(super.name, this.path);

  final String path;
}

final class FfmpegOutput {
  const FfmpegOutput(
    this.name, {
    this.destinationPath,
    this.captureBytes = true,
    this.maxBytes,
  });

  final String name;
  final String? destinationPath;
  final bool captureBytes;
  final int? maxBytes;
}

/// One isolated invocation. Arguments reference inputs and outputs by [name].
final class FfmpegJob {
  FfmpegJob({
    required this.id,
    required List<String> arguments,
    List<FfmpegInput> inputs = const [],
    List<FfmpegOutput> outputs = const [],
    this.operation = FfmpegOperation.ffmpeg,
    this.expectedDuration,
    this.timeout,
    this.overwriteOutput = false,
  }) : arguments = List.unmodifiable(arguments),
       inputs = List.unmodifiable(inputs),
       outputs = List.unmodifiable(outputs);

  final String id;
  final List<String> arguments;
  final List<FfmpegInput> inputs;
  final List<FfmpegOutput> outputs;
  final FfmpegOperation operation;
  final Duration? expectedDuration;
  final Duration? timeout;
  final bool overwriteOutput;
}

final class FfmpegProgress {
  const FfmpegProgress({
    required this.jobId,
    required this.processed,
    required this.fraction,
    this.speed,
  });

  final String jobId;
  final Duration processed;
  final double? fraction;
  final double? speed;
}

final class FfmpegResult {
  FfmpegResult({
    required this.jobId,
    required this.backend,
    required this.exitCode,
    required this.elapsed,
    required this.logs,
    required Map<String, Uint8List> outputBytes,
    this.cancelled = false,
    this.timedOut = false,
  }) : outputBytes = Map.unmodifiable(outputBytes);

  final String jobId;
  final String backend;
  final int exitCode;
  final Duration elapsed;
  final List<String> logs;
  final Map<String, Uint8List> outputBytes;
  final bool cancelled;
  final bool timedOut;

  bool get isSuccess => exitCode == 0 && !cancelled && !timedOut;
}
