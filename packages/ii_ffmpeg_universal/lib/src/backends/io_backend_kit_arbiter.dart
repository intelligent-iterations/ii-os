part of 'io_backend.dart';

/// FFmpegKit configuration, callbacks, history, and native execution are
/// process-global. Serialize sessions across every UniversalFfmpeg instance in
/// this Dart isolate. The native adapter separately admits only one Flutter
/// engine per process because FFmpegKit callbacks and sessions are global.
/// Process-global FIFO gate for the in-process FFmpegKit engine.
///
/// Public only so the adverse no-completion behavior can be verified without
/// launching a mobile engine in a host-side unit test. It is not exported by
/// the package entrypoint.
final class FfmpegKitExecutionGate {
  FfmpegKitExecutionGate();

  static final FfmpegKitExecutionGate shared = FfmpegKitExecutionGate();

  Future<void> _tail = Future<void>.value();

  Future<FfmpegKitExecutionLease?> acquire(
    FfmpegExecutionContext context,
  ) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    final acquiredSignal = Object();
    final cancelledSignal = Object();
    final outcome = await Future.any<Object>([
      previous.then<Object>((_) => acquiredSignal),
      context.whenCancelled.then<Object>((_) => cancelledSignal),
    ]);
    if (identical(outcome, cancelledSignal) || context.isCancelled) {
      // Preserve FIFO ordering even though this caller can return immediately.
      // The next lease is released only after the predecessor actually exits.
      unawaited(
        previous.whenComplete(() {
          if (!released.isCompleted) released.complete();
        }),
      );
      return null;
    }
    return FfmpegKitExecutionLease._(released);
  }
}

final class FfmpegKitExecutionLease {
  FfmpegKitExecutionLease._(this._released);

  final Completer<void> _released;

  void releaseWhen(Future<void> nativeCompletion) {
    // FFmpegKit is process-global and cannot be force-killed. A bounded caller
    // may stop waiting, but the process gate must remain occupied until the
    // native completion callback proves that the prior session has stopped.
    // Deliberately leave the gate poisoned forever if that proof never arrives.
    unawaited(
      nativeCompletion.then<void>(
        (_) {
          if (!_released.isCompleted) _released.complete();
        },
        // An error is not native-stop proof. Consume it and retain the poison.
        onError: (Object _, StackTrace _) {},
      ),
    );
  }
}
