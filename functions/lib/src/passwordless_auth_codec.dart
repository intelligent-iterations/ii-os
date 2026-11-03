import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final class PasswordlessAuthCodec {
  PasswordlessAuthCodec({required String pepper, Random? random})
    : _key = utf8.encode(pepper),
      _random = random ?? Random.secure() {
    if (_key.length < 32) {
      throw ArgumentError(
        'Passwordless auth pepper must contain at least 32 bytes.',
      );
    }
  }

  final List<int> _key;
  final Random _random;

  String newOtp() => _random.nextInt(1000000).toString().padLeft(6, '0');

  String newExchangeToken(String challengeId, String clientNonce) => base64Url
      .encode(_hmac('exchange-token:$challengeId:$clientNonce'))
      .replaceAll('=', '');

  String otpHash(String challengeId, String otp) =>
      _digest('otp:$challengeId:$otp');

  String exchangeHash(String challengeId, String token) =>
      _digest('exchange:$challengeId:$token');

  String bindingHash(String clientNonce) => _digest('binding:$clientNonce');

  String emailHash(String email) => _digest('email:$email');

  String ipHash(String ip) => _digest('ip:$ip');

  bool matches(String expected, String actual) {
    final left = utf8.encode(expected);
    final right = utf8.encode(actual);
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  String _digest(String value) =>
      base64Url.encode(_hmac(value)).replaceAll('=', '');

  List<int> _hmac(String value) =>
      Hmac(sha256, _key).convert(utf8.encode(value)).bytes;
}
