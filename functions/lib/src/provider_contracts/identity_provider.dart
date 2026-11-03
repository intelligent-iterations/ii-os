enum AuthenticationMethod {
  emailOtp,
  google,
  apple,
  localDevelopment,
  unsupported,
}

final class VerifiedIdentity {
  const VerifiedIdentity({
    required this.subject,
    required this.email,
    required this.emailVerified,
    required this.authenticationMethod,
    required this.hasSystemOwnerClaim,
  });

  final String subject;
  final String email;
  final bool emailVerified;
  final AuthenticationMethod authenticationMethod;
  final bool hasSystemOwnerClaim;
}

/// Verifies a human session without exposing a provider token or SDK type to
/// the application layer.
abstract interface class IdentityProvider {
  Future<VerifiedIdentity> verify(String bearerToken);

  /// Mirrors a durable Owner grant into a provider claim when that provider
  /// supports claims. Providers without claim storage implement this as a
  /// no-op; the durable [SystemOwnerRepository] remains authoritative.
  Future<void> grantSystemOwnerClaim(String subject);
}

/// Durable system-Owner authority, separated from the identity provider so an
/// auth migration cannot grant or revoke product authorization by accident.
abstract interface class SystemOwnerRepository {
  Future<bool> contains(String subject);

  Future<void> grant({required String subject, required String email});
}
