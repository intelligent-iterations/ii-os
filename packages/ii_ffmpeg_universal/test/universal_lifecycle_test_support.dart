part of 'universal_lifecycle_test.dart';

final class _HungExecuteBackend implements FfmpegBackend {
  _HungExecuteBackend({this.cancelCompletes = false});

  final bool cancelCompletes;
  final finish = Completer<FfmpegResult>();
  var cancelCount = 0;
  var disposeCount = 0;

  @override
  FfmpegCapabilities get capabilities => const FfmpegCapabilities(
    backend: 'hung-execute-test',
    platform: 'test',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: false,
    inProcess: true,
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) => finish.future;

  @override
  Future<void> cancel() {
    cancelCount += 1;
    return cancelCompletes ? Future.value() : Completer<void>().future;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _HungInitializeBackend implements FfmpegBackend {
  final finish = Completer<void>();
  var initializeCount = 0;
  var cancelCount = 0;

  @override
  FfmpegCapabilities get capabilities => const FfmpegCapabilities(
    backend: 'hung-initialize-test',
    platform: 'test',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: false,
    inProcess: true,
  );

  @override
  Future<void> initialize() {
    initializeCount += 1;
    return finish.future;
  }

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) => throw UnsupportedError('initialize-only backend');

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

FfmpegResult _backendSuccess(String jobId) => FfmpegResult(
  jobId: jobId,
  backend: 'hung-execute-test',
  exitCode: 0,
  elapsed: Duration.zero,
  logs: const [],
  outputBytes: const {},
);

final class _HungDisposeBackend implements FfmpegBackend {
  @override
  FfmpegCapabilities get capabilities => const FfmpegCapabilities(
    backend: 'hung-dispose-test',
    platform: 'test',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: false,
    inProcess: true,
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) => throw UnsupportedError('dispose-only backend');

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => Completer<void>().future;
}

final class _CommittedBackend implements FfmpegBackend {
  @override
  FfmpegCapabilities get capabilities => FfmpegCapabilities(
    backend: 'committed-test',
    platform: 'test',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: false,
    inProcess: true,
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) async {
    context.recordPersistentOutputCommit();
    context.cancel();
    return FfmpegResult(
      jobId: job.id,
      backend: capabilities.backend,
      exitCode: 0,
      elapsed: context.elapsed,
      logs: const [],
      outputBytes: const {},
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

final class _LifecycleBackend implements FfmpegBackend {
  final initializationStarted = Completer<void>();
  final _allowInitialization = Completer<void>();
  var cancelCount = 0;
  var disposeCount = 0;

  @override
  FfmpegCapabilities get capabilities => FfmpegCapabilities(
    backend: 'lifecycle-test',
    platform: 'test',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: false,
    inProcess: true,
  );

  @override
  Future<void> initialize() async {
    if (!initializationStarted.isCompleted) initializationStarted.complete();
    await _allowInitialization.future;
  }

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) => throw UnsupportedError('lifecycle-only backend');

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    if (!_allowInitialization.isCompleted) _allowInitialization.complete();
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class _ThrowingBackend implements FfmpegBackend {
  @override
  FfmpegCapabilities get capabilities => FfmpegCapabilities(
    backend: 'throwing-test',
    platform: 'test',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: false,
    inProcess: true,
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) => throw StateError('backend detail');

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

final class _TimeoutReportingBackend implements FfmpegBackend {
  var initializeCount = 0;

  @override
  FfmpegCapabilities get capabilities => FfmpegCapabilities(
    backend: 'timeout-test',
    platform: 'test',
    supportsPathInputs: false,
    supportsByteInputs: true,
    supportsFfprobe: false,
    inProcess: true,
  );

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) async {
    await context.whenCancelled;
    return FfmpegResult(
      jobId: job.id,
      backend: capabilities.backend,
      exitCode: 255,
      elapsed: context.elapsed,
      logs: const [],
      outputBytes: const {},
      cancelled: true,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
