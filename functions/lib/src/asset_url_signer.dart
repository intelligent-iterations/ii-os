import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:googleapis/iamcredentials/v1.dart' as credentials;
import 'package:googleapis_auth/auth_io.dart';

import 'api_error.dart';
import 'data_plane_connection.dart';
import 'gcs_crc32c.dart';

final class AssetReadGrantCacheIdentity {
  const AssetReadGrantCacheIdentity({
    required this.workspaceId,
    required this.jobId,
    required this.sizeBytes,
    required this.sha256,
    required this.contentType,
  });

  final String workspaceId;
  final String jobId;
  final int sizeBytes;
  final String sha256;
  final String contentType;
}

final class AssetUrlSigner {
  const AssetUrlSigner(this.connection);

  static const _readRefreshBefore = Duration(minutes: 2);
  static const _maxReadGrants = 512;
  static final Map<String, _ReadGrantEntry> _readGrants = {};

  final DataPlaneConnection connection;

  Future<({String url, DateTime expiresAt})> signReadUrl(
    String objectName, {
    Duration lifetime = const Duration(minutes: 15),
    String? generation,
    AssetReadGrantCacheIdentity? cacheIdentity,
  }) async {
    _validateLifetime(lifetime);
    _validateGeneration(generation);
    if (cacheIdentity == null) {
      return _signReadUrl(
        objectName,
        lifetime: lifetime,
        generation: generation,
      );
    }
    _validateReadCacheIdentity(cacheIdentity);
    final now = DateTime.now().toUtc();
    final key = [
      connection.bucket,
      connection.dataServiceAccount,
      cacheIdentity.workspaceId,
      cacheIdentity.jobId,
      objectName,
      generation ?? '',
      cacheIdentity.sizeBytes,
      cacheIdentity.sha256,
      cacheIdentity.contentType,
      lifetime.inSeconds,
    ].join('\n');
    final existing = _readGrants[key];
    final grant = existing?.grant;
    if (grant != null && grant.expiresAt.isAfter(now.add(_readRefreshBefore))) {
      return grant;
    }
    final pending = existing?.pending;
    if (pending != null) return pending;

    final entry = _ReadGrantEntry();
    final request =
        _signReadUrl(
          objectName,
          lifetime: lifetime,
          generation: generation,
        ).then(
          (grant) {
            if (identical(_readGrants[key], entry)) {
              entry
                ..grant = grant
                ..pending = null;
            }
            return grant;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (identical(_readGrants[key], entry)) _readGrants.remove(key);
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    entry.pending = request;
    _readGrants[key] = entry;
    _pruneReadGrants(now);
    return request;
  }

  Future<({String url, DateTime expiresAt})> _signReadUrl(
    String objectName, {
    required Duration lifetime,
    required String? generation,
  }) async {
    if (connection.emulated) {
      final signedAt = _wholeSecond(DateTime.now().toUtc());
      final expiresAt = signedAt.add(lifetime);
      final date = _date(signedAt);
      return (
        url: Uri.https(
          '${connection.bucket}.storage.googleapis.com',
          '/$objectName',
          {
            'X-Goog-Algorithm': 'GOOG4-RSA-SHA256',
            'X-Goog-Credential':
                '${connection.dataServiceAccount}/'
                '$date/auto/storage/goog4_request',
            'X-Goog-Date': _timestamp(signedAt),
            'X-Goog-Expires': lifetime.inSeconds.toString(),
            'X-Goog-SignedHeaders': 'host',
            'X-Goog-Signature': List.filled(512, '0').join(),
            'generation': ?generation,
          },
        ).toString(),
        expiresAt: expiresAt,
      );
    }
    final signed = await _sign(
      method: 'GET',
      objectName: objectName,
      lifetime: lifetime,
      headers: const {},
      query: {'generation': ?generation},
    );
    return (url: signed.url, expiresAt: signed.expiresAt);
  }

  static void _pruneReadGrants(DateTime now) {
    _readGrants.removeWhere(
      (_, entry) =>
          entry.pending == null &&
          (entry.grant == null || !entry.grant!.expiresAt.isAfter(now)),
    );
    while (_readGrants.length > _maxReadGrants) {
      _readGrants.remove(_readGrants.keys.first);
    }
  }

  Future<({String url, DateTime expiresAt, Map<String, String> headers})>
  signWriteUrl({
    required String objectName,
    required String contentType,
    required String sha256Hex,
    String? crc32cBase64,
    Duration lifetime = const Duration(minutes: 5),
  }) async {
    _validateLifetime(lifetime);
    if (crc32cBase64 != null &&
        canonicalGcsCrc32c(crc32cBase64) != crc32cBase64) {
      throw const ApiError(
        400,
        'invalid_asset_checksum',
        'The asset checksum is invalid.',
      );
    }
    final headers = <String, String>{
      'content-type': contentType,
      if (crc32cBase64 != null) 'x-goog-hash': 'crc32c=$crc32cBase64',
      'x-goog-if-generation-match': '0',
      'x-goog-meta-ii-os-sha256': sha256Hex,
    };
    if (connection.emulated) {
      final signedAt = _wholeSecond(DateTime.now().toUtc());
      final expiresAt = signedAt.add(lifetime);
      final date = _date(signedAt);
      final signedHeaderNames = ['host', ...headers.keys]..sort();
      return (
        url: Uri.https(
          '${connection.bucket}.storage.googleapis.com',
          '/$objectName',
          {
            'X-Goog-Algorithm': 'GOOG4-RSA-SHA256',
            'X-Goog-Credential':
                '${connection.dataServiceAccount}/'
                '$date/auto/storage/goog4_request',
            'X-Goog-Date': _timestamp(signedAt),
            'X-Goog-Expires': lifetime.inSeconds.toString(),
            'X-Goog-SignedHeaders': signedHeaderNames.join(';'),
            'X-Goog-Signature': List.filled(512, '0').join(),
          },
        ).toString(),
        expiresAt: expiresAt,
        headers: headers,
      );
    }
    final signed = await _sign(
      method: 'PUT',
      objectName: objectName,
      lifetime: lifetime,
      headers: headers,
      query: const {},
    );
    return (url: signed.url, expiresAt: signed.expiresAt, headers: headers);
  }

  Future<({String url, DateTime expiresAt})> _sign({
    required String method,
    required String objectName,
    required Duration lifetime,
    required Map<String, String> headers,
    required Map<String, String> query,
  }) async {
    final now = _wholeSecond(DateTime.now().toUtc());
    final expiresAt = now.add(lifetime);
    final date = _date(now);
    final timestamp = _timestamp(now);
    final scope = '$date/auto/storage/goog4_request';
    final host = '${connection.bucket}.storage.googleapis.com';
    final canonicalUri = '/${objectName.split('/').map(_encode).join('/')}';
    final canonicalHeaders = <String, String>{'host': host, ...headers};
    final sortedHeaders = canonicalHeaders.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final signedHeaders = sortedHeaders.map((entry) => entry.key).join(';');
    final signedQuery = <String, String>{
      'X-Goog-Algorithm': 'GOOG4-RSA-SHA256',
      'X-Goog-Credential': '${connection.dataServiceAccount}/$scope',
      'X-Goog-Date': timestamp,
      'X-Goog-Expires': lifetime.inSeconds.toString(),
      'X-Goog-SignedHeaders': signedHeaders,
      ...query,
    };
    final canonicalQuery = _canonicalQuery(signedQuery);
    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQuery,
      '${sortedHeaders.map((entry) => '${entry.key}:${entry.value.trim()}').join('\n')}\n',
      signedHeaders,
      'UNSIGNED-PAYLOAD',
    ].join('\n');
    final stringToSign = [
      'GOOG4-RSA-SHA256',
      timestamp,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)),
    ].join('\n');
    final signature = await _signBlob(stringToSign);
    return (
      url:
          'https://$host$canonicalUri?$canonicalQuery&X-Goog-Signature=$signature',
      expiresAt: expiresAt,
    );
  }

  Future<String> _signBlob(String value) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      final response = await credentials.IAMCredentialsApi(client)
          .projects
          .serviceAccounts
          .signBlob(
            credentials.SignBlobRequest(
              payload: base64Encode(utf8.encode(value)),
            ),
            'projects/-/serviceAccounts/${connection.dataServiceAccount}',
          );
      final encoded = response.signedBlob;
      if (encoded == null || encoded.isEmpty) {
        throw StateError('IAM Credentials returned an empty signature.');
      }
      return base64
          .decode(base64.normalize(encoded))
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
    } catch (_) {
      throw const ApiError(
        503,
        'asset_signing_unavailable',
        'The customer data-plane identity could not sign an asset URL.',
      );
    } finally {
      client.close();
    }
  }
}

final class _ReadGrantEntry {
  ({String url, DateTime expiresAt})? grant;
  Future<({String url, DateTime expiresAt})>? pending;
}

void _validateGeneration(String? generation) {
  if (generation != null &&
      !RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(generation)) {
    throw const ApiError(
      400,
      'invalid_asset_generation',
      'The asset generation is invalid.',
    );
  }
}

void _validateReadCacheIdentity(AssetReadGrantCacheIdentity identity) {
  if (identity.workspaceId.isEmpty ||
      identity.jobId.isEmpty ||
      identity.sizeBytes <= 0 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(identity.sha256) ||
      identity.contentType.isEmpty) {
    throw const ApiError(
      409,
      'invalid_asset_cache_identity',
      'The immutable asset authorization identity is invalid.',
    );
  }
}

void _validateLifetime(Duration lifetime) {
  if (lifetime <= Duration.zero || lifetime > const Duration(minutes: 15)) {
    throw const ApiError(
      400,
      'invalid_asset_url_lifetime',
      'Asset grants may last at most 15 minutes.',
    );
  }
}

String _canonicalQuery(Map<String, String> values) {
  final entries = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries
      .map((entry) => '${_encode(entry.key)}=${_encode(entry.value)}')
      .join('&');
}

String _encode(String value) => Uri.encodeComponent(value);

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}'
    '${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}';

String _timestamp(DateTime value) =>
    '${_date(value)}T'
    '${value.hour.toString().padLeft(2, '0')}'
    '${value.minute.toString().padLeft(2, '0')}'
    '${value.second.toString().padLeft(2, '0')}Z';

DateTime _wholeSecond(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
  (value.toUtc().millisecondsSinceEpoch ~/ 1000) * 1000,
  isUtc: true,
);
