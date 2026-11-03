import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';

GoogleAuthProvider googleAccountSelectionProvider() =>
    GoogleAuthProvider()
      ..setCustomParameters(const {'prompt': 'select_account'});

({String? clientId, String? serverClientId}) nativeGoogleClientIds(
  TargetPlatform platform, {
  required String iosClientId,
  required String androidServerClientId,
}) {
  return switch (platform) {
    TargetPlatform.iOS => (clientId: iosClientId.trim(), serverClientId: null),
    TargetPlatform.android => (
      clientId: null,
      serverClientId: androidServerClientId.trim(),
    ),
    _ => (clientId: null, serverClientId: null),
  };
}

abstract final class GoogleAuthService {
  static Future<void>? _nativeInitialization;

  static Future<UserCredential> signIn() async {
    if (kIsWeb) {
      return FirebaseAuth.instance.signInWithPopup(
        googleAccountSelectionProvider(),
      );
    }

    final clientIds = nativeGoogleClientIds(
      defaultTargetPlatform,
      iosClientId: AppConfig.googleIosClientId,
      androidServerClientId: AppConfig.googleAndroidServerClientId,
    );
    if ((clientIds.clientId ?? clientIds.serverClientId ?? '').isEmpty) {
      throw FirebaseAuthException(
        code: 'google-client-id-missing',
        message: 'Google Sign-In is not configured for this build.',
      );
    }
    await (_nativeInitialization ??= GoogleSignIn.instance.initialize(
      clientId: clientIds.clientId,
      serverClientId: clientIds.serverClientId,
    ));
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'google-id-token-missing',
        message: 'Google did not return a sign-in token.',
      );
    }
    return FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }
}
