import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'protocol.dart';

final class SessionGrantClaims {
  const SessionGrantClaims({
    required this.audience,
    required this.sessionId,
    required this.organizationId,
    required this.workspaceId,
    required this.subject,
    required this.role,
    required this.capabilities,
    required this.generation,
    required this.policyRevision,
    required this.tokenId,
    required this.issuedAt,
    required this.expiresAt,
    this.jobId = '',
    this.leaseId = '',
  });

  factory SessionGrantClaims.fromJson(Map<String, Object?> json) =>
      SessionGrantClaims(
        audience: _string(json, 'aud'),
        sessionId: _string(json, 'sid'),
        organizationId: _string(json, 'org'),
        workspaceId: _string(json, 'workspace'),
        subject: _string(json, 'sub'),
        role: ParticipantRole.values.byName(_string(json, 'role')),
        capabilities: _strings(
          json['capabilities'],
        ).map(SessionCapability.parse).toSet(),
        generation: _int(json, 'generation'),
        policyRevision: _int(json, 'policyRevision'),
        tokenId: _string(json, 'jti'),
        issuedAt: DateTime.fromMillisecondsSinceEpoch(
          _int(json, 'iat') * 1000,
          isUtc: true,
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          _int(json, 'exp') * 1000,
          isUtc: true,
        ),
        jobId: json['job']?.toString() ?? '',
        leaseId: json['lease']?.toString() ?? '',
      );

  final String audience;
  final String sessionId;
  final String organizationId;
  final String workspaceId;
  final String subject;
  final ParticipantRole role;
  final Set<SessionCapability> capabilities;
  final int generation;
  final int policyRevision;
  final String tokenId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String jobId;
  final String leaseId;

  Map<String, Object?> toJson() => {
    'v': interactiveSessionProtocolVersion,
    'aud': audience,
    'sid': sessionId,
    'org': organizationId,
    'workspace': workspaceId,
    'sub': subject,
    'role': role.name,
    'capabilities': capabilities.map((item) => item.wireName).toList()..sort(),
    'generation': generation,
    'policyRevision': policyRevision,
    'jti': tokenId,
    'iat': issuedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    'exp': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    if (jobId.isNotEmpty) 'job': jobId,
    if (leaseId.isNotEmpty) 'lease': leaseId,
  };
}

final class SessionGrantSigner {
  SessionGrantSigner(List<int> key, {Random? random})
    : _key = List.unmodifiable(key),
      _random = random ?? Random.secure() {
    if (_key.length < 32) {
      throw ArgumentError.value(key.length, 'key', 'must be at least 32 bytes');
    }
  }

  final List<int> _key;
  final Random _random;

  String mint(SessionGrantClaims claims) {
    final header = _encode(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'IISG'})),
    );
    final payload = _encode(utf8.encode(jsonEncode(claims.toJson())));
    final body = '$header.$payload';
    final signature = Hmac(sha256, _key).convert(utf8.encode(body)).bytes;
    return '$body.${_encode(signature)}';
  }

  SessionGrantClaims verify(
    String token, {
    required String audience,
    required DateTime now,
    String? sessionId,
  }) {
    final parts = token.split('.');
    if (parts.length != 3) throw const SessionGrantException('grant_malformed');
    final body = '${parts[0]}.${parts[1]}';
    final expected = Hmac(sha256, _key).convert(utf8.encode(body)).bytes;
    late List<int> actual;
    try {
      actual = base64Url.decode(base64Url.normalize(parts[2]));
    } on FormatException {
      throw const SessionGrantException('grant_malformed');
    }
    if (!_constantTimeEquals(expected, actual)) {
      throw const SessionGrantException('grant_signature_invalid');
    }
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) throw const SessionGrantException('grant_malformed');
    final claims = SessionGrantClaims.fromJson(payload.cast<String, Object?>());
    if (claims.audience != audience) {
      throw const SessionGrantException('grant_audience_mismatch');
    }
    if (sessionId != null && claims.sessionId != sessionId) {
      throw const SessionGrantException('grant_session_mismatch');
    }
    if (!claims.expiresAt.isAfter(now.toUtc())) {
      throw const SessionGrantException('grant_expired');
    }
    if (claims.issuedAt.isAfter(now.toUtc().add(const Duration(seconds: 30)))) {
      throw const SessionGrantException('grant_not_yet_valid');
    }
    return claims;
  }

  String newTokenId() {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return _encode(bytes);
  }
}

final class SessionGrantException implements Exception {
  const SessionGrantException(this.code);

  final String code;

  @override
  String toString() => 'SessionGrantException($code)';
}

String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _constantTimeEquals(List<int> left, List<int> right) {
  var different = left.length ^ right.length;
  for (var index = 0; index < left.length; index++) {
    different |= left[index] ^ (index < right.length ? right[index] : 0);
  }
  return different == 0;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('$key required');
  return value;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key required');
  return value.toInt();
}

Iterable<String> _strings(Object? value) =>
    value is List<Object?> ? value.whereType<String>() : const [];
