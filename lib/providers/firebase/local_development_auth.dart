import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef LocalDevelopmentSessionCheck = Future<bool> Function();
typedef LocalDevelopmentTokenExchange = Future<void> Function(String token);
typedef LocalEmulatorAccountAction = Future<void> Function(String email);

final class LocalDevelopmentAuthException implements Exception {
  const LocalDevelopmentAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class LocalEmulatorAccountExistsException implements Exception {
  const LocalEmulatorAccountExistsException();
}

/// Takes a custom token from the one-shot loopback endpoint and exchanges it
/// for a session-scoped Firebase session. The endpoint exists only in the
/// local development proxy; deployed Hosting never serves it.
final class LocalDevelopmentAuthBootstrap {
  LocalDevelopmentAuthBootstrap({
    required bool enabled,
    required Uri baseUri,
    required http.Client client,
    required LocalDevelopmentSessionCheck hasSession,
    required LocalDevelopmentTokenExchange exchangeCustomToken,
  }) : this._(
         enabled: enabled,
         baseUri: baseUri,
         client: client,
         hasSession: hasSession,
         exchangeCustomToken: exchangeCustomToken,
         ownsClient: false,
       );

  factory LocalDevelopmentAuthBootstrap.firebase({
    required FirebaseAuth auth,
    required bool enabled,
    required Uri baseUri,
    required String expectedEmail,
    http.Client? client,
  }) {
    final normalizedEmail = expectedEmail.trim().toLowerCase();
    return LocalDevelopmentAuthBootstrap._(
      enabled: enabled,
      baseUri: baseUri,
      client: client ?? http.Client(),
      hasSession: () async {
        final user = auth.currentUser;
        if (user == null || user.email?.toLowerCase() != normalizedEmail) {
          return false;
        }
        try {
          final token = await user.getIdTokenResult();
          return token.claims?['ii_os_auth_method'] == 'local_development';
        } on FirebaseAuthException {
          return false;
        }
      },
      exchangeCustomToken: (token) async {
        if (kIsWeb) await auth.setPersistence(Persistence.SESSION);
        await auth.signInWithCustomToken(token);
      },
      ownsClient: client == null,
    );
  }

  const LocalDevelopmentAuthBootstrap._({
    required this.enabled,
    required this.baseUri,
    required this._client,
    required this._hasSession,
    required this._exchangeCustomToken,
    required this._ownsClient,
  });

  final bool enabled;
  final Uri baseUri;
  final http.Client _client;
  final LocalDevelopmentSessionCheck _hasSession;
  final LocalDevelopmentTokenExchange _exchangeCustomToken;
  final bool _ownsClient;

  Future<bool> run() async {
    if (!enabled || await _hasSession()) return false;
    final response = await _client.post(baseUri.resolve('/_ii/local-auth'));
    if (response.statusCode != 200 || response.bodyBytes.length > 16 * 1024) {
      throw const LocalDevelopmentAuthException(
        'The local development sign-in token is unavailable.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const LocalDevelopmentAuthException(
        'The local development sign-in response is invalid.',
      );
    }
    final token = decoded is Map ? decoded['customToken'] : null;
    if (token is! String ||
        token.length > 8 * 1024 ||
        !RegExp(
          r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
        ).hasMatch(token)) {
      throw const LocalDevelopmentAuthException(
        'The local development sign-in response is invalid.',
      );
    }
    await _exchangeCustomToken(token);
    return true;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Creates or resumes one synthetic email account only inside the Firebase
/// Auth emulator. Production disables password Auth and never enables this
/// bootstrap, while the API rejects password sessions outside the emulator.
final class LocalEmulatorAuthBootstrap {
  const LocalEmulatorAuthBootstrap({
    required bool enabled,
    required String email,
    required LocalDevelopmentSessionCheck hasSession,
    required LocalEmulatorAccountAction createAccount,
    required LocalEmulatorAccountAction signIn,
  }) : this._(
         enabled: enabled,
         email: email,
         hasSession: hasSession,
         createAccount: createAccount,
         signIn: signIn,
       );

  factory LocalEmulatorAuthBootstrap.firebase({
    required FirebaseAuth auth,
    required bool enabled,
    required String email,
  }) {
    return LocalEmulatorAuthBootstrap._(
      enabled: enabled,
      email: email,
      hasSession: () async => auth.currentUser != null,
      createAccount: (value) async {
        try {
          await auth.createUserWithEmailAndPassword(
            email: value,
            password: _emulatorPassword,
          );
        } on FirebaseAuthException catch (error) {
          if (error.code == 'email-already-in-use') {
            throw const LocalEmulatorAccountExistsException();
          }
          rethrow;
        }
      },
      signIn: (value) async {
        await auth.signInWithEmailAndPassword(
          email: value,
          password: _emulatorPassword,
        );
      },
    );
  }

  const LocalEmulatorAuthBootstrap._({
    required this.enabled,
    required this.email,
    required this._hasSession,
    required this._createAccount,
    required this._signIn,
  });

  final bool enabled;
  final String email;
  final LocalDevelopmentSessionCheck _hasSession;
  final LocalEmulatorAccountAction _createAccount;
  final LocalEmulatorAccountAction _signIn;

  Future<bool> run() async {
    if (!enabled || await _hasSession()) return false;
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw const LocalDevelopmentAuthException(
        'The local emulator sign-in email is invalid.',
      );
    }
    try {
      await _createAccount(normalizedEmail);
    } on LocalEmulatorAccountExistsException {
      await _signIn(normalizedEmail);
    }
    return true;
  }
}

const _emulatorPassword = 'ii-os-local-emulator-only-2026';
