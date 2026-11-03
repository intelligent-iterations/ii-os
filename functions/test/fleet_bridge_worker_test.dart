import 'dart:async';

import 'package:ii_os_functions/src/fleet_bridge.dart';
import 'package:ii_os_functions/src/fleet_bridge_worker.dart';
import 'package:test/test.dart';

void main() {
  test('runs only after a durable wake and stops at terminal state', () async {
    final bridge = _Ticker([
      const FleetBridgeTick(changed: 1, pending: true),
      const FleetBridgeTick(changed: 1, pending: false),
    ]);
    final wakes = _WakeStore();
    final delays = <Duration>[];
    final worker = FleetBridgeWorker(
      bridge: bridge,
      wakeStore: wakes,
      delay: (duration) async => delays.add(duration),
    );

    await worker.resume();
    expect(bridge.calls, 0);
    await worker.wake();
    await worker.waitForIdle();

    expect(bridge.calls, 2);
    expect(delays, [const Duration(seconds: 5)]);
    expect(await wakes.hasWake(), isFalse);
  });

  test(
    'retains wake state when the bounded worker deadline is reached',
    () async {
      final bridge = _Ticker(const [
        FleetBridgeTick(changed: 0, pending: true),
        FleetBridgeTick(changed: 0, pending: true),
      ]);
      final wakes = _WakeStore();
      var now = DateTime.utc(2026, 8, 26);
      final worker = FleetBridgeWorker(
        bridge: bridge,
        wakeStore: wakes,
        clock: () => now,
        maxActiveDuration: const Duration(seconds: 5),
        delay: (duration) async => now = now.add(duration),
      );

      await worker.wake();
      await worker.waitForIdle();

      expect(bridge.calls, 1);
      expect(await wakes.hasWake(), isTrue);
    },
  );

  test('retains its wake and retries a transient bridge failure', () async {
    final bridge = _Ticker([
      StateError('temporary failure'),
      const FleetBridgeTick(changed: 0, pending: false),
    ]);
    final wakes = _WakeStore();
    final errors = <Object>[];
    final worker = FleetBridgeWorker(
      bridge: bridge,
      wakeStore: wakes,
      delay: (_) async {},
      onError: (error, _) => errors.add(error),
    );

    await worker.wake();
    await worker.waitForIdle();

    expect(bridge.calls, 2);
    expect(errors, hasLength(1));
    expect(await wakes.hasWake(), isFalse);
  });
}

final class _Ticker implements FleetBridgeTicker {
  _Ticker(this.results);

  final List<Object> results;
  int calls = 0;

  @override
  Future<FleetBridgeTick> tick() async {
    final index = calls.clamp(0, results.length - 1);
    calls++;
    final result = results[index];
    if (result is Error) throw result;
    return result as FleetBridgeTick;
  }
}

final class _WakeStore implements BridgeWakeStore {
  bool marked = false;

  @override
  Future<void> clear() async => marked = false;

  @override
  Future<bool> hasWake() async => marked;

  @override
  Future<void> mark() async => marked = true;
}
