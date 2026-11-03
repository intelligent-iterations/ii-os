import 'dart:async';

import 'local_video_handle.dart';

typedef SceneVideoHandleResolver = Future<LocalVideoHandle> Function();

final class StoryboardVideoPreloader {
  _PreloadedVideo? _slot;
  bool _disposed = false;

  void preload({
    required String key,
    required SceneVideoHandleResolver resolveHandle,
  }) {
    if (_disposed || _slot?.key == key) return;
    _discard(_slot);

    late final _PreloadedVideo slot;
    final future = _initialize(resolveHandle);
    slot = _PreloadedVideo(key, future);
    _slot = slot;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_slot, slot)) _slot = null;
        },
      ),
    );
  }

  Future<LocalVideoHandle?> take(String key) async {
    final slot = _slot;
    if (_disposed || slot == null || slot.key != key) return null;
    _slot = null;
    try {
      final controller = await slot.future;
      if (_disposed) {
        await controller.dispose();
        return null;
      }
      return controller;
    } on Object {
      return null;
    }
  }

  Future<LocalVideoHandle> _initialize(
    SceneVideoHandleResolver resolveHandle,
  ) async {
    final handle = await resolveHandle();
    try {
      await handle.controller.setLooping(false);
      return handle;
    } on Object {
      await handle.dispose();
      rethrow;
    }
  }

  void clear() {
    _discard(_slot);
    _slot = null;
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void _discard(_PreloadedVideo? slot) {
    if (slot == null) return;
    unawaited(
      slot.future.then<void>(
        (controller) => controller.dispose(),
        onError: (Object _, StackTrace _) {},
      ),
    );
  }
}

final class _PreloadedVideo {
  const _PreloadedVideo(this.key, this.future);

  final String key;
  final Future<LocalVideoHandle> future;
}
