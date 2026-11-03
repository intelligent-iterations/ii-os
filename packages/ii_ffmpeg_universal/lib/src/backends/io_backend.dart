import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_full/abstract_session.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_full/statistics.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../backend.dart';
import '../capabilities.dart';
import '../configuration.dart';
import '../exception.dart';
import '../execution_constraints.dart';
import '../job.dart';
import 'io_workspace.dart';

part 'io_backend_kit.dart';
part 'io_backend_kit_arbiter.dart';
part 'io_backend_pe.dart';
part 'io_backend_process_bundle.dart';
part 'io_backend_process.dart';
part 'io_log_store.dart';

enum _NativeEngine { ffmpegKit, process }

final class IoFfmpegBackend implements FfmpegBackend {
  IoFfmpegBackend(FfmpegConfiguration configuration)
    : _safety = configuration.safety,
      _desktopBundle = configuration.desktopBundle,
      _workspaceRoot = configuration.nativeWorkspaceRoot == null
          ? null
          : Directory(configuration.nativeWorkspaceRoot!),
      _engine = Platform.isAndroid || Platform.isIOS
          ? _NativeEngine.ffmpegKit
          : _NativeEngine.process;

  static const int _maxLogLines = 5000;
  static final Object _cancelledWait = Object();
  static final Object _timedOutWait = Object();

  final _NativeEngine _engine;
  final FfmpegSafetyPolicy _safety;
  final FfmpegDesktopBundle? _desktopBundle;
  final Directory? _workspaceRoot;
  Process? _activeProcess;
  int? _activeSessionId;
  Completer<void>? _activeLaunch;
  Future<void>? _engineStopped;
  Future<void>? _kitReleaseBarrier;
  final Set<Future<void>> _activeLifecycle = <Future<void>>{};
  final Set<Future<void>> _pendingLifecycle = <Future<void>>{};
  FfmpegException? _pendingLifecycleFailure;
  bool _cancelRequested = false;
  FfmpegException? _runtimeLimitFailure;
  IoWorkspace? _desktopEngineWorkspace;
  _StagedDesktopBundle? _stagedDesktopBundle;
  Duration _activeTerminationGrace = const Duration(seconds: 5);
  Completer<void> _cancellation = Completer<void>();

  @override
  FfmpegCapabilities get capabilities => FfmpegCapabilities(
    backend: Platform.isWindows
        ? 'unsupported'
        : _engine == _NativeEngine.ffmpegKit
        ? 'ffmpeg-kit'
        : 'process',
    platform: Platform.operatingSystem,
    supportsPathInputs: !Platform.isWindows,
    supportsByteInputs: !Platform.isWindows,
    supportsFfprobe: !Platform.isWindows,
    inProcess: _engine == _NativeEngine.ffmpegKit,
  );

  @override
  Future<void> initialize() async {
    if (Platform.isWindows) {
      throw const FfmpegException(
        FfmpegErrorCode.unsupportedPlatform,
        'Windows execution is disabled until a live isolated Windows release '
        'proof validates the complete desktop engine closure.',
      );
    }
    if (_engine == _NativeEngine.process && _workspaceRoot == null) {
      throw const FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'Desktop execution requires a dedicated absolute nativeWorkspaceRoot '
        'for crash-safe owned cleanup.',
      );
    }
    _activeTerminationGrace = _safety.terminationGracePeriod;
    _resetCancellation();
    await _joinPendingLifecycle();
    try {
      if (_engine == _NativeEngine.ffmpegKit) {
        await _waitForWorkOrCancellation<void>(
          FFmpegKitConfig.init(),
          _safety.defaultTimeout,
          timeoutFailure: const FfmpegException(
            FfmpegErrorCode.engineUnavailable,
            'FFmpegKit initialization exceeded its configured deadline.',
          ),
          onAbandoned: (_) => _restoreSafeKitGlobalState(),
        );
        // Keep log redirection off so sessions cannot accumulate native log
        // text. Statistics remain enabled for the job-scoped progress callback;
        // the Dart adapter throttles delivery and session history is bounded.
        await _waitForWorkOrCancellation<void>(
          FFmpegKitConfig.disableRedirection(),
          _safety.terminationGracePeriod,
          timeoutFailure: const FfmpegException(
            FfmpegErrorCode.engineUnavailable,
            'FFmpegKit redirection setup did not finish safely.',
          ),
        );
        await _waitForWorkOrCancellation<void>(
          FFmpegKitConfig.enableStatistics(),
          _safety.terminationGracePeriod,
          timeoutFailure: const FfmpegException(
            FfmpegErrorCode.engineUnavailable,
            'FFmpegKit progress setup did not finish safely.',
          ),
        );
        await _waitForWorkOrCancellation<void>(
          FFmpegKitConfig.setSessionHistorySize(32),
          _safety.terminationGracePeriod,
          timeoutFailure: const FfmpegException(
            FfmpegErrorCode.engineUnavailable,
            'FFmpegKit history setup did not finish safely.',
          ),
        );
      } else {
        final bundle = _desktopBundle;
        if (bundle == null) {
          throw const FfmpegException(
            FfmpegErrorCode.engineUnavailable,
            'Desktop execution requires an explicit SHA-256-verified '
            'FfmpegDesktopBundle; PATH lookup is disabled.',
          );
        }
        try {
          await _prepareDesktopBundle();
          await _checkExecutable(FfmpegOperation.ffmpeg);
          await _checkExecutable(FfmpegOperation.ffprobe);
        } catch (_) {
          await _disposeDesktopBundle();
          rethrow;
        }
      }
    } on FfmpegException {
      rethrow;
    } catch (error) {
      throw FfmpegException(
        FfmpegErrorCode.engineUnavailable,
        'Unable to initialize the ${capabilities.backend} backend.',
        cause: error,
      );
    }
  }

  @override
  Future<FfmpegResult> execute(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) async {
    _resetCancellation();
    final kitLease = _engine == _NativeEngine.ffmpegKit
        ? await FfmpegKitExecutionGate.shared.acquire(context)
        : null;
    if (_engine == _NativeEngine.ffmpegKit && kitLease == null) {
      return _cancelledResult(job, context);
    }
    _kitReleaseBarrier = null;
    try {
      return await _executeExclusive(
        job,
        safety,
        context: context,
        onProgress: onProgress,
      );
    } finally {
      kitLease?.releaseWhen(_kitReleaseBarrier ?? Future<void>.value());
      _kitReleaseBarrier = null;
    }
  }

  Future<FfmpegResult> _executeExclusive(
    FfmpegJob job,
    FfmpegSafetyPolicy safety, {
    required FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  }) async {
    _runtimeLimitFailure = null;
    _activeTerminationGrace = safety.terminationGracePeriod;
    final launch = Completer<void>();
    _activeLaunch = launch;
    _engineStopped = null;
    IoWorkspace? workspace;
    var stopMonitor = true;
    Future<void>? monitor;
    try {
      workspace = await IoWorkspace.create(job.id, root: _workspaceRoot);
      stopMonitor = false;
      monitor = _monitorWorkspace(
        workspace,
        job,
        safety,
        context,
        () => stopMonitor,
      );
      final replacements =
          await workspace.materializeInputs(job, safety, context)
            ..addAll(workspace.outputPaths(job));
      final workspaceBytes = await workspace.sizeBytes(
        stopAfter: safety.maxWorkspaceBytes,
      );
      final constrained = constrainManagedExecution(
        job,
        safety,
        workspaceBytesAlreadyUsed: workspaceBytes,
        outputOvershootReserveBytes: safety.maxEngineAllocationBytes,
        maxEngineAllocationBytes: safety.maxEngineAllocationBytes,
      );
      final arguments = constrained
          .map((argument) => replacements[argument] ?? argument)
          .toList(growable: true);
      if (job.operation == FfmpegOperation.ffmpeg) {
        arguments.insert(0, job.overwriteOutput ? '-y' : '-n');
        arguments.insert(0, '-nostdin');
      }
      if (context.isCancelled) return _cancelledResult(job, context);
      final result = _engine == _NativeEngine.ffmpegKit
          ? await _executeKit(job, arguments, safety, context, onProgress)
          : await _executeProcess(
              job,
              arguments,
              safety,
              context,
              workspace.directory.path,
              onProgress,
            );
      final limitFailure = _runtimeLimitFailure;
      if (limitFailure != null) throw limitFailure;
      if (!result.isSuccess) return result;
      if (context.isCancelled) return _cancelledResult(job, context);
      final output = await workspace.collectOutputs(job, safety, context);
      return FfmpegResult(
        jobId: result.jobId,
        backend: result.backend,
        exitCode: result.exitCode,
        elapsed: result.elapsed,
        logs: result.logs,
        outputBytes: output,
      );
    } finally {
      if (!launch.isCompleted) launch.complete();
      stopMonitor = true;
      Object? cleanupError;
      StackTrace? cleanupStack;
      var engineStopped = true;
      try {
        if (monitor != null) await monitor;
      } catch (error, stackTrace) {
        cleanupError = error;
        cleanupStack = stackTrace;
      }
      try {
        final stopped = _engineStopped;
        if (stopped != null) {
          await stopped.timeout(safety.terminationGracePeriod);
        }
      } catch (error, stackTrace) {
        engineStopped = false;
        cleanupError ??= error;
        cleanupStack ??= stackTrace;
      } finally {
        _activeProcess = null;
        _activeSessionId = null;
        _engineStopped = null;
        if (identical(_activeLaunch, launch)) _activeLaunch = null;
      }
      if (workspace != null && engineStopped) {
        try {
          await workspace.dispose();
        } catch (error, stackTrace) {
          cleanupError ??= error;
          cleanupStack ??= stackTrace;
        }
      }
      if (cleanupError != null && !context.persistentOutputCommitted) {
        Error.throwWithStackTrace(cleanupError, cleanupStack!);
      }
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    if (!_cancellation.isCompleted) _cancellation.complete();
    final launch = _activeLaunch;
    if (launch != null) {
      await launch.future.timeout(_activeTerminationGrace);
    }
    final sessionId = _activeSessionId;
    if (sessionId != null) {
      await FFmpegKit.cancel(sessionId).timeout(_activeTerminationGrace);
    }
    final process = _activeProcess;
    if (process != null) {
      await _stopProcess(process, _activeTerminationGrace);
    }
    final stopped = _engineStopped;
    if (stopped != null) await stopped.timeout(_activeTerminationGrace);
    await _joinActiveLifecycle();
    await _joinPendingLifecycle();
  }

  Future<T> _waitForWorkOrCancellation<T>(
    Future<T> work,
    Duration timeout, {
    required Object timeoutFailure,
    FutureOr<void> Function(T value)? onAbandoned,
  }) async {
    var abandoned = false;
    final observed = work.then<T>((value) async {
      if (abandoned && onAbandoned != null) {
        await onAbandoned(value);
      }
      return value;
    });
    late final Future<void> active;
    active = observed
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _activeLifecycle.remove(active));
    _activeLifecycle.add(active);
    final timeoutSignal = Completer<Object?>();
    final timer = Timer(timeout, () {
      abandoned = true;
      timeoutSignal.complete(_timedOutWait);
    });
    try {
      final outcome = await Future.any<Object?>([
        observed,
        _cancellation.future.then<Object?>((_) {
          abandoned = true;
          return _cancelledWait;
        }),
        timeoutSignal.future,
      ]);
      if (identical(outcome, _cancelledWait)) {
        _trackPendingLifecycle(observed.then<void>((_) {}));
        throw const FfmpegException(
          FfmpegErrorCode.cancelled,
          'Native engine work was cancelled before it completed.',
        );
      }
      if (identical(outcome, _timedOutWait)) {
        _trackPendingLifecycle(observed.then<void>((_) {}));
        throw timeoutFailure;
      }
      return outcome as T;
    } finally {
      timer.cancel();
    }
  }

  void _resetCancellation() {
    _cancelRequested = false;
    _cancellation = Completer<void>();
  }

  void _trackPendingLifecycle(Future<void> lifecycle) {
    late final Future<void> guarded;
    guarded = lifecycle
        .catchError((Object error, StackTrace stackTrace) {
          _pendingLifecycleFailure ??= FfmpegException(
            FfmpegErrorCode.executionFailed,
            'Abandoned native lifecycle work failed during cleanup.',
            cause: error,
          );
        })
        .whenComplete(() => _pendingLifecycle.remove(guarded));
    _pendingLifecycle.add(guarded);
  }

  Future<void> _joinActiveLifecycle() async {
    final deadline = DateTime.now().add(_activeTerminationGrace);
    while (_activeLifecycle.isNotEmpty) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'Native lifecycle work did not stop within the termination grace '
          'period.',
        );
      }
      await Future.wait(List<Future<void>>.of(_activeLifecycle)).timeout(
        remaining,
        onTimeout: () => throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'Native lifecycle work did not stop within the termination grace '
          'period.',
        ),
      );
    }
  }

  Future<void> _joinPendingLifecycle() async {
    final deadline = DateTime.now().add(_activeTerminationGrace);
    while (_pendingLifecycle.isNotEmpty) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'Native lifecycle cleanup did not finish within the termination '
          'grace period.',
        );
      }
      await Future.wait(List<Future<void>>.of(_pendingLifecycle)).timeout(
        remaining,
        onTimeout: () => throw const FfmpegException(
          FfmpegErrorCode.executionFailed,
          'Native lifecycle cleanup did not finish within the termination '
          'grace period.',
        ),
      );
    }
    final failure = _pendingLifecycleFailure;
    _pendingLifecycleFailure = null;
    if (failure != null) throw failure;
  }

  Future<void> _restoreSafeKitGlobalState() async {
    await FFmpegKitConfig.disableRedirection().timeout(_activeTerminationGrace);
    await FFmpegKitConfig.disableStatistics().timeout(_activeTerminationGrace);
    await FFmpegKitConfig.setSessionHistorySize(
      32,
    ).timeout(_activeTerminationGrace);
  }

  Future<void> _monitorWorkspace(
    IoWorkspace workspace,
    FfmpegJob job,
    FfmpegSafetyPolicy safety,
    FfmpegExecutionContext context,
    bool Function() shouldStop,
  ) async {
    try {
      while (!shouldStop()) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (shouldStop()) return;
        final outputFailure = await workspace.outputLimitViolation(job, safety);
        if (outputFailure != null) {
          _runtimeLimitFailure = outputFailure;
          context.cancel();
          await cancel();
          return;
        }
        final size = await workspace.sizeBytes(
          stopAfter: safety.maxWorkspaceBytes,
        );
        if (size <= safety.maxWorkspaceBytes) continue;
        _runtimeLimitFailure = FfmpegException(
          FfmpegErrorCode.outputTooLarge,
          'The FFmpeg workspace exceeded ${safety.maxWorkspaceBytes} bytes.',
        );
        context.cancel();
        await cancel();
        return;
      }
    } catch (error) {
      _runtimeLimitFailure ??= FfmpegException(
        FfmpegErrorCode.executionFailed,
        'Workspace monitoring failed; FFmpeg was cancelled and cleanup '
        'continued fail-closed.',
        cause: error,
      );
      context.cancel();
      try {
        await cancel();
      } catch (_) {
        // The execution cleanup path still joins or preserves the workspace.
      }
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

  @override
  Future<void> dispose() async {
    Object? cancellationError;
    StackTrace? cancellationStack;
    try {
      await cancel();
    } catch (error, stackTrace) {
      cancellationError = error;
      cancellationStack = stackTrace;
    }
    await _joinPendingLifecycle();
    await _disposeDesktopBundle();
    if (cancellationError != null) {
      Error.throwWithStackTrace(cancellationError, cancellationStack!);
    }
  }
}
