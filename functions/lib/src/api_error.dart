final class ApiError implements Exception {
  const ApiError(
    this.status,
    this.code,
    this.message, {
    this.details,
    this.diagnostic,
  });

  final int status;
  final String code;
  final String message;
  final Object? details;

  /// Provider or implementation detail for protected telemetry only.
  ///
  /// API responses always use [message]; this value must never be serialized
  /// to a caller.
  final String? diagnostic;

  @override
  String toString() => '$code: $message';
}
