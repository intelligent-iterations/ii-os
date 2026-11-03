import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract final class AppleAuthService {
  static OAuthProvider get _provider => OAuthProvider('apple.com');

  static Future<UserCredential> signIn() {
    final provider = _provider
      ..addScope('email')
      ..addScope('name');
    if (kIsWeb) {
      return FirebaseAuth.instance.signInWithPopup(provider);
    }
    return FirebaseAuth.instance.signInWithProvider(provider);
  }
}
