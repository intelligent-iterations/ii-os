part of 'io_backend.dart';

extension on IoFfmpegBackend {
  Future<void> _checkExecutable(FfmpegOperation operation) async {
    final engine = await _desktopBundleReady();
    final executable = operation == FfmpegOperation.ffmpeg
        ? engine.ffmpeg
        : engine.ffprobe;
    const deadline = Duration(seconds: 10);
    final launch = Completer<void>();
    _activeLaunch = launch;
    Process? process;
    var joined = false;
    try {
      final started = Process.start(
        executable,
        const ['-version'],
        runInShell: false,
        workingDirectory: engine.directory,
        environment: _sanitizedProcessEnvironment(
          engine.directory,
          engineDirectory: engine.directory,
        ),
        includeParentEnvironment: false,
      );
      process = await _waitForWorkOrCancellation<Process>(
        started,
        deadline,
        timeoutFailure: TimeoutException(
          '$executable process launch timed out.',
          deadline,
        ),
        onAbandoned: (lateProcess) =>
            _stopProcess(lateProcess, _activeTerminationGrace),
      );
      _activeProcess = process;
      final exitFuture = process.exitCode;
      // Install the termination barrier before the first operation that can
      // throw or suspend after Process.start. Cleanup must never infer that a
      // live child has stopped merely because stdin setup failed.
      _engineStopped = exitFuture.then<void>((_) {});
      await process.stdin.close();
      final stdoutDone = process.stdout.drain<void>();
      final stderrDone = process.stderr.drain<void>();
      if (!launch.isCompleted) launch.complete();
      if (_cancelRequested) {
        await _stopProcess(process, _activeTerminationGrace);
      }
      final exit = await Future.any<int?>([
        exitFuture,
        Future<int?>.delayed(deadline),
      ]);
      if (exit == null) {
        await _stopProcess(process, _activeTerminationGrace);
        throw TimeoutException(
          '$executable version check timed out.',
          deadline,
        );
      }
      joined = true;
      await Future.wait([stdoutDone, stderrDone]);
      if (_cancelRequested) {
        throw const FfmpegException(
          FfmpegErrorCode.cancelled,
          'Native engine initialization was cancelled.',
        );
      }
      if (exit != 0) {
        throw FfmpegException(
          FfmpegErrorCode.engineUnavailable,
          '$executable version check exited with $exit.',
        );
      }
    } finally {
      if (!launch.isCompleted) launch.complete();
      if (process != null && !joined) {
        await _stopProcess(process, _activeTerminationGrace);
      }
      _activeProcess = null;
      _engineStopped = null;
      if (identical(_activeLaunch, launch)) _activeLaunch = null;
    }
  }

  Future<FfmpegResult> _executeProcess(
    FfmpegJob job,
    List<String> arguments,
    FfmpegSafetyPolicy safety,
    FfmpegExecutionContext context,
    String workingDirectory,
    FfmpegProgressCallback? onProgress,
  ) async {
    final started = Stopwatch()..start();
    final logs = _BoundedLogStore(safety);
    if (job.operation == FfmpegOperation.ffmpeg) {
      arguments.insertAll(0, const ['-progress', 'pipe:2', '-nostats']);
    }
    final engine = await _desktopBundleReady();
    final executable = job.operation == FfmpegOperation.ffmpeg
        ? engine.ffmpeg
        : engine.ffprobe;
    final process = await _startProcessBounded(
      executable,
      arguments,
      context.remaining,
      workingDirectory: workingDirectory,
      engineDirectory: engine.directory,
    );
    _activeProcess = process;
    final exitFuture = process.exitCode;
    // See _checkExecutable: the exit barrier owns the workspace immediately
    // after launch, before closing stdin or attaching stream listeners.
    _engineStopped = exitFuture.then<void>((_) {});
    // Managed jobs never accept standard-stream inputs. Closing stdin also
    // prevents a malformed demuxer from waiting on an inherited pipe while the
    // execution deadline is the only remaining escape hatch.
    await process.stdin.close();

    final stdoutSink = _BoundedLogSink(logs);
    final stderrSink = _BoundedLogSink(
      logs,
      onLine: (line) => _readProgressLine(job, line, onProgress),
    );
    final stdoutDone = process.stdout.listen(stdoutSink.add).asFuture<void>();
    final stderrDone = process.stderr.listen(stderrSink.add).asFuture<void>();
    final launch = _activeLaunch;
    if (launch != null && !launch.isCompleted) launch.complete();
    if (context.isCancelled || _cancelRequested) {
      await _stopProcess(process, safety.terminationGracePeriod);
    }
    final timeout = context.remaining;
    final exit = await Future.any<int?>([
      exitFuture,
      Future<int?>.delayed(timeout),
    ]);
    final timedOut = exit == null;
    if (timedOut) await _stopProcess(process, safety.terminationGracePeriod);
    final exitCode = exit ?? await exitFuture;
    await Future.wait([stdoutDone, stderrDone]);
    stdoutSink.close();
    stderrSink.close();
    started.stop();
    return FfmpegResult(
      jobId: job.id,
      backend: capabilities.backend,
      exitCode: exitCode,
      elapsed: started.elapsed,
      logs: logs.snapshot,
      outputBytes: const {},
      cancelled: !timedOut && _cancelRequested,
      timedOut: timedOut,
    );
  }

  Map<String, String> _sanitizedProcessEnvironment(
    String workspace, {
    String? engineDirectory,
  }) {
    final environment = <String, String>{
      'HOME': workspace,
      'LANG': 'C',
      'LC_ALL': 'C',
      'TEMP': workspace,
      'TMP': workspace,
      'TMPDIR': workspace,
    };
    if (Platform.isWindows) {
      for (final name in ['SystemRoot', 'WINDIR', 'SystemDrive']) {
        final value = Platform.environment[name];
        if (value != null && value.isNotEmpty) environment[name] = value;
      }
      if (engineDirectory != null) environment['PATH'] = engineDirectory;
    } else if (engineDirectory != null) {
      if (Platform.isLinux) environment['LD_LIBRARY_PATH'] = engineDirectory;
      if (Platform.isMacOS) {
        environment['DYLD_LIBRARY_PATH'] = engineDirectory;
        environment['DYLD_FALLBACK_LIBRARY_PATH'] = engineDirectory;
      }
    }
    return environment;
  }

  void _readProgressLine(
    FfmpegJob job,
    String line,
    FfmpegProgressCallback? onProgress,
  ) {
    if (!line.startsWith('out_time_us=')) return;
    final micros = int.tryParse(line.substring('out_time_us='.length));
    if (micros == null) return;
    onProgress?.call(_progress(job, Duration(microseconds: micros)));
  }

  FfmpegProgress _progress(FfmpegJob job, Duration processed, {double? speed}) {
    final total = job.expectedDuration;
    final fraction = total == null || total.inMicroseconds <= 0
        ? null
        : (processed.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0);
    return FfmpegProgress(
      jobId: job.id,
      processed: processed,
      fraction: fraction,
      speed: speed,
    );
  }

  Future<Process> _startProcessBounded(
    String executable,
    List<String> arguments,
    Duration timeout, {
    String? workingDirectory,
    String? engineDirectory,
  }) async {
    if (timeout <= Duration.zero) {
      throw const FfmpegException(
        FfmpegErrorCode.timedOut,
        'The execution deadline expired before the process could start.',
      );
    }
    final started = Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
      environment: _sanitizedProcessEnvironment(
        workingDirectory ?? Directory.systemTemp.path,
        engineDirectory: engineDirectory,
      ),
      includeParentEnvironment: false,
    );
    final lateStopped = Completer<void>();
    try {
      return await _waitForWorkOrCancellation<Process>(
        started,
        timeout,
        timeoutFailure: const FfmpegException(
          FfmpegErrorCode.timedOut,
          'The FFmpeg process did not start before its deadline.',
        ),
        onAbandoned: (lateProcess) async {
          try {
            await _stopProcess(lateProcess, _activeTerminationGrace);
            if (!lateStopped.isCompleted) lateStopped.complete();
          } catch (error, stackTrace) {
            if (!lateStopped.isCompleted) {
              lateStopped.completeError(error, stackTrace);
            }
          }
        },
      );
    } on FfmpegException catch (error) {
      if (error.code == FfmpegErrorCode.cancelled ||
          error.code == FfmpegErrorCode.timedOut) {
        _engineStopped = lateStopped.future;
      }
      rethrow;
    }
  }

  Future<void> _stopProcess(Process process, Duration grace) async {
    if (Platform.isWindows) {
      process.kill();
      try {
        await process.exitCode.timeout(grace);
        return;
      } on TimeoutException catch (error) {
        throw FfmpegException(
          FfmpegErrorCode.executionFailed,
          'FFmpeg did not stop within the termination grace period.',
          cause: error,
        );
      }
    }
    // The configured grace bounds the complete TERM-to-KILL sequence. Giving
    // each signal the full duration lets backend cancellation consume twice
    // its advertised budget, so an outer lifecycle join can time out while
    // this method is only beginning its forceful phase.
    final gracefulWindow = Duration(microseconds: grace.inMicroseconds ~/ 2);
    final forcefulWindow = grace - gracefulWindow;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(gracefulWindow);
      return;
    } on TimeoutException {
      // Escalate below.
    }
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(forcefulWindow);
    } on TimeoutException catch (error) {
      // Keep the workspace when the OS still considers FFmpeg alive.
      throw FfmpegException(
        FfmpegErrorCode.executionFailed,
        'FFmpeg remained alive after forceful termination; its workspace was '
        'preserved.',
        cause: error,
      );
    }
  }
}
