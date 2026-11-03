import '../models/models.dart';

final class DirectGcsWriteGrant {
  const DirectGcsWriteGrant({
    required this.uri,
    required this.expiresAt,
    required this.headers,
  });

  final Uri uri;
  final DateTime expiresAt;
  final Map<String, String> headers;
}

DirectGcsWriteGrant validateDirectGcsWriteGrant({
  required JsonMap data,
  required String expectedBucket,
  required String expectedObject,
  required String expectedContentType,
  required String expectedSha256,
  String? expectedCrc32c,
}) {
  final uri = Uri.tryParse(data['uploadUrl'] as String? ?? '');
  final expiresAt = DateTime.tryParse(
    data['uploadExpiresAt'] as String? ?? '',
  )?.toUtc();
  final now = DateTime.now().toUtc();
  final bucket = data['uploadBucket'] as String? ?? '';
  final objectName = data['uploadObject'] as String? ?? '';
  final headers = _normalizedHeaders(data['uploadHeaders']);
  if (uri == null ||
      expiresAt == null ||
      !expiresAt.isAfter(now) ||
      expiresAt.isAfter(now.add(const Duration(minutes: 16))) ||
      bucket != expectedBucket ||
      objectName != expectedObject ||
      !_writeUrlIdentityMatches(
        uri,
        bucket: expectedBucket,
        objectName: expectedObject,
      ) ||
      !_writeV4ExpiryMatches(
        uri,
        expiresAt,
        expectsCrc32c: expectedCrc32c != null,
      ) ||
      !_headersMatch(
        headers,
        contentType: expectedContentType,
        sha256: expectedSha256,
        crc32c: expectedCrc32c,
      )) {
    throw const FormatException(
      'The ii-os control API returned an invalid GCS upload grant.',
    );
  }
  return DirectGcsWriteGrant(
    uri: uri,
    expiresAt: expiresAt,
    headers: Map.unmodifiable(headers),
  );
}

bool _writeUrlIdentityMatches(
  Uri uri, {
  required String bucket,
  required String objectName,
}) {
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      bucket.isEmpty ||
      objectName.isEmpty) {
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

bool _writeV4ExpiryMatches(
  Uri uri,
  DateTime expiresAt, {
  required bool expectsCrc32c,
}) {
  final query = uri.queryParametersAll;
  final expectedSignedHeaders = [
    'content-type',
    'host',
    if (expectsCrc32c) 'x-goog-hash',
    'x-goog-if-generation-match',
    'x-goog-meta-ii-os-sha256',
  ]..sort();
  if (query.keys.toSet().difference(_writeV4QueryKeys).isNotEmpty ||
      _writeV4QueryKeys.difference(query.keys.toSet()).isNotEmpty ||
      !_single(query, 'X-Goog-Algorithm', 'GOOG4-RSA-SHA256') ||
      !_single(
        query,
        'X-Goog-SignedHeaders',
        expectedSignedHeaders.join(';'),
      )) {
    return false;
  }
  final credentials = query['X-Goog-Credential'];
  final dates = query['X-Goog-Date'];
  final durations = query['X-Goog-Expires'];
  final signatures = query['X-Goog-Signature'];
  if (credentials == null ||
      credentials.length != 1 ||
      dates == null ||
      dates.length != 1 ||
      durations == null ||
      durations.length != 1 ||
      signatures == null ||
      signatures.length != 1 ||
      !RegExp(r'^[1-9][0-9]{0,3}$').hasMatch(durations.single) ||
      !RegExp(r'^[a-f0-9]{512}$').hasMatch(signatures.single)) {
    return false;
  }
  final signedAt = _parseV4Timestamp(dates.single);
  final seconds = int.tryParse(durations.single);
  final now = DateTime.now().toUtc();
  final credential = RegExp(
    r'^([^/]+)/([0-9]{8})/auto/storage/goog4_request$',
  ).firstMatch(credentials.single);
  return signedAt != null &&
      !signedAt.isAfter(now.add(const Duration(minutes: 1))) &&
      seconds != null &&
      seconds <= const Duration(minutes: 15).inSeconds &&
      credential != null &&
      credential.group(1)!.contains('@') &&
      credential.group(2) == dates.single.substring(0, 8) &&
      signedAt.add(Duration(seconds: seconds)) == expiresAt;
}

bool _headersMatch(
  Map<String, String> headers, {
  required String contentType,
  required String sha256,
  required String? crc32c,
}) {
  final expectedKeys = {
    ..._baseWriteHeaderKeys,
    if (crc32c != null) 'x-goog-hash',
  };
  return headers.length == expectedKeys.length &&
      headers.keys.toSet().difference(expectedKeys).isEmpty &&
      headers['content-type'] == contentType &&
      headers['x-goog-if-generation-match'] == '0' &&
      headers['x-goog-meta-ii-os-sha256'] == sha256 &&
      (crc32c == null || headers['x-goog-hash'] == 'crc32c=$crc32c');
}

Map<String, String> _normalizedHeaders(Object? value) {
  if (value is! Map) return const {};
  final output = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) return const {};
    final key = (entry.key! as String).toLowerCase();
    if (output.containsKey(key)) return const {};
    output[key] = entry.value! as String;
  }
  return output;
}

bool _single(Map<String, List<String>> query, String key, String expected) {
  final values = query[key];
  return values != null && values.length == 1 && values.single == expected;
}

DateTime? _parseV4Timestamp(String value) {
  if (!RegExp(r'^[0-9]{8}T[0-9]{6}Z$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(
    '${value.substring(0, 4)}-${value.substring(4, 6)}-'
    '${value.substring(6, 8)}T${value.substring(9, 11)}:'
    '${value.substring(11, 13)}:${value.substring(13, 15)}Z',
  )?.toUtc();
  if (parsed == null || _timestamp(parsed) != value) return null;
  return parsed;
}

String _timestamp(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${two(value.month)}${two(value.day)}T'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
}

const _writeV4QueryKeys = {
  'X-Goog-Algorithm',
  'X-Goog-Credential',
  'X-Goog-Date',
  'X-Goog-Expires',
  'X-Goog-SignedHeaders',
  'X-Goog-Signature',
};

const _baseWriteHeaderKeys = {
  'content-type',
  'x-goog-if-generation-match',
  'x-goog-meta-ii-os-sha256',
};
