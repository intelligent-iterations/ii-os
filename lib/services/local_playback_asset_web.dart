import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

final class LocalPlaybackAsset {
  LocalPlaybackAsset._(this.uri, this._objectUrl);

  final Uri uri;
  final String _objectUrl;
  bool _disposed = false;

  static Future<LocalPlaybackAsset> create({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: contentType),
    );
    final objectUrl = web.URL.createObjectURL(blob);
    return LocalPlaybackAsset._(Uri.parse(objectUrl), objectUrl);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    web.URL.revokeObjectURL(_objectUrl);
  }
}
