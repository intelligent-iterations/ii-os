/// Stable error categories exposed by the universal API.
enum FfmpegErrorCode {
  invalidJob,
  invalidResourceName,
  unsafeArgument,
  unsupportedPlatform,
  missingConfiguration,
  engineUnavailable,
  busy,
  inputTooLarge,
  outputTooLarge,
  outputExists,
  executionFailed,
  timedOut,
  cancelled,
  disposed,
}

/// An actionable failure that does not expose platform exception types.
final class FfmpegException implements Exception {
  const FfmpegException(this.code, this.message, {this.cause});

  final FfmpegErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'FfmpegException(${code.name}): $message';
}
