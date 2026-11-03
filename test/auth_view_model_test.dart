import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/services/passwordless_auth_client.dart';
import 'package:ii_os/view_models/auth_view_model.dart';

/// Records what the screen asked for and returns whatever the test stages.
final class _FakeAuthClient implements PasswordlessAuthClient {
  _FakeAuthClient({this.onStart, this.onVerify});

  Future<PasswordlessChallenge> Function(String email)? onStart;
  Future<void> Function(String code)? onVerify;

  final startedWith = <String>[];
  final verifiedWith = <String>[];
  int clears = 0;

  @override
  Future<PasswordlessChallenge> start(String email) async {
    startedWith.add(email);
    final handler = onStart;
    if (handler != null) return handler(email);
    return _challenge(email);
  }

  @override
  Future<Never> verifyAndSignIn(String code) async {
    verifiedWith.add(code);
    await onVerify?.call(code);
    // Signing in returns a Firebase UserCredential, which cannot be built in a
    // unit test. Every case here either throws or asserts on what was sent.
    throw const ApiFailure('unreachable', 'no credential in a unit test');
  }

  @override
  String? get email => startedWith.isEmpty ? null : startedWith.last;

  @override
  void clear() => clears++;

  @override
  void close() {}
}

PasswordlessChallenge _challenge(
  String email, {
  Duration resendIn = const Duration(seconds: 30),
  int maxAttempts = 3,
}) {
  final now = DateTime(2026, 8, 2, 12);
  return PasswordlessChallenge(
    email: email,
    expiresAt: now.add(const Duration(minutes: 10)),
    resendAt: now.add(resendIn),
    maxAttempts: maxAttempts,
  );
}

DateTime _fixedNow() => DateTime(2026, 8, 2, 12);

void main() {
  group('sendCode', () {
    test('refuses an empty address without calling the API', () async {
      final client = _FakeAuthClient();
      final model = AuthViewModel(auth: client, clock: _fixedNow);

      await model.sendCode('   ');

      expect(model.errorMessage, 'Enter your email address.');
      expect(client.startedWith, isEmpty);
      expect(model.enteringCode, isFalse);
    });

    test('opens a challenge and adopts its attempt count', () async {
      final client = _FakeAuthClient(
        onStart: (email) async => _challenge(email, maxAttempts: 5),
      );
      final model = AuthViewModel(auth: client, clock: _fixedNow);

      await model.sendCode(' Person@Example.com ');

      expect(client.startedWith, ['Person@Example.com']);
      expect(model.enteringCode, isTrue);
      expect(model.remainingAttempts, 5);
      expect(model.errorMessage, isNull);
    });

    test('a resend cannot retarget a different address', () async {
      final client = _FakeAuthClient();
      final model = AuthViewModel(auth: client, clock: _fixedNow);
      await model.sendCode('first@example.com');

      // The code form has no email field, but nothing should let a caller
      // slip a new address past an open challenge either.
      await model.sendCode('attacker@example.com');

      expect(client.startedWith, ['first@example.com', 'first@example.com']);
    });

    test('reports a failure and stays on the email step', () async {
      final client = _FakeAuthClient(
        onStart: (_) async =>
            throw const ApiFailure('rate_limited', 'Try again in a minute.'),
      );
      final model = AuthViewModel(auth: client, clock: _fixedNow);

      await model.sendCode('person@example.com');

      expect(model.errorMessage, 'Try again in a minute.');
      expect(model.enteringCode, isFalse);
      expect(model.isBusy, isFalse);
    });
  });

  group('verifyCode', () {
    test('refuses a short code without calling the API', () async {
      final client = _FakeAuthClient();
      final model = AuthViewModel(auth: client, clock: _fixedNow);

      await model.verifyCode('123');

      expect(model.errorMessage, 'Enter the 6-digit code.');
      expect(client.verifiedWith, isEmpty);
    });

    test('adopts the remaining attempts the API reports', () async {
      final client = _FakeAuthClient(
        onVerify: (_) async => throw const ApiFailure(
          'invalid_code',
          'That code is not right.',
          details: {'remainingAttempts': 2},
        ),
      );
      final model = AuthViewModel(auth: client, clock: _fixedNow);
      await model.sendCode('person@example.com');

      await model.verifyCode('000000');

      expect(model.remainingAttempts, 2);
      expect(model.errorMessage, 'That code is not right.');
    });

    test('unlocks resend immediately once no attempts remain', () async {
      final client = _FakeAuthClient(
        onStart: (email) async =>
            _challenge(email, resendIn: const Duration(minutes: 5)),
        onVerify: (_) async => throw const ApiFailure(
          'invalid_code',
          'That code is not right.',
          details: {'remainingAttempts': 0},
        ),
      );
      final model = AuthViewModel(auth: client, clock: _fixedNow);
      await model.sendCode('person@example.com');
      expect(model.canResend, isFalse, reason: 'cooldown has not elapsed');

      await model.verifyCode('000000');

      // Waiting out a five-minute cooldown on a dead challenge helps nobody.
      expect(model.canResend, isTrue);
    });
  });

  test('useDifferentEmail clears the challenge and the client', () async {
    final client = _FakeAuthClient();
    final model = AuthViewModel(auth: client, clock: _fixedNow);
    await model.sendCode('person@example.com');

    model.useDifferentEmail();

    expect(model.enteringCode, isFalse);
    expect(model.errorMessage, isNull);
    expect(client.clears, 1);
  });

  group('federated providers', () {
    test('a cancelled sheet is not reported as a failure', () async {
      final model = AuthViewModel(
        auth: _FakeAuthClient(),
        google: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
        clock: _fixedNow,
      );

      await model.signInWithGoogle();

      expect(model.errorMessage, isNull);
      expect(model.isBusy, isFalse);
    });

    test('an unexpected failure is reported and clears busy', () async {
      final model = AuthViewModel(
        auth: _FakeAuthClient(),
        apple: () async => throw StateError('boom'),
        clock: _fixedNow,
      );

      await model.signInWithApple();

      expect(model.errorMessage, 'Authentication failed. Please try again.');
      expect(model.isBusy, isFalse);
    });
  });
}
