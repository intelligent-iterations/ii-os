import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

final class LocalPlaybackAsset {
  LocalPlaybackAsset._(this.uri, this._directory, this._token);

  static const _owner = 'ii-os-local-playback-asset-v1';
  static const _markerName = '.ii-disposable-owner';

  final Uri uri;
  final Directory _directory;
  final String _token;
  bool _disposed = false;

  static Future<LocalPlaybackAsset> create({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'ii_os_local_playback_',
    );
    final token = _randomToken();
    try {
      await File(_inside(directory, _markerName)).writeAsString(
        jsonEncode({'owner': _owner, 'token': token, 'pid': pid}),
        flush: true,
      );
      final media = File(
        _inside(directory, 'verified-media.${_extension(contentType)}'),
      );
      await media.writeAsBytes(bytes, flush: true);
      return LocalPlaybackAsset._(media.uri, directory, token);
    } on Object {
      await _deleteOwnedDirectory(directory, token);
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
      // Preserve anything whose exact disposable ownership cannot be proven.
    }
  }

  static String _extension(String contentType) => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'video/webm' => 'webm',
    'audio/mpeg' => 'mp3',
    'audio/wav' => 'wav',
    'audio/flac' => 'flac',
    _ => 'mp4',
  };

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
