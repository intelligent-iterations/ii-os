import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

final class LocalEditorExportArtifact {
  LocalEditorExportArtifact._({
    required this.byteLength,
    required this.duration,
    required this.contentType,
    required this._objectUrl,
  });

  final int byteLength;
  final Duration duration;
  final String contentType;
  final String _objectUrl;
  String? assetId;
  bool _disposed = false;

  static Future<LocalEditorExportArtifact> create({
    required Uint8List bytes,
    required Duration duration,
    required String contentType,
  }) async {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: contentType),
    );
    return LocalEditorExportArtifact._(
      byteLength: bytes.length,
      duration: duration,
      contentType: contentType,
      objectUrl: web.URL.createObjectURL(blob),
    );
  }

  void attachAssetId(String value) => assetId = value;

  Future<VideoPlayerController> createController() async {
    if (_disposed) throw StateError('The local editor export was disposed.');
    final controller = VideoPlayerController.networkUrl(Uri.parse(_objectUrl));
    try {
      await controller.initialize();
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    web.URL.revokeObjectURL(_objectUrl);
  }
}
