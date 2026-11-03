import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'local_playback_asset.dart';

final class LocalVideoHandle {
  LocalVideoHandle._(this.controller, this._asset);

  final VideoPlayerController controller;
  final LocalPlaybackAsset? _asset;

  static Future<LocalVideoHandle> create({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final LocalPlaybackAsset? asset;
    final VideoPlayerController controller;
    if (path.isNotEmpty) {
      asset = null;
      controller = VideoPlayerController.file(File(path));
    } else {
      asset = await LocalPlaybackAsset.create(
        bytes: bytes,
        contentType: contentType,
      );
      controller = VideoPlayerController.file(File.fromUri(asset.uri));
    }
    final handle = LocalVideoHandle._(controller, asset);
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
    await _asset?.dispose();
  }
}
