import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'backends/backend_factory.dart';
import 'capabilities.dart';
import 'configuration.dart';
import 'exception.dart';
import 'job.dart';

final class UniversalFfmpeg {
  UniversalFfmpeg({
    FfmpegConfiguration configuration = const FfmpegConfiguration(),
  }) : _configuration = configuration,
       _backend = createPlatformBackend(configuration);

  UniversalFfmpeg._(this._configuration, this._backend);

  final FfmpegConfiguration _configuration;
  final FfmpegBackend _backend;
  Future<void>? _initialization;
  Future<void>? _initializationSource;
  Future<void>? _activeOperation;
  Future<void>? _disposeOperation;
  FfmpegExecutionContext? _activeContext;
  bool _initializationTerminationUnproven = false;
  bool _disposing = false;
  bool _disposed = false;

  FfmpegCapabilities get capabilities => _backend.capabilities;

  Future<void> initialize() async {
    _ensureAvailable();
    await _ensureInitialized();
  }

  Future<FfmpegResult> execute(
    FfmpegJob job, {
    FfmpegProgressCallback? onProgress,
  }) async {
    _ensureAvailable();
    if (_activeOperation != null) {
      throw const FfmpegException(
        FfmpegErrorCode.busy,
        'This FFmpeg instance already has an active job.',
      );
    }
    // Reject policy errors before starting lifecycle state or a deadline
    // timer. A zero/invalid deadline must still report invalidJob rather than
    // racing the cancellation path.
    _configuration.safety.validate(job);
    final completion = Completer<void>();
    final context = FfmpegExecutionContext(
      job.timeout ?? _configuration.safety.defaultTimeout,
    );
    _activeOperation = completion.future;
    _activeContext = context;
    Future<FfmpegResult>? backendExecution;
    var backendSettled = true;
    Future<void>? deadlineCancellation;
    final timer = Timer(context.remaining, () {
      context.cancel(timedOut: true);
      deadlineCancellation ??= _cancelBackendWithoutLeakingErrors();
    });
    try {
      try {
        final initialization = _ensureInitialized();
        await Future.any<void>([initialization, context.whenCancelled]);
        if (context.isCancelled) {
          _initializationTerminationUnproven = true;
          final source = _initializationSource ?? initialization;
          final settlement = source.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
          try {
            await Future.wait<void>([
              deadlineCancellation ??= _cancelBackendWithoutLeakingErrors(),
              settlement,
            ]).timeout(_configuration.safety.terminationGracePeriod);
          } on TimeoutException {
            throw const FfmpegException(
              FfmpegErrorCode.executionFailed,
              'The selected engine did not stop initialization within the '
              'job termination window.',
            );
          }
          return _cancelledResult(job, context);
        }
      } catch (_) {
        if (context.isCancelled) return _cancelledResult(job, context);
        rethrow;
      }
      if (context.isCancelled) return _cancelledResult(job, context);
      backendSettled = false;
      backendExecution = _backend
          .execute(
            job,
            _configuration.safety,
            context: context,
            onProgress: onProgress,
          )
          .whenComplete(() => backendSettled = true);
      final result = await backendExecution.timeout(
        context.remaining + _configuration.safety.terminationGracePeriod,
        onTimeout: () => throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'The selected engine did not stop within its bounded execution '
          'and termination window.',
        ),
      );
      return _applyContext(result, context);
    } on FfmpegException catch (error) {
      // Policy/resource failures remain actionable stable exceptions even when
      // the backend used cancellation internally to stop the engine. Explicit
      // cancellation and deadline failures are normalized into a result on
      // every backend.
      if (error.code == FfmpegErrorCode.cancelled ||
          error.code == FfmpegErrorCode.timedOut) {
        context.cancel(timedOut: error.code == FfmpegErrorCode.timedOut);
        return _cancelledResult(job, context);
      }
      if (context.isCancelled &&
          error.code != FfmpegErrorCode.inputTooLarge &&
          error.code != FfmpegErrorCode.outputTooLarge &&
          error.code != FfmpegErrorCode.outputExists) {
        return _cancelledResult(job, context);
      }
      rethrow;
    } catch (error) {
      if (context.isCancelled) return _cancelledResult(job, context);
      throw FfmpegException(
        FfmpegErrorCode.executionFailed,
        'The ${capabilities.backend} backend failed while executing ${job.id}.',
        cause: error,
      );
    } finally {
      timer.cancel();
      final cancellation = deadlineCancellation;
      if (cancellation != null) await cancellation;
      void releaseOperation() {
        if (identical(_activeContext, context)) {
          _activeContext = null;
          _activeOperation = null;
        }
        if (!completion.isCompleted) completion.complete();
      }

      final stillRunning = backendExecution;
      if (stillRunning == null || backendSettled) {
        releaseOperation();
      } else {
        // Future.timeout does not cancel its source. Keep this instance busy
        // until the engine itself settles so a failed termination proof can
        // never permit an overlapping second job.
        unawaited(
          stillRunning.then<void>(
            (_) => releaseOperation(),
            onError: (Object _, StackTrace _) => releaseOperation(),
          ),
        );
      }
    }
  }

  Future<void> cancel() async {
    _ensureAvailable();
    final context = _activeContext;
    final initialization = _initializationSource;
    if (context == null && initialization == null) return;
    final active = _activeOperation;
    context?.cancel();
    await _backend.cancel().timeout(
      _configuration.safety.terminationGracePeriod,
      onTimeout: () => throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'The selected engine did not acknowledge cancellation within the '
        'termination grace period.',
      ),
    );
    if (active != null) {
      await active.timeout(
        _configuration.safety.terminationGracePeriod,
        onTimeout: () => throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'The selected engine did not finish after acknowledging cancellation '
          'within the termination grace period.',
        ),
      );
    }
    if (initialization != null) {
      try {
        await initialization.timeout(
          _configuration.safety.terminationGracePeriod,
          onTimeout: () => throw const FfmpegException(
            FfmpegErrorCode.executionFailed,
            'The selected engine did not finish initialization after '
            'acknowledging cancellation within the termination grace period.',
          ),
        );
      } on FfmpegException catch (error) {
        if (error.code != FfmpegErrorCode.cancelled) rethrow;
        // A cancelled initialization is the expected terminal acknowledgement
        // for an explicit cancel request, not a failure of cancel itself.
      }
    }
  }

  Future<void> dispose() {
    if (_disposed) return Future.value();
    final current = _disposeOperation;
    if (current != null) return current;
    _disposing = true;
    final started = _dispose();
    _disposeOperation = started;
    return started;
  }

  Future<void> _dispose() async {
    FfmpegException? terminationFailure;
    final context = _activeContext;
    final active = _activeOperation;
    if (context != null) {
      context.cancel();
      await _cancelBackendWithoutLeakingErrors();
    }
    if (active != null) {
      try {
        await active.timeout(_configuration.safety.terminationGracePeriod);
      } on TimeoutException {
        terminationFailure = const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'The selected engine did not finish during disposal within the '
          'termination grace period.',
        );
      }
    }
    final initialization = _initializationSource ?? _initialization;
    if (initialization != null) {
      await _cancelBackendWithoutLeakingErrors();
      try {
        await initialization.timeout(
          _configuration.safety.terminationGracePeriod,
        );
      } on TimeoutException {
        terminationFailure ??= const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'The selected engine did not finish initialization during disposal '
          'within the termination grace period.',
        );
      } catch (_) {
        // Initialization already reports its own error to its caller. Disposal
        // still owns releasing any partially initialized backend resources.
      }
    }
    await _backend.dispose().timeout(
      _configuration.safety.terminationGracePeriod,
      onTimeout: () => throw const FfmpegException(
        FfmpegErrorCode.executionFailed,
        'The selected engine did not dispose within the termination grace '
        'period.',
      ),
    );
    _disposed = true;
    if (terminationFailure != null) throw terminationFailure;
  }

  Future<void> _ensureInitialized() {
    if (_initializationTerminationUnproven) {
      return Future<void>.error(
        const FfmpegException(
          FfmpegErrorCode.engineUnavailable,
          'A previous engine initialization has not confirmed termination.',
        ),
      );
    }
    final current = _initialization;
    if (current != null) return current;
    var backendSettled = false;
    late final Future<void> backendInitialization;
    backendInitialization = _backend.initialize().whenComplete(() {
      backendSettled = true;
      _initializationTerminationUnproven = false;
      if (identical(_initializationSource, backendInitialization)) {
        _initializationSource = null;
      }
    });
    _initializationSource = backendInitialization;
    final started = _initializeWithinDeadline(backendInitialization);
    _initialization = started;
    return started.catchError((Object error, StackTrace stackTrace) {
      if (!backendSettled) {
        // Do not retry on top of an initialization that timed out only at the
        // Dart join boundary. The source future remains observed and clears
        // this poison only if the backend later confirms it has settled.
        _initializationTerminationUnproven = true;
        unawaited(
          backendInitialization.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
      if (identical(_initialization, started)) _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _initializeWithinDeadline(Future<void> source) async {
    try {
      await source.timeout(_configuration.safety.defaultTimeout);
      return;
    } on TimeoutException {
      _initializationTerminationUnproven = true;
      final sourceSettlement = source.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      try {
        await Future.wait<void>([
          _cancelBackendWithoutLeakingErrors(),
          sourceSettlement,
        ]).timeout(_configuration.safety.terminationGracePeriod);
      } on TimeoutException {
        throw const FfmpegException(
          FfmpegErrorCode.engineUnavailable,
          'The selected engine did not stop within its bounded '
          'initialization termination window.',
        );
      }
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'The selected engine did not initialize before its deadline.',
      );
    }
  }

  Future<void> _cancelBackendWithoutLeakingErrors() async {
    try {
      await _backend.cancel().timeout(
        _configuration.safety.terminationGracePeriod,
      );
    } catch (_) {
      // The active execution remains responsible for reporting engine errors.
    }
  }

  FfmpegResult _cancelledResult(
    FfmpegJob job,
    FfmpegExecutionContext context,
  ) => FfmpegResult(
    jobId: job.id,
    backend: capabilities.backend,
    exitCode: 255,
    elapsed: context.elapsed,
    logs: const [],
    outputBytes: const {},
    cancelled: !context.timedOut,
    timedOut: context.timedOut,
  );

  static FfmpegResult _applyContext(
    FfmpegResult result,
    FfmpegExecutionContext context,
  ) {
    if (context.persistentOutputCommitted) return result;
    final timedOut = result.timedOut || context.timedOut;
    return FfmpegResult(
      jobId: result.jobId,
      backend: result.backend,
      exitCode: result.exitCode,
      elapsed: context.elapsed,
      logs: result.logs,
      outputBytes: result.outputBytes,
      cancelled:
          !timedOut &&
          (result.cancelled || (context.isCancelled && !context.timedOut)),
      timedOut: timedOut,
    );
  }

  void _ensureAvailable() {
    if (_disposed || _disposing) {
      throw const FfmpegException(
        FfmpegErrorCode.disposed,
        'This FFmpeg instance has been disposed.',
      );
    }
  }
}

/// Source-only adapter injection for this package's lifecycle tests.
///
/// The root library exports only [UniversalFfmpeg], so application code cannot
/// select engines or bypass the platform-owned backend policy.
@visibleForTesting
UniversalFfmpeg createUniversalFfmpegForTesting({
  required FfmpegBackend backend,
  FfmpegConfiguration configuration = const FfmpegConfiguration(),
}) => UniversalFfmpeg._(configuration, backend);
