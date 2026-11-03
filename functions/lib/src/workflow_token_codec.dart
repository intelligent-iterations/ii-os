import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

typedef SecureByteGenerator = List<int> Function(int length);

final class IssuedWorkflowToken {
  const IssuedWorkflowToken({
    required this.id,
    required this.value,
    required this.digest,
  });

  final String id;
  final String value;
  final String digest;
}

final class ParsedWorkflowToken {
  const ParsedWorkflowToken({required this.id, required this.value});

  final String id;
  final String value;
}

final class WorkflowTokenCodec {
  WorkflowTokenCodec({required String pepper, SecureByteGenerator? randomBytes})
    : _pepper = utf8.encode(pepper),
      _randomBytes = randomBytes ?? _secureBytes;

  static const prefix = 'iiost_v1';

  final List<int> _pepper;
  final SecureByteGenerator _randomBytes;

  bool get isConfigured => _pepper.length >= 32;

  IssuedWorkflowToken issue(String id) {
    if (!_validId(id)) throw ArgumentError.value(id, 'id');
    final secret = base64UrlEncode(_randomBytes(32)).replaceAll('=', '');
    final value = '$prefix.$id.$secret';
    return IssuedWorkflowToken(id: id, value: value, digest: digest(value));
  }

  ParsedWorkflowToken? parse(String value) {
    if (value.length > 160) return null;
    final parts = value.split('.');
    if (parts.length != 3 ||
        parts[0] != prefix ||
        !_validId(parts[1]) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(parts[2])) {
      return null;
    }
    return ParsedWorkflowToken(id: parts[1], value: value);
  }

  String digest(String value) =>
      Hmac(sha256, _pepper).convert(utf8.encode(value)).toString();

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
