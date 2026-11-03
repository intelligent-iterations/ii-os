import 'dart:io';

import 'package:firebase_admin_sdk/auth.dart';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';

import '../../provider_contracts/identity_provider.dart';

final class FirebaseIdentityProvider implements IdentityProvider {
  FirebaseIdentityProvider({
    required FirebaseApp adminApp,
    this.checkRevoked = true,
    this.manageCustomClaims = true,
    this.allowLocalDevelopment = false,
  }) : _auth = adminApp.auth();

  final Auth _auth;
  final bool checkRevoked;
  final bool manageCustomClaims;
  final bool allowLocalDevelopment;

  @override
  Future<VerifiedIdentity> verify(String bearerToken) async {
    final decoded = await _auth.verifyIdToken(
      bearerToken,
      checkRevoked: checkRevoked,
    );
    final usingAuthEmulator =
        Platform.environment['FIREBASE_AUTH_EMULATOR_HOST']?.isNotEmpty == true;
    return VerifiedIdentity(
      subject: decoded.uid,
      email: decoded.email ?? '',
      emailVerified: decoded.emailVerified == true || usingAuthEmulator,
      authenticationMethod: firebaseAuthenticationMethod(
        customClaims: decoded.claims,
        signInProvider: decoded.firebase.signInProvider,
        usingAuthEmulator: usingAuthEmulator,
        allowLocalDevelopment: allowLocalDevelopment,
      ),
      hasSystemOwnerClaim: decoded.claims['ii_os_owner'] == true,
    );
  }

  @override
  Future<void> grantSystemOwnerClaim(String subject) async {
    if (!manageCustomClaims) return;
    final user = await _auth.getUser(subject);
    await _auth.setCustomUserClaims(
      subject,
      customUserClaims: <String, Object?>{
        ...?user.customClaims,
        'ii_os_owner': true,
      },
    );
  }
}

AuthenticationMethod firebaseAuthenticationMethod({
  required Map<String, Object?> customClaims,
  required String signInProvider,
  bool usingAuthEmulator = false,
  bool allowLocalDevelopment = false,
}) {
  if (usingAuthEmulator) return AuthenticationMethod.localDevelopment;
  if (customClaims['ii_os_auth_method'] == 'email_otp') {
    return AuthenticationMethod.emailOtp;
  }
  if (allowLocalDevelopment &&
      signInProvider == 'custom' &&
      customClaims['ii_os_auth_method'] == 'local_development') {
    return AuthenticationMethod.localDevelopment;
  }
  return switch (signInProvider) {
    'google.com' => AuthenticationMethod.google,
    'apple.com' => AuthenticationMethod.apple,
    _ => AuthenticationMethod.unsupported,
  };
}
