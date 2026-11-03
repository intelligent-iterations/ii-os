import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';

import 'api_client.dart';

final class PasswordlessChallenge {
  const PasswordlessChallenge({
    required this.email,
    required this.expiresAt,
    required this.resendAt,
    required this.maxAttempts,
  });

  final String email;
  final DateTime expiresAt;
  final DateTime resendAt;
  final int maxAttempts;
}

/// The passwordless sign-in exchange: request a code, verify it, sign in.
///
/// An interface rather than a concrete class so `AuthViewModel` can be unit
/// tested without a Firebase app or a live control API -- the same reason the
/// repositories in `lib/repositories/` are interfaces.
abstract interface class PasswordlessAuthClient {
  /// Requests a one-time code for [email] and returns the challenge it opened.
  Future<PasswordlessChallenge> start(String email);

  /// Exchanges [code] for a Firebase session.
  Future<UserCredential> verifyAndSignIn(String code);

  /// The address the open challenge was sent to, if there is one.
  String? get email;

  /// Forgets the open challenge.
  void clear();

  /// Releases the underlying HTTP client.
  void close();
}

final class PasswordlessApiAuthClient implements PasswordlessAuthClient {
  PasswordlessApiAuthClient({ApiClient? api, FirebaseAuth? auth})
    : _api = api ?? ApiClient(reportFailures: false),
      _providedAuth = auth;

  final ApiClient _api;
  final FirebaseAuth? _providedAuth;
  String? _challengeId;
  String? _clientNonce;
  String? _email;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  @override
  Future<PasswordlessChallenge> start(String email) async {
    final nonce = _newNonce();
    final normalizedEmail = email.trim().toLowerCase();
    final response = await _api.postPublic(
      'v1/auth/otp/start',
      body: {'email': normalizedEmail, 'clientNonce': nonce},
    );
    final challengeId = response['challengeId'];
    final expiresIn = response['expiresInSeconds'];
    final resendAfter = response['resendAfterSeconds'];
    final maxAttempts = response['maxAttempts'];
    if (challengeId is! String ||
        expiresIn is! int ||
        resendAfter is! int ||
        maxAttempts is! int) {
      throw const ApiFailure(
        'invalid_response',
        'The server returned an unreadable sign-in response.',
      );
    }
    _challengeId = challengeId;
    _clientNonce = nonce;
    _email = normalizedEmail;
    final now = DateTime.now();
    return PasswordlessChallenge(
      email: normalizedEmail,
      expiresAt: now.add(Duration(seconds: expiresIn)),
      resendAt: now.add(Duration(seconds: resendAfter)),
      maxAttempts: maxAttempts,
    );
  }

  @override
  Future<UserCredential> verifyAndSignIn(String code) async {
    final challengeId = _challengeId;
    final nonce = _clientNonce;
    if (challengeId == null || nonce == null) {
      throw const ApiFailure('challenge_stale', 'Send a new code to continue.');
    }
    final verified = await _api.postPublic(
      'v1/auth/otp/verify',
      body: {
        'challengeId': challengeId,
        'code': code.trim(),
        'clientNonce': nonce,
      },
    );
    final magicExchange = verified['magicExchange'];
    if (magicExchange is! String || magicExchange.isEmpty) {
      throw const ApiFailure(
        'invalid_response',
        'The server returned an unreadable sign-in response.',
      );
    }
    final exchanged = await _api.postPublic(
      'v1/auth/otp/exchange',
      body: {
        'challengeId': challengeId,
        'magicExchange': magicExchange,
        'clientNonce': nonce,
      },
    );
    final customToken = exchanged['customToken'];
    if (customToken is! String || customToken.isEmpty) {
      throw const ApiFailure(
        'invalid_response',
        'The server returned an unreadable sign-in response.',
      );
    }
    try {
      return await _auth.signInWithCustomToken(customToken);
    } finally {
      clear();
    }
  }

  @override
  String? get email => _email;

  @override
  void clear() {
    _challengeId = null;
    _clientNonce = null;
    _email = null;
  }

  @override
  void close() => _api.close();
}

String _newNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
