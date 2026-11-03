import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'direct_gcs_write_grant.dart';
import 'gcs_crc32c.dart';

final class SourceAssetUploader {
  const SourceAssetUploader(this.api);

  final ApiClient api;

  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async {
    final sha256Hex = sha256.convert(bytes).toString();
    final crc32c = gcsCrc32c(bytes);
    final createdResponse = await api.post(
      'v1/workspaces/$workspaceId/source-assets',
      body: {
        'filename': filename,
        'contentType': contentType,
        'sizeBytes': bytes.length,
        'sha256': sha256Hex,
        'crc32c': crc32c,
        if (ghostMode) 'ghostMode': true,
      },
    );
    final created = asJsonMap(createdResponse['data']);
    final assetId = created['assetId'] as String? ?? '';
    final objectName = created['path'] as String? ?? '';
    final returnedFilename = created['filename'] as String? ?? '';
    final expectedObject =
        'workspaces/$workspaceId/'
        '${ghostMode ? 'ghost-source-assets' : 'source-assets'}/'
        '$assetId/$returnedFilename';
    if (!RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-'
          r'[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(assetId) ||
        expectedBucket.isEmpty ||
        returnedFilename.isEmpty ||
        returnedFilename.contains('/') ||
        objectName != expectedObject) {
      throw const FormatException(
        'The ii-os control API returned an invalid GCS upload grant.',
      );
    }
    final grant = validateDirectGcsWriteGrant(
      data: created,
      expectedBucket: expectedBucket,
      expectedObject: expectedObject,
      expectedContentType: contentType,
      expectedSha256: sha256Hex,
      expectedCrc32c: crc32c,
    );
    await api.putBytes(grant.uri, bytes, headers: grant.headers);
    await api.post(
      'v1/workspaces/$workspaceId/source-assets/$assetId/complete',
    );
    return assetId;
  }
}

String? sourceImageContentType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      _startsWith(bytes, const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ])) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

String? sourceAudioContentType(Uint8List bytes, {String filename = ''}) {
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE') {
    return 'audio/wav';
  }
  if (bytes.length >= 3 && String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3') {
    return 'audio/mpeg';
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
    return 'audio/mpeg';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    return 'audio/mp4';
  }
  final lower = filename.toLowerCase();
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
  return null;
}

String? sourceVideoContentType(Uint8List bytes, {String filename = ''}) {
  final lower = filename.toLowerCase();
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp' &&
      (lower.endsWith('.mp4') ||
          lower.endsWith('.m4v') ||
          lower.endsWith('.mov'))) {
    return 'video/mp4';
  }
  if (bytes.length >= 4 && _startsWith(bytes, const [0x1a, 0x45, 0xdf, 0xa3])) {
    return 'video/webm';
  }
  return null;
}

bool _startsWith(Uint8List bytes, List<int> signature) {
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}
