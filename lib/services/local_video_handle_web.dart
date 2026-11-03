import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'local_playback_asset.dart';

final class LocalVideoHandle {
  LocalVideoHandle._(this.controller, this._asset);

  final VideoPlayerController controller;
  final LocalPlaybackAsset _asset;

  static Future<LocalVideoHandle> create({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final asset = await LocalPlaybackAsset.create(
      bytes: bytes,
      contentType: contentType,
    );
    final handle = LocalVideoHandle._(
      VideoPlayerController.networkUrl(asset.uri),
      asset,
    );
    try {
      await handle.controller.initialize();
      return handle;
    } on Object {
      await handle.dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    await controller.dispose();
    await _asset.dispose();
  }
}
