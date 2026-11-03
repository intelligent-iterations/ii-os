import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_ffmpeg_universal/src/backend.dart';
import 'package:ii_ffmpeg_universal/src/backends/io_backend.dart';

void main() {
  test('native gate remains poisoned until actual completion proof', () async {
    final gate = FfmpegKitExecutionGate();
    final firstContext = FfmpegExecutionContext(const Duration(seconds: 1));
    final firstLease = await gate.acquire(firstContext);
    expect(firstLease, isNotNull);

    final nativeCompletion = Completer<void>();
    firstLease!.releaseWhen(nativeCompletion.future);

    final secondContext = FfmpegExecutionContext(const Duration(seconds: 1));
    var secondStarted = false;
    final second = gate.acquire(secondContext).then((lease) {
      secondStarted = lease != null;
      return lease;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(secondStarted, isFalse);

    secondContext.cancel(timedOut: true);
    expect(await second, isNull);
    expect(secondStarted, isFalse);

    final thirdContext = FfmpegExecutionContext(const Duration(seconds: 1));
    var thirdStarted = false;
    final third = gate.acquire(thirdContext).then((lease) {
      thirdStarted = lease != null;
      return lease;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(thirdStarted, isFalse);

    nativeCompletion.complete();
    final thirdLease = await third.timeout(const Duration(seconds: 1));
    expect(thirdLease, isNotNull);
    expect(thirdStarted, isTrue);
    thirdLease!.releaseWhen(Future<void>.value());
  });
}
