import '../backend.dart';
import '../capabilities.dart';
import '../configuration.dart';
import '../exception.dart';
import '../job.dart';

FfmpegBackend createPlatformBackend(FfmpegConfiguration configuration) =>
    const _UnsupportedBackend();

final class _UnsupportedBackend implements FfmpegBackend {
  const _UnsupportedBackend();

  @override
  FfmpegCapabilities get capabilities => FfmpegCapabilities(
    backend: 'unsupported',
    platform: 'unknown',
    supportsPathInputs: false,
    supportsByteInputs: false,
    supportsFfprobe: false,
    inProcess: false,
  );

  @override
  Future<void> initialize() => Future.error(
    const FfmpegException(
      FfmpegErrorCode.unsupportedPlatform,
      'No FFmpeg backend is available on this Dart platform.',
    ),
  );

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) => initialize().then((_) => throw StateError('unreachable'));

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
