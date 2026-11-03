import 'job.dart';

typedef FfmpegProgressCallback = void Function(FfmpegProgress progress);

/// Portable feature discovery for the engine selected by this package.
final class FfmpegCapabilities {
  const FfmpegCapabilities({
    required this.backend,
    required this.platform,
    required this.supportsPathInputs,
    required this.supportsByteInputs,
    required this.supportsFfprobe,
    required this.inProcess,
    this.enforcesWorkspaceLimitBeforeWrite = false,
    this.enforcesEngineMemoryLimit = false,
    this.acceptsUntrustedMedia = false,
  });

  final String backend;
  final String platform;
  final bool supportsPathInputs;
  final bool supportsByteInputs;
  final bool supportsFfprobe;
  final bool inProcess;

  /// Whether writes are rejected before the owned workspace exceeds policy.
  final bool enforcesWorkspaceLimitBeforeWrite;

  /// Whether the selected engine enforces a hard engine-memory boundary.
  ///
  /// This is true for ffmpeg.wasm's linear memory. It is false for native
  /// process RSS and the in-process mobile heap.
  final bool enforcesEngineMemoryLimit;

  /// Whether this wrapper alone is an isolation boundary for hostile media.
  ///
  /// All current backends deliberately report false. Native callers that
  /// accept hostile bytes need an application/OS sandbox in addition to this
  /// package's transfer, workspace, and deadline controls.
  final bool acceptsUntrustedMedia;
}
