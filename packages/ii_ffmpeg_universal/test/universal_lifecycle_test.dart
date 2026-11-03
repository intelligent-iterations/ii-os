import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_ffmpeg_universal/src/backend.dart';
import 'package:ii_ffmpeg_universal/src/universal_ffmpeg.dart'
    show createUniversalFfmpegForTesting;

part 'universal_lifecycle_test_support.dart';

void main() {
  test(
    'dispose joins initialization and concurrent disposal exactly once',
    () async {
      final backend = _LifecycleBackend();
      final ffmpeg = createUniversalFfmpegForTesting(backend: backend);
      final initialization = ffmpeg.initialize();
      await backend.initializationStarted.future;

      final firstDispose = ffmpeg.dispose();
      final secondDispose = ffmpeg.dispose();
      expect(identical(firstDispose, secondDispose), isTrue);

      await Future.wait([initialization, firstDispose, secondDispose]);
      expect(backend.cancelCount, 1);
      expect(backend.disposeCount, 1);
    },
  );

  test('unexpected backend errors use the stable exception model', () async {
    final ffmpeg = createUniversalFfmpegForTesting(backend: _ThrowingBackend());
    addTearDown(ffmpeg.dispose);

    await expectLater(
      ffmpeg.execute(
        FfmpegJob(
          id: 'backend-error',
          arguments: const [
            '-f',
            'lavfi',
            '-i',
            'color=black:s=16x16:d=0.1',
            '-f',
            'null',
            '-',
          ],
        ),
      ),
      throwsA(
        isA<FfmpegException>()
            .having(
              (error) => error.code,
              'code',
              FfmpegErrorCode.executionFailed,
            )
            .having((error) => error.cause, 'cause', isA<StateError>()),
      ),
    );
  });

  test('deadline results are timed out and never also cancelled', () async {
    final backend = _TimeoutReportingBackend();
    final ffmpeg = createUniversalFfmpegForTesting(backend: backend);
    addTearDown(ffmpeg.dispose);

    final result = await ffmpeg.execute(
      FfmpegJob(
        id: 'timeout-normalization',
        arguments: const [
          '-f',
          'lavfi',
          '-i',
          'color=black:s=16x16:d=10',
          '-f',
          'null',
          '-',
        ],
        timeout: const Duration(milliseconds: 10),
      ),
    );

    expect(result.timedOut, isTrue);
    expect(result.cancelled, isFalse);
  });

  test('invalid deadlines fail before backend initialization', () async {
    final backend = _TimeoutReportingBackend();
    final ffmpeg = createUniversalFfmpegForTesting(backend: backend);
    addTearDown(ffmpeg.dispose);

    await expectLater(
      ffmpeg.execute(
        FfmpegJob(
          id: 'invalid-deadline',
          arguments: const ['-f', 'null', '-'],
          timeout: Duration.zero,
        ),
      ),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.invalidJob,
        ),
      ),
    );
    expect(backend.initializeCount, 0);
  });

  test('a persistent commit wins a racing cancellation signal', () async {
    final ffmpeg = createUniversalFfmpegForTesting(
      backend: _CommittedBackend(),
    );
    addTearDown(ffmpeg.dispose);

    final result = await ffmpeg.execute(
      FfmpegJob(id: 'committed-output', arguments: const ['-f', 'null', '-']),
    );

    expect(result.isSuccess, isTrue);
    expect(result.cancelled, isFalse);
    expect(result.timedOut, isFalse);
  });

  test('a non-cooperative execution cannot outlive its bounded join', () async {
    final backend = _HungExecuteBackend();
    final ffmpeg = createUniversalFfmpegForTesting(
      backend: backend,
      configuration: const FfmpegConfiguration(
        safety: FfmpegSafetyPolicy(
          defaultTimeout: Duration(milliseconds: 10),
          maxTimeout: Duration(seconds: 1),
          terminationGracePeriod: Duration(milliseconds: 10),
        ),
      ),
    );

    final result = await ffmpeg
        .execute(
          FfmpegJob(
            id: 'hung-execution',
            arguments: const ['-f', 'null', '-'],
            timeout: const Duration(milliseconds: 10),
          ),
        )
        .timeout(const Duration(seconds: 1));
    expect(result.timedOut, isTrue);
    expect(result.cancelled, isFalse);
    expect(backend.cancelCount, greaterThanOrEqualTo(1));
    await expectLater(
      ffmpeg.execute(
        FfmpegJob(
          id: 'overlap-after-unproven-stop',
          arguments: const ['-f', 'null', '-'],
        ),
      ),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.busy,
        ),
      ),
    );
    backend.finish.complete(_backendSuccess('hung-execution'));
    await Future<void>.delayed(Duration.zero);
    await ffmpeg.dispose();
  });

  test('timed-out initialization cannot overlap a retry', () async {
    final backend = _HungInitializeBackend();
    final ffmpeg = createUniversalFfmpegForTesting(
      backend: backend,
      configuration: const FfmpegConfiguration(
        safety: FfmpegSafetyPolicy(
          defaultTimeout: Duration(milliseconds: 10),
          maxTimeout: Duration(seconds: 1),
          terminationGracePeriod: Duration(milliseconds: 10),
        ),
      ),
    );

    await expectLater(
      ffmpeg.initialize(),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.engineUnavailable,
        ),
      ),
    ).timeout(const Duration(seconds: 1));
    expect(backend.cancelCount, 1);
    await expectLater(
      ffmpeg.initialize(),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.engineUnavailable,
        ),
      ),
    );
    expect(backend.initializeCount, 1);
    await expectLater(
      ffmpeg.cancel(),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.executionFailed,
        ),
      ),
    ).timeout(const Duration(seconds: 1));
    expect(backend.cancelCount, 2);

    backend.finish.complete();
    await Future<void>.delayed(Duration.zero);
    await ffmpeg.initialize();
    expect(backend.initializeCount, 2);
    await ffmpeg.dispose();
  });

  test('job deadline bounds initialization and its termination join', () async {
    final backend = _HungInitializeBackend();
    final ffmpeg = createUniversalFfmpegForTesting(
      backend: backend,
      configuration: const FfmpegConfiguration(
        safety: FfmpegSafetyPolicy(
          defaultTimeout: Duration(seconds: 30),
          maxTimeout: Duration(seconds: 30),
          terminationGracePeriod: Duration(milliseconds: 10),
        ),
      ),
    );

    final stopwatch = Stopwatch()..start();
    final result = await ffmpeg
        .execute(
          FfmpegJob(
            id: 'short-initialization-deadline',
            arguments: const ['-f', 'null', '-'],
            timeout: const Duration(milliseconds: 10),
          ),
        )
        .timeout(const Duration(seconds: 1));
    stopwatch.stop();

    expect(result.timedOut, isTrue);
    expect(result.cancelled, isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(backend.cancelCount, greaterThanOrEqualTo(1));
    await expectLater(
      ffmpeg.initialize(),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.engineUnavailable,
        ),
      ),
    );
    backend.finish.complete();
    await Future<void>.delayed(Duration.zero);
    await ffmpeg.dispose();
  });

  test(
    'explicit cancellation never joins a non-cooperative job unbounded',
    () async {
      final backend = _HungExecuteBackend(cancelCompletes: true);
      final ffmpeg = createUniversalFfmpegForTesting(
        backend: backend,
        configuration: const FfmpegConfiguration(
          safety: FfmpegSafetyPolicy(
            defaultTimeout: Duration(seconds: 30),
            maxTimeout: Duration(seconds: 30),
            terminationGracePeriod: Duration(milliseconds: 10),
          ),
        ),
      );
      final execution = ffmpeg.execute(
        FfmpegJob(
          id: 'hung-explicit-cancel',
          arguments: const ['-f', 'null', '-'],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        ffmpeg.cancel(),
        throwsA(
          isA<FfmpegException>().having(
            (error) => error.code,
            'code',
            FfmpegErrorCode.executionFailed,
          ),
        ),
      ).timeout(const Duration(seconds: 1));
      backend.finish.complete(_backendSuccess('hung-explicit-cancel'));
      expect((await execution).cancelled, isTrue);
      await ffmpeg.dispose();
    },
  );

  test('dispose never joins a non-cooperative active job unbounded', () async {
    final backend = _HungExecuteBackend(cancelCompletes: true);
    final ffmpeg = createUniversalFfmpegForTesting(
      backend: backend,
      configuration: const FfmpegConfiguration(
        safety: FfmpegSafetyPolicy(
          defaultTimeout: Duration(seconds: 30),
          maxTimeout: Duration(seconds: 30),
          terminationGracePeriod: Duration(milliseconds: 10),
        ),
      ),
    );
    final execution = ffmpeg.execute(
      FfmpegJob(
        id: 'hung-active-dispose',
        arguments: const ['-f', 'null', '-'],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      ffmpeg.dispose(),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.executionFailed,
        ),
      ),
    ).timeout(const Duration(seconds: 1));
    expect(backend.disposeCount, 1);
    backend.finish.complete(_backendSuccess('hung-active-dispose'));
    expect((await execution).cancelled, isTrue);
  });

  test('a non-cooperative dispose is bounded by termination grace', () async {
    final ffmpeg = createUniversalFfmpegForTesting(
      backend: _HungDisposeBackend(),
      configuration: const FfmpegConfiguration(
        safety: FfmpegSafetyPolicy(
          defaultTimeout: Duration(seconds: 1),
          maxTimeout: Duration(seconds: 1),
          terminationGracePeriod: Duration(milliseconds: 10),
        ),
      ),
    );

    await expectLater(
      ffmpeg.dispose(),
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.code,
          'code',
          FfmpegErrorCode.executionFailed,
        ),
      ),
    ).timeout(const Duration(seconds: 1));
  });
}
