import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _localDocumentChannel = MethodChannel('ii_os/local_document');

final class LocalDocumentIdentity {
  const LocalDocumentIdentity({
    required this.sha256,
    required this.sizeBytes,
    required this.signatureHex,
  });

  final String sha256;
  final int sizeBytes;
  final String signatureHex;
}

Future<LocalDocumentIdentity> readLocalDocumentIdentity(
  String uri, {
  required int maxBytes,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError(
      'Opaque local document read-back is supported only on Android.',
    );
  }
  if (!uri.startsWith('content://') || maxBytes <= 0) {
    throw ArgumentError('A bounded Android content URI is required.');
  }
  final response = await _localDocumentChannel.invokeMapMethod<String, Object?>(
    'readIdentity',
    {'uri': uri, 'maxBytes': maxBytes},
  );
  final sha256 = response?['sha256'];
  final sizeBytes = response?['sizeBytes'];
  final signatureHex = response?['signatureHex'];
  if (sha256 is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
      sizeBytes is! int ||
      sizeBytes <= 0 ||
      signatureHex is! String ||
      !RegExp(r'^[0-9a-f]{8}$').hasMatch(signatureHex)) {
    throw StateError('Android returned an invalid document identity.');
  }
  return LocalDocumentIdentity(
    sha256: sha256,
    sizeBytes: sizeBytes,
    signatureHex: signatureHex,
  );
}
