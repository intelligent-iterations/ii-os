import 'package:shelf/shelf.dart';

import 'api_error.dart';
import 'provider_contracts/identity_provider.dart';

final class AuthenticatedUser {
  const AuthenticatedUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.displayName,
    required this.isOwner,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String displayName;
  final bool isOwner;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'email': email,
    'emailVerified': emailVerified,
    'displayName': displayName,
    'isOwner': isOwner,
  };
}

bool isSupportedAuthenticationMethod(AuthenticationMethod method) =>
    method != AuthenticationMethod.unsupported;

final class AuthService {
  AuthService({
    required this.identityProvider,
    required this.systemOwners,
    required Set<String> bootstrapOwnerEmails,
  }) : _bootstrapOwnerEmails = bootstrapOwnerEmails
           .map((email) => email.trim().toLowerCase())
           .where((email) => email.isNotEmpty)
           .toSet();

  final IdentityProvider identityProvider;
  final SystemOwnerRepository systemOwners;
  final Set<String> _bootstrapOwnerEmails;

  Future<AuthenticatedUser> authenticate(Request request) async {
    final authorization = request.headers['authorization'];
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      throw const ApiError(401, 'unauthenticated', 'Sign in is required.');
    }
    final token = authorization.substring('Bearer '.length).trim();
    if (token.isEmpty) {
      throw const ApiError(401, 'unauthenticated', 'Sign in is required.');
    }

    try {
      final identity = await identityProvider.verify(token);
      final email = identity.email.trim().toLowerCase();
      if (!isSupportedAuthenticationMethod(identity.authenticationMethod)) {
        throw const ApiError(
          401,
          'supported_auth_session_required',
          'Sign in again with Google, Apple, or an emailed code.',
        );
      }
      final emailVerified = identity.emailVerified;
      var isOwner = identity.hasSystemOwnerClaim;
      if (!isOwner) {
        isOwner = await systemOwners.contains(identity.subject);
      }
      if (!isOwner && _bootstrapOwnerEmails.contains(email)) {
        if (!emailVerified) {
          throw const ApiError(
            403,
            'owner_email_unverified',
            'Verify the bootstrap Owner email before continuing.',
          );
        }
        await identityProvider.grantSystemOwnerClaim(identity.subject);
        await systemOwners.grant(subject: identity.subject, email: email);
        isOwner = true;
      }
      return AuthenticatedUser(
        uid: identity.subject,
        email: email,
        emailVerified: emailVerified,
        displayName: email.isEmpty ? 'Signed-in user' : email.split('@').first,
        isOwner: isOwner,
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const ApiError(
        401,
        'invalid_auth_token',
        'The session is invalid or expired.',
      );
    }
  }
}
