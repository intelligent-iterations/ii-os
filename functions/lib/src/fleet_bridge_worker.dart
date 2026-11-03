import 'dart:async';
import 'dart:io';

import 'fleet_bridge.dart';

abstract interface class BridgeWakeStore {
  Future<void> mark();

  Future<void> clear();

  Future<bool> hasWake();
}

final class FileBridgeWakeStore implements BridgeWakeStore {
  FileBridgeWakeStore(this.file);

  final File file;

  @override
  Future<void> mark() async {
    await file.parent.create(recursive: true);
    await file.writeAsString('ready\n', flush: true);
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> hasWake() => file.exists();
}

final class FleetBridgeWorker {
  FleetBridgeWorker({
    required this.bridge,
    required this.wakeStore,
    this.interval = const Duration(seconds: 5),
    this.maxActiveDuration = const Duration(hours: 2, minutes: 5),
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    this.onError,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _delay = delay ?? Future<void>.delayed;

  final FleetBridgeTicker bridge;
  final BridgeWakeStore wakeStore;
  final Duration interval;
  final Duration maxActiveDuration;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  Future<void>? _active;

  Future<void> resume() async {
    if (await wakeStore.hasWake()) _start();
  }

  Future<void> wake() async {
    await wakeStore.mark();
    _start();
  }

  Future<void> waitForIdle() async => await _active;

  void _start() {
    if (_active != null) return;
    late final Future<void> operation;
    operation = _run().whenComplete(() {
      if (identical(_active, operation)) _active = null;
    });
    _active = operation;
  }

  Future<void> _run() async {
    final startedAt = _clock();
    while (_clock().difference(startedAt) < maxActiveDuration) {
      try {
        final result = await bridge.tick();
        if (!result.pending) {
          await wakeStore.clear();
          return;
        }
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
      await _delay(interval);
    }
  }
}
