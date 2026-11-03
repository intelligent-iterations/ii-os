import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

final class LocalEditorExportArtifact {
  LocalEditorExportArtifact._({
    required this.byteLength,
    required this.duration,
    required this.contentType,
    required this._directory,
    required this._token,
    required this._mediaPath,
  });

  static const _owner = 'ii-os-local-editor-export-v1';
  static const _markerName = '.ii-disposable-owner';

  final int byteLength;
  final Duration duration;
  final String contentType;
  final Directory _directory;
  final String _token;
  final String _mediaPath;
  String? assetId;
  bool _disposed = false;

  static Future<LocalEditorExportArtifact> create({
    required Uint8List bytes,
    required Duration duration,
    required String contentType,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'ii_os_local_editor_export_',
    );
    final token = _randomToken();
    try {
      await File(_inside(directory, _markerName)).writeAsString(
        jsonEncode({'owner': _owner, 'token': token, 'pid': pid}),
        flush: true,
      );
      final mediaPath = _inside(directory, 'edited-output.mp4');
      await File(mediaPath).writeAsBytes(bytes, flush: true);
      return LocalEditorExportArtifact._(
        byteLength: bytes.length,
        duration: duration,
        contentType: contentType,
        directory: directory,
        token: token,
        mediaPath: mediaPath,
      );
    } catch (_) {
      await _deleteOwnedDirectory(directory, token);
      rethrow;
    }
  }

  void attachAssetId(String value) => assetId = value;

  Future<VideoPlayerController> createController() async {
    if (_disposed) throw StateError('The local editor export was disposed.');
    final controller = VideoPlayerController.file(File(_mediaPath));
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
    await _deleteOwnedDirectory(_directory, _token);
  }

  static Future<void> _deleteOwnedDirectory(
    Directory directory,
    String token,
  ) async {
    try {
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      final marker = File(_inside(directory, _markerName));
      if (await FileSystemEntity.type(marker.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return;
      }
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map ||
          decoded['owner'] != _owner ||
          decoded['token'] != token) {
        return;
      }
      await directory.delete(recursive: true);
    } on Object {
      // Fail closed: preserve a directory whose run ownership is not proven.
    }
  }

  static String _randomToken() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _inside(Directory directory, String name) =>
      '${directory.path}${Platform.pathSeparator}$name';
}
