part of 'io_backend.dart';

extension on IoFfmpegBackend {
  Future<FfmpegResult> _executeKit(
    FfmpegJob job,
    List<String> arguments,
    FfmpegSafetyPolicy safety,
    FfmpegExecutionContext context,
    FfmpegProgressCallback? onProgress,
  ) async {
    final started = Stopwatch()..start();
    final logs = _BoundedLogStore(safety);
    final completed = Completer<AbstractSession>();
    _engineStopped = completed.future.then<void>((_) {});
    _kitReleaseBarrier = _engineStopped;
    final launchTimeout = context.remaining;
    final quietArguments = _withoutNativeLogs(job, arguments);
    var lastProgressMilliseconds = -250;

    void reportProgress(Statistics statistics) {
      final milliseconds = statistics.getTime();
      if (milliseconds < lastProgressMilliseconds + 250) return;
      lastProgressMilliseconds = milliseconds;
      onProgress?.call(
        _progress(
          job,
          Duration(milliseconds: milliseconds),
          speed: statistics.getSpeed(),
        ),
      );
    }

    try {
      if (job.operation == FfmpegOperation.ffmpeg) {
        final session = await _waitForWorkOrCancellation<AbstractSession>(
          FFmpegKit.executeWithArgumentsAsync(
            quietArguments,
            (session) => completed.complete(session),
            null,
            onProgress == null ? null : reportProgress,
          ),
          launchTimeout,
          timeoutFailure: const FfmpegException(
            FfmpegErrorCode.timedOut,
            'FFmpegKit did not launch before the execution deadline.',
          ),
          onAbandoned: _cancelLateKitSession,
        );
        _activeSessionId = session.getSessionId();
      } else {
        final session = await _waitForWorkOrCancellation<AbstractSession>(
          FFprobeKit.executeWithArgumentsAsync(
            quietArguments,
            (session) => completed.complete(session),
          ),
          launchTimeout,
          timeoutFailure: const FfmpegException(
            FfmpegErrorCode.timedOut,
            'FFprobeKit did not launch before the execution deadline.',
          ),
          onAbandoned: _cancelLateKitSession,
        );
        _activeSessionId = session.getSessionId();
      }
    } on FfmpegException catch (error) {
      final launch = _activeLaunch;
      if (launch != null && !launch.isCompleted) launch.complete();
      if (error.code == FfmpegErrorCode.cancelled ||
          error.code == FfmpegErrorCode.timedOut) {
        // A late platform launch still owns the workspace until its completion
        // callback. Its hook cancels the session and this barrier joins it.
        rethrow;
      }
      _engineStopped = Future.value();
      _kitReleaseBarrier = _engineStopped;
      rethrow;
    } catch (_) {
      // A channel launch error releases the vendored per-session callback, so
      // no native completion can arrive for this completer.
      _engineStopped = Future.value();
      _kitReleaseBarrier = _engineStopped;
      final launch = _activeLaunch;
      if (launch != null && !launch.isCompleted) launch.complete();
      rethrow;
    }
    final launch = _activeLaunch;
    if (launch != null && !launch.isCompleted) launch.complete();
    if (context.isCancelled || _cancelRequested) {
      final sessionId = _activeSessionId;
      if (sessionId != null) {
        await FFmpegKit.cancel(sessionId).timeout(_activeTerminationGrace);
      }
    }

    final executionRemaining = context.remaining;
    final session = executionRemaining <= Duration.zero
        ? null
        : await Future.any<AbstractSession?>([
            completed.future,
            Future<AbstractSession?>.delayed(executionRemaining),
          ]);
    final finalSession =
        session ??
        await _cancelTimedOutKit(completed).timeout(
          safety.terminationGracePeriod,
          onTimeout: () => throw const FfmpegException(
            FfmpegErrorCode.executionFailed,
            'FFmpegKit did not confirm native completion after cancellation; '
            'the owned workspace was preserved for operator inspection.',
          ),
        );
    final timedOut = session == null;
    final returnCode = await finalSession.getReturnCode();
    started.stop();
    return FfmpegResult(
      jobId: job.id,
      backend: capabilities.backend,
      exitCode: returnCode?.getValue() ?? -1,
      elapsed: started.elapsed,
      logs: logs.snapshot,
      outputBytes: const {},
      cancelled:
          !timedOut && (_cancelRequested || ReturnCode.isCancel(returnCode)),
      timedOut: timedOut,
    );
  }

  List<String> _withoutNativeLogs(FfmpegJob job, List<String> arguments) {
    final quiet = <String>[
      '-loglevel',
      'quiet',
      if (job.operation == FfmpegOperation.ffmpeg) '-nostats',
    ];
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if ((argument == '-loglevel' || argument == '-v') &&
          index + 1 < arguments.length) {
        index += 1;
        continue;
      }
      quiet.add(argument);
    }
    return quiet;
  }

  Future<AbstractSession> _cancelTimedOutKit(
    Completer<AbstractSession> completed,
  ) async {
    final sessionId = _activeSessionId;
    if (sessionId != null) {
      await FFmpegKit.cancel(sessionId).timeout(_activeTerminationGrace);
    }
    // An in-process engine has no safe force-kill operation. Keep its workspace
    // until the native completion callback proves cancellation has stopped it.
    return completed.future;
  }

  Future<void> _cancelLateKitSession(AbstractSession session) async {
    await FFmpegKit.cancel(
      session.getSessionId(),
    ).timeout(_activeTerminationGrace);
  }
}
