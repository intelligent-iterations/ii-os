import 'dart:convert';

/// The tenant-owned GitHub App private key, wrapped with the identity it
/// belongs to.
///
/// The wrapper is the anti-substitution control: the broker holds separately
/// scoped grants from many tenants, so it re-checks on every load that the key
/// it just read names the same thing the connection does. Without it, a
/// misconfigured Secret Manager grant would be enough to mint an installation
/// token for somebody else's App.
///
/// Schema 1 names a workspace; schema 2 names an organization; schema 3 also
/// carries the App ID required for discovery. All remain readable, and
/// [bindingId] is compared with the tier owning the connection.
final class GitHubAppSecret {
  const GitHubAppSecret({
    required this.workspaceId,
    required this.privateKey,
    this.organizationId = '',
    this.appId = '',
  });

  factory GitHubAppSecret.parse(String value) {
    if (utf8.encode(value).length > 64 * 1024) {
      throw const FormatException('GitHub App secret is too large.');
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('GitHub App secret must be JSON.');
    }
    final json = decoded.cast<String, Object?>();
    final version = json['schemaVersion'];
    final fields = switch (version) {
      1 => _workspaceFields,
      2 => _organizationFields,
      3 => _discoverableOrganizationFields,
      _ => null,
    };
    if (fields == null || json.keys.any((key) => !fields.contains(key))) {
      throw const FormatException(
        'Use a supported workspace-bound or organization-bound GitHub App '
        'secret.',
      );
    }
    final privateKey = json['privateKey'] as String? ?? '';
    final workspaceId = version == 1
        ? (json['workspaceId'] as String? ?? '').trim()
        : '';
    final organizationId = version == 2 || version == 3
        ? (json['organizationId'] as String? ?? '').trim()
        : '';
    final appId = version == 3 ? (json['appId'] as String? ?? '').trim() : '';
    if ((version == 1 ? workspaceId : organizationId).isEmpty ||
        (version == 3 && !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(appId)) ||
        !_validPrivateKey(privateKey)) {
      throw const FormatException(
        'GitHub App secret has an invalid binding or private key.',
      );
    }
    return GitHubAppSecret(
      workspaceId: workspaceId,
      organizationId: organizationId,
      privateKey: privateKey,
      appId: appId,
    );
  }

  final String workspaceId;

  /// The tenant this key belongs to, for a schema-v2 payload.
  final String organizationId;
  final String privateKey;
  final String appId;

  bool get isOrganizationBound => organizationId.isNotEmpty;
  bool get isDiscoverable => isOrganizationBound && appId.isNotEmpty;

  /// The identifier the connection carrying this key must agree with.
  String get bindingId => isOrganizationBound ? organizationId : workspaceId;

  bool isBoundTo({
    required String bindingId,
    required bool organizationBound,
  }) => isOrganizationBound == organizationBound && this.bindingId == bindingId;
}

const _workspaceFields = {'schemaVersion', 'workspaceId', 'privateKey'};
const _organizationFields = {'schemaVersion', 'organizationId', 'privateKey'};
const _discoverableOrganizationFields = {
  'schemaVersion',
  'organizationId',
  'appId',
  'privateKey',
};

bool _validPrivateKey(String value) {
  if (utf8.encode(value).length > 32 * 1024) return false;
  final trimmed = value.trim();
  return (trimmed.startsWith('-----BEGIN PRIVATE KEY-----') && // gitleaks:allow
          trimmed.endsWith('-----END PRIVATE KEY-----')) ||
      (trimmed.startsWith(
            '-----BEGIN RSA PRIVATE KEY-----',
          ) && // gitleaks:allow
          trimmed.endsWith('-----END RSA PRIVATE KEY-----'));
}
