import 'dart:convert';
import 'dart:math';

import 'package:ii_os_functions/src/passwordless_auth_codec.dart';
import 'package:test/test.dart';

void main() {
  final codec = PasswordlessAuthCodec(
    pepper: 'test-passwordless-auth-pepper-with-more-than-32-bytes',
    random: Random(7),
  );
  const challenge = '11111111-1111-4111-8111-111111111111';
  final nonce = base64Url.encode(List<int>.generate(32, (index) => index));

  test('generates bounded six-digit codes', () {
    for (var index = 0; index < 100; index++) {
      expect(codec.newOtp(), matches(RegExp(r'^\d{6}$')));
    }
  });

  test('hashes are scoped and do not reveal the OTP', () {
    final otpHash = codec.otpHash(challenge, '123456');

    expect(otpHash, isNot(contains('123456')));
    expect(otpHash, isNot(codec.otpHash(challenge, '654321')));
    expect(
      otpHash,
      isNot(codec.otpHash('22222222-2222-4222-8222-222222222222', '123456')),
    );
  });

  test('exchange proof is deterministic, scoped, and device bound', () {
    final token = codec.newExchangeToken(challenge, nonce);
    final hash = codec.exchangeHash(challenge, token);

    expect(token, hasLength(43));
    expect(codec.matches(hash, codec.exchangeHash(challenge, token)), isTrue);
    expect(
      codec.newExchangeToken(challenge, nonce),
      token,
      reason: 'A successful verification retry must recover the same proof.',
    );
    expect(
      codec.newExchangeToken(challenge, base64Url.encode(List.filled(32, 9))),
      isNot(token),
    );
  });

  test('rejects a pepper that could be brute-forced', () {
    expect(() => PasswordlessAuthCodec(pepper: 'short'), throwsArgumentError);
  });
}
