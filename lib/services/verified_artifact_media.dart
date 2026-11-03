import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'artifact_read_url_cache.dart';

const supportedArtifactContentTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'video/webm',
  'audio/mpeg',
  'audio/wav',
  'audio/flac',
};

final int maxPreviewArtifactBytes = kIsWeb
    ? 112 * 1024 * 1024
    : 512 * 1024 * 1024;

final class VerifiedArtifactMedia {
  const VerifiedArtifactMedia({
    required this.identity,
    required this.filename,
    required this.detectedContentType,
    required this.bytes,
  });

  final ArtifactAuthorizationIdentity identity;
  final String filename;
  final String detectedContentType;
  final Uint8List bytes;
}

Future<VerifiedArtifactMedia> downloadVerifiedArtifactMedia({
  required ApiClient api,
  required ArtifactReadGrant grant,
  required ArtifactAuthorizationIdentity expected,
  required int maxBytes,
}) async {
  final uri = Uri.tryParse(grant.url);
  if (uri == null ||
      maxBytes <= 0 ||
      expected.sizeBytes > maxBytes ||
      !expected.matches(grant) ||
      !grant.expiresAt.isAfter(DateTime.now().toUtc()) ||
      !signedArtifactUrlIdentityMatches(
        uri,
        bucket: expected.bucket,
        objectName: expected.objectName,
        generation: expected.generation,
      ) ||
      !signedArtifactUrlExpiryMatches(uri, grant.expiresAt)) {
    throw const FormatException(
      'The workspace asset authorization is unavailable.',
    );
  }
  final bytes = await api.getBytes(uri, maxBytes: expected.sizeBytes);
  if (bytes.length != expected.sizeBytes ||
      sha256.convert(bytes).toString() != expected.sha256) {
    throw const FormatException(
      'The workspace asset bytes do not match their immutable metadata.',
    );
  }
  final detected = detectArtifactMediaContentType(bytes);
  if (detected == null ||
      !_artifactContentTypesAgree(expected.contentType, detected)) {
    throw const FormatException(
      'The workspace asset media type does not match its bytes.',
    );
  }
  return VerifiedArtifactMedia(
    identity: expected,
    filename: expected.objectName.split('/').last,
    detectedContentType: detected,
    bytes: Uint8List.fromList(bytes).asUnmodifiableView(),
  );
}

String? detectArtifactMediaContentType(Uint8List bytes) {
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
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 12) == 'WEBP') {
    return 'image/webp';
  }
  if (bytes.length >= 12 && _ascii(bytes, 4, 8) == 'ftyp') {
    return 'video/mp4';
  }
  if (bytes.length >= 4 && _startsWith(bytes, const [0x1a, 0x45, 0xdf, 0xa3])) {
    return 'video/webm';
  }
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 12) == 'WAVE') {
    return 'audio/wav';
  }
  if (bytes.length >= 4 && _ascii(bytes, 0, 4) == 'fLaC') {
    return 'audio/flac';
  }
  if ((bytes.length >= 3 && _ascii(bytes, 0, 3) == 'ID3') ||
      (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
    return 'audio/mpeg';
  }
  return null;
}

final class VerifiedArtifactMediaCache {
  VerifiedArtifactMediaCache({this.maxEntries = 96, int? maxRetainedBytes})
    : maxRetainedBytes = maxRetainedBytes ?? (kIsWeb ? 64 : 128) * 1024 * 1024;

  final int maxEntries;
  final int maxRetainedBytes;
  final Map<String, _VerifiedArtifactEntry> _entries = {};
  int _retainedBytes = 0;

  Future<VerifiedArtifactMedia> resolve({
    required ArtifactAuthorizationIdentity expected,
    required Future<VerifiedArtifactMedia> Function() load,
  }) {
    final key = expected.cacheKey;
    final existing = _entries[key];
    if (existing?.media case final media?
        when identical(media.identity, expected) ||
            media.identity.cacheKey == expected.cacheKey) {
      _touch(key);
      return Future.value(media);
    }
    if (existing?.pending case final pending?) {
      _touch(key);
      return pending;
    }

    final entry = _VerifiedArtifactEntry();
    _entries[key] = entry;
    return entry.pending = load().then(
      (media) {
        if (media.identity.cacheKey != expected.cacheKey) {
          throw const FormatException(
            'The verified workspace asset identity changed.',
          );
        }
        if (!identical(_entries[key], entry)) return media;
        entry.pending = null;
        if (media.bytes.length > maxRetainedBytes) {
          _entries.remove(key);
          return media;
        }
        entry.media = media;
        _retainedBytes += media.bytes.length;
        _prune();
        return media;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_entries[key], entry)) _entries.remove(key);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  void clear() {
    _entries.clear();
    _retainedBytes = 0;
  }

  /// Moves a key to the most-recently-used end.
  ///
  /// A Dart map iterates in insertion order, so re-inserting is what turns
  /// [_prune]'s "drop the first key" from first-in-first-out into
  /// least-recently-used. Without it, looking at a thumbnail again does
  /// nothing to protect it, and scrolling back up a grid re-downloads
  /// everything it just showed.
  void _touch(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry;
  }

  void _prune() {
    while (_entries.length > maxEntries || _retainedBytes > maxRetainedBytes) {
      final oldestKey = _entries.keys.first;
      final oldest = _entries[oldestKey]!;
      if (oldest.pending != null) {
        _entries.remove(oldestKey);
        continue;
      }
      _entries.remove(oldestKey);
      _retainedBytes -= oldest.media?.bytes.length ?? 0;
    }
  }
}

bool _artifactContentTypesAgree(String declared, String detected) =>
    declared == detected ||
    (declared == 'audio/mp4' && detected == 'video/mp4');

bool _startsWith(Uint8List bytes, List<int> signature) {
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

String _ascii(Uint8List bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start, end));

final class _VerifiedArtifactEntry {
  VerifiedArtifactMedia? media;
  Future<VerifiedArtifactMedia>? pending;
}
