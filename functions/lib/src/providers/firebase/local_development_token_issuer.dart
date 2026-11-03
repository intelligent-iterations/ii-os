final class LocalDevelopmentTokenRequest {
  const LocalDevelopmentTokenRequest._({
    required this.projectId,
    required this.email,
    required this.displayName,
    required this.provision,
  });

  factory LocalDevelopmentTokenRequest.parse({
    required String projectId,
    required String profile,
    required String email,
    required String displayName,
    required bool provision,
  }) {
    final normalizedProject = projectId.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = displayName.trim();
    if (profile.trim() != 'dev') {
      throw const FormatException(
        'Local development tokens are available only for the dev profile.',
      );
    }
    if (!RegExp(
      r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$',
    ).hasMatch(normalizedProject)) {
      throw const FormatException('The Firebase project ID is invalid.');
    }
    if (normalizedEmail.length > 254 ||
        !RegExp(
          r'^[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
        ).hasMatch(normalizedEmail)) {
      throw const FormatException('The local operator email is invalid.');
    }
    if (normalizedName.isEmpty || normalizedName.length > 100) {
      throw const FormatException(
        'The local operator display name must be 1-100 characters.',
      );
    }
    return LocalDevelopmentTokenRequest._(
      projectId: normalizedProject,
      email: normalizedEmail,
      displayName: normalizedName,
      provision: provision,
    );
  }

  final String projectId;
  final String email;
  final String displayName;
  final bool provision;

  Map<String, Object?> get developerClaims => const {
    'ii_os_auth_method': 'local_development',
  };
}
