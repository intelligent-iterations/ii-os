part of 'github_app_transport.dart';

/// The least-privilege installation-token request for [workspace].
Map<String, Object?>? githubInstallationAccessRequestBody(
  Workspace workspace, {
  String? repository,
}) {
  if (!workspace.resourceGrantsExplicit) return null;
  final grant = workspace.primaryGitHubGrant;
  if (grant == null) {
    throw const ApiError(
      409,
      'workspace_github_resource_required',
      'Select a GitHub App for this workspace before using GitHub.',
    );
  }
  if (repository != null && !grant.repositories.contains(repository)) {
    throw const ApiError(
      400,
      'repository_not_allowed',
      'Repository is not configured for this workspace.',
    );
  }
  final selectedRepositories = repository == null
      ? grant.repositories
      : {repository};
  final repositories =
      selectedRepositories
          .map((repository) => repository.split('/').last)
          .toSet()
          .toList()
        ..sort();
  final levels = <String, String>{};
  for (final permission in grant.permissions.toList()..sort()) {
    final separator = permission.lastIndexOf(':');
    if (separator <= 0 || separator == permission.length - 1) continue;
    final name = permission.substring(0, separator);
    final level = permission.substring(separator + 1);
    if (!const {'read', 'write'}.contains(level)) continue;
    if (levels[name] != 'write') levels[name] = level;
  }
  final permissions = {
    for (final name in levels.keys.toList()..sort()) name: levels[name]!,
  };
  if (repositories.isEmpty || permissions.isEmpty) {
    throw const ApiError(
      403,
      'workspace_github_scope_required',
      'Grant at least one repository and GitHub permission to this workspace.',
    );
  }
  return {'repositories': repositories, 'permissions': permissions};
}

/// Returns the repository addressed by a repository-local GitHub REST path.
///
/// Repository calls mint a token for only that repository. This keeps an
/// unrelated renamed or removed repository in the workspace grant from
/// preventing access to a still-authorized repository.
String? githubRepositoryFromRestPath(String path) {
  final uri = Uri.tryParse('https://api.github.com$path');
  final segments = uri?.pathSegments ?? const <String>[];
  if (segments.length < 3 || segments.first != 'repos') return null;
  return '${segments[1]}/${segments[2]}';
}

String githubInstallationAccessCacheKey(
  Workspace workspace, {
  String? repository,
}) => jsonEncode({
  'installationId': workspace.githubInstallationId,
  'scope': githubInstallationAccessRequestBody(
    workspace,
    repository: repository,
  ),
});

final class GitHubInstallationToken {
  const GitHubInstallationToken({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

/// [refresh] always forces a new token so the caller observes the permission
/// set GitHub grants now, not the one captured when the cached token was
/// issued.
bool installationTokenReusable({
  required DateTime? expiresAt,
  required DateTime now,
  required bool refresh,
}) =>
    !refresh &&
    expiresAt != null &&
    expiresAt.isAfter(now.add(const Duration(minutes: 2)));

final class _CachedToken {
  const _CachedToken(this.token, this.expiresAt, this.permissions);

  final String token;
  final DateTime expiresAt;
  final Map<String, String> permissions;
}
