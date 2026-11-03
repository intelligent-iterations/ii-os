import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';

typedef ArtifactReadUrlLoader = Future<JsonMap> Function();

final class ArtifactReadGrant {
  const ArtifactReadGrant({
    required this.url,
    required this.expiresAt,
    required this.workspaceId,
    required this.jobId,
    required this.bucket,
    required this.objectName,
    required this.generation,
    required this.sizeBytes,
    required this.sha256,
    required this.contentType,
  });

  final String url;
  final DateTime expiresAt;
  final String workspaceId;
  final String jobId;
  final String bucket;
  final String objectName;
  final String generation;
  final int sizeBytes;
  final String sha256;
  final String contentType;
}

final class ArtifactAuthorizationIdentity {
  const ArtifactAuthorizationIdentity({
    required this.workspaceId,
    required this.jobId,
    required this.bucket,
    required this.objectName,
    required this.generation,
    required this.sizeBytes,
    required this.sha256,
    required this.contentType,
  });

  final String workspaceId;
  final String jobId;
  final String bucket;
  final String objectName;
  final String generation;
  final int sizeBytes;
  final String sha256;
  final String contentType;

  String get cacheKey => jsonEncode([
    workspaceId,
    jobId,
    bucket,
    objectName,
    generation,
    sizeBytes,
    sha256,
    contentType,
  ]);

  bool matches(ArtifactReadGrant grant) =>
      grant.workspaceId == workspaceId &&
      grant.jobId == jobId &&
      grant.bucket == bucket &&
      grant.objectName == objectName &&
      grant.generation == generation &&
      grant.sizeBytes == sizeBytes &&
      grant.sha256 == sha256 &&
      grant.contentType == contentType;
}

final class ArtifactReadUrlCache {
  ArtifactReadUrlCache({
    this.refreshBefore = const Duration(seconds: 30),
    this.maxEntries = 256,
  });

  final Duration refreshBefore;

  /// Grants are small, but the map had no ceiling at all: a long session
  /// browsing a large library grew it without bound for the lifetime of the
  /// app.
  final int maxEntries;
  final Map<String, _ArtifactReadUrlEntry> _entries = {};

  Future<ArtifactReadGrant> resolve({
    required ArtifactAuthorizationIdentity expected,
    required ArtifactReadUrlLoader load,
  }) {
    final key = expected.cacheKey;
    final existing = _entries[key];
    final now = DateTime.now().toUtc();
    if (existing != null) _touch(key);
    if (existing?.grant case final grant?
        when expected.matches(grant) &&
            grant.expiresAt.isAfter(now.add(refreshBefore))) {
      return Future.value(grant);
    }
    if (existing?.pending case final pending?) return pending;

    final entry = _ArtifactReadUrlEntry();
    _entries[key] = entry;
    return entry.pending = _load(key, entry, expected: expected, load: load);
  }

  Future<ArtifactReadGrant> _load(
    String key,
    _ArtifactReadUrlEntry entry, {
    required ArtifactAuthorizationIdentity expected,
    required ArtifactReadUrlLoader load,
  }) async {
    try {
      final data = asJsonMap((await load())['data']);
      final url = data['url'] as String? ?? '';
      final expiresAt = DateTime.tryParse(data['expiresAt'] as String? ?? '');
      final uri = Uri.tryParse(url);
      final workspaceId = data['workspaceId'] as String? ?? '';
      final jobId = data['jobId'] as String? ?? '';
      final bucket = data['bucket'] as String? ?? '';
      final objectName = data['object'] as String? ?? '';
      final generation = data['generation'] as String? ?? '';
      final sizeBytes = data['sizeBytes'];
      final sha256 = data['sha256'] as String? ?? '';
      final contentType = data['contentType'] as String? ?? '';
      final now = DateTime.now().toUtc();
      if (url.isEmpty ||
          expiresAt == null ||
          !expiresAt.isAfter(now) ||
          uri == null ||
          !signedArtifactUrlExpiryMatches(uri, expiresAt) ||
          !signedArtifactUrlIdentityMatches(
            uri,
            bucket: bucket,
            objectName: objectName,
            generation: generation,
          ) ||
          sizeBytes is! int ||
          !expected.matches(
            ArtifactReadGrant(
              url: url,
              expiresAt: expiresAt,
              workspaceId: workspaceId,
              jobId: jobId,
              bucket: bucket,
              objectName: objectName,
              generation: generation,
              sizeBytes: sizeBytes,
              sha256: sha256,
              contentType: contentType,
            ),
          )) {
        throw const FormatException('The media URL is unavailable.');
      }
      final grant = ArtifactReadGrant(
        url: url,
        expiresAt: expiresAt.toUtc(),
        workspaceId: workspaceId,
        jobId: jobId,
        bucket: bucket,
        objectName: objectName,
        generation: generation,
        sizeBytes: sizeBytes,
        sha256: sha256,
        contentType: contentType,
      );
      if (identical(_entries[key], entry)) {
        entry
          ..grant = grant
          ..pending = null;
        _prune();
      }
      return grant;
    } on Object {
      if (identical(_entries[key], entry)) _entries.remove(key);
      rethrow;
    }
  }

  /// How many grants are retained. Exposed so the ceiling can be asserted.
  @visibleForTesting
  int get entryCount => _entries.length;

  void clear() => _entries.clear();

  /// Moves a key to the most-recently-used end; see the note on
  /// `VerifiedArtifactMediaCache._touch`.
  void _touch(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _entries[key] = entry;
  }

  void _prune() {
    while (_entries.length > maxEntries) {
      final oldestKey = _entries.keys.first;
      // An in-flight grant is somebody's pending await; dropping the entry
      // only forgets it, it does not cancel them.
      _entries.remove(oldestKey);
    }
  }
}

bool signedArtifactUrlIdentityMatches(
  Uri uri, {
  required String bucket,
  required String objectName,
  required String generation,
}) {
  final generationValues = uri.queryParametersAll['generation'];
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      bucket.isEmpty ||
      objectName.isEmpty ||
      generationValues == null ||
      generationValues.length != 1 ||
      generationValues.single != generation) {
    return false;
  }
  if (uri.host == '$bucket.storage.googleapis.com') {
    return uri.pathSegments.join('/') == objectName;
  }
  return uri.host == 'storage.googleapis.com' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == bucket &&
      uri.pathSegments.skip(1).join('/') == objectName;
}

bool signedArtifactUrlExpiryMatches(Uri uri, DateTime expiresAt) {
  if (uri.queryParametersAll.keys
          .toSet()
          .difference(_readV4QueryKeys)
          .isNotEmpty ||
      _readV4QueryKeys
          .difference(uri.queryParametersAll.keys.toSet())
          .isNotEmpty) {
    return false;
  }
  final algorithms = uri.queryParametersAll['X-Goog-Algorithm'];
  final credentials = uri.queryParametersAll['X-Goog-Credential'];
  final dates = uri.queryParametersAll['X-Goog-Date'];
  final durations = uri.queryParametersAll['X-Goog-Expires'];
  final signedHeaders = uri.queryParametersAll['X-Goog-SignedHeaders'];
  final signatures = uri.queryParametersAll['X-Goog-Signature'];
  if (algorithms == null ||
      algorithms.length != 1 ||
      algorithms.single != 'GOOG4-RSA-SHA256' ||
      credentials == null ||
      credentials.length != 1 ||
      dates == null ||
      dates.length != 1 ||
      durations == null ||
      durations.length != 1 ||
      signedHeaders == null ||
      signedHeaders.length != 1 ||
      signedHeaders.single != 'host' ||
      signatures == null ||
      signatures.length != 1 ||
      !RegExp(r'^[a-f0-9]{512}$').hasMatch(signatures.single) ||
      !RegExp(r'^[1-9][0-9]{0,3}$').hasMatch(durations.single)) {
    return false;
  }
  final seconds = int.tryParse(durations.single);
  final signedAt = _parseV4Timestamp(dates.single);
  final credential = RegExp(
    r'^([^/]+)/([0-9]{8})/auto/storage/goog4_request$',
  ).firstMatch(credentials.single);
  final now = DateTime.now().toUtc();
  return seconds != null &&
      seconds <= const Duration(minutes: 15).inSeconds &&
      signedAt != null &&
      !signedAt.isAfter(now.add(const Duration(minutes: 1))) &&
      expiresAt.toUtc().isAfter(now) &&
      !expiresAt.toUtc().isAfter(now.add(const Duration(minutes: 16))) &&
      credential != null &&
      credential.group(1)!.contains('@') &&
      credential.group(2) == dates.single.substring(0, 8) &&
      signedAt.add(Duration(seconds: seconds)) == expiresAt.toUtc();
}

const _readV4QueryKeys = {
  'generation',
  'X-Goog-Algorithm',
  'X-Goog-Credential',
  'X-Goog-Date',
  'X-Goog-Expires',
  'X-Goog-SignedHeaders',
  'X-Goog-Signature',
};

DateTime? _parseV4Timestamp(String value) {
  if (!RegExp(r'^[0-9]{8}T[0-9]{6}Z$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(
    '${value.substring(0, 4)}-${value.substring(4, 6)}-'
    '${value.substring(6, 8)}T${value.substring(9, 11)}:'
    '${value.substring(11, 13)}:${value.substring(13, 15)}Z',
  )?.toUtc();
  if (parsed == null || _v4Timestamp(parsed) != value) return null;
  return parsed;
}

String _v4Timestamp(DateTime value) {
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

final class _ArtifactReadUrlEntry {
  ArtifactReadGrant? grant;
  Future<ArtifactReadGrant>? pending;
}
