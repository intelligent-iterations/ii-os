import 'dart:async';

import 'capabilities.dart';
import 'configuration.dart';
import 'job.dart';

/// One execution's deadline and cancellation state.
///
/// Backends must check this before launching an engine after asynchronous
/// preparation. The owning [UniversalFfmpeg] also calls the backend's cancel
/// method when this token changes while an engine is active.
final class FfmpegExecutionContext {
  FfmpegExecutionContext(Duration timeout)
    : _started = Stopwatch()..start(),
      _timeout = timeout;

  final Stopwatch _started;
  final Duration _timeout;
  final Completer<void> _cancelled = Completer<void>();
  bool _timedOut = false;
  bool _persistentOutputCommitted = false;

  Duration get elapsed => _started.elapsed;
  Duration get remaining {
    final value = _timeout - elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  bool get isCancelled => _cancelled.isCompleted;
  bool get timedOut => _timedOut;
  bool get persistentOutputCommitted => _persistentOutputCommitted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel({bool timedOut = false}) {
    _timedOut = _timedOut || timedOut;
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  /// Records the backend's successful atomic publication boundary.
  ///
  /// Cancellation is best effort until this point. Once an external output
  /// has been installed, success must win a racing cancel/deadline so callers
  /// never receive a retryable failure after a persistent side effect.
  void recordPersistentOutputCommit() {
    _persistentOutputCommitted = true;
  }
}

/// Internal adapter contract. It is intentionally not exported by the package.
abstract interface class FfmpegBackend {
  FfmpegCapabilities get capabilities;

  Future<void> initialize();

  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  });

  Future<void> cancel();

  Future<void> dispose();
}
