import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

typedef FleetKeyRandomBytes = List<int> Function(int length);

final class IssuedFleetReportingKey {
  const IssuedFleetReportingKey({
    required this.id,
    required this.value,
    required this.digest,
  });

  final String id;
  final String value;
  final String digest;
}

final class ParsedFleetReportingKey {
  const ParsedFleetReportingKey({required this.id, required this.value});

  final String id;
  final String value;
}

/// Issues write-only, organization-scoped credentials for fleet reporting.
///
/// A fleet publisher runs on the tenant's own hardware, so it cannot hold a
/// Firebase session and cannot be reached from here. It authenticates with a
/// bearer credential whose cleartext is returned once; Firestore keeps only a
/// digest, so reading the database cannot recover a credential that writes.
///
/// The secret half is 32 bytes from a cryptographic generator and the digest is
/// a plain SHA-256 of the whole credential -- the standard shape for a prefixed
/// machine token. There is deliberately no salt and no pepper. Both defend a
/// *guessable* secret: salt stops one precomputed table cracking many records,
/// and a pepper held outside the database stops offline guessing altogether.
/// Neither applies to 256 bits of entropy, where there is no candidate list to
/// work through and no table worth building. A password-style KDF would be
/// worse still, buying nothing and slowing every request.
///
/// `agent_usage_key_codec.dart` peppers the same shape of credential. That is
/// not this file disagreeing with it: its keys are already issued and stored
/// against that pepper, so changing how they hash would invalidate live
/// credentials. Reconciling the two is a migration, not a cleanup.
final class FleetReportingKeyCodec {
  FleetReportingKeyCodec({FleetKeyRandomBytes? randomBytes})
    : _randomBytes = randomBytes ?? _secureBytes;

  static const prefix = 'iiosf_v1';

  final FleetKeyRandomBytes _randomBytes;

  IssuedFleetReportingKey issue(String id) {
    if (!_validId(id)) throw ArgumentError.value(id, 'id');
    final secret = base64UrlEncode(_randomBytes(32)).replaceAll('=', '');
    final value = '$prefix.$id.$secret';
    return IssuedFleetReportingKey(id: id, value: value, digest: digest(value));
  }

  ParsedFleetReportingKey? parse(String value) {
    if (value.length > 160) return null;
    final parts = value.split('.');
    if (parts.length != 3 ||
        parts[0] != prefix ||
        !_validId(parts[1]) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(parts[2])) {
      return null;
    }
    return ParsedFleetReportingKey(id: parts[1], value: value);
  }

  String digest(String value) => sha256.convert(utf8.encode(value)).toString();

  /// Compared in constant time. The digest is not a secret, but a comparison
  /// that returns early still leaks how much of a guess was right, and that is
  /// free to avoid.
  bool matches(String expectedDigest, String value) =>
      _constantTimeEquals(expectedDigest, digest(value));
}

bool _validId(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
).hasMatch(value);

List<int> _secureBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
