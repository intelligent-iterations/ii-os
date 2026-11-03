part of 'organization_resources.dart';

OrganizationResourceCatalog promoteLegacyWorkspaceResources({
  required OrganizationResourceCatalog current,
  required String organizationId,
  required String sourceWorkspaceId,
  required DataPlaneConnection connection,
  required int? installationId,
  required Set<String> repositories,
  required Set<String> githubPermissions,
}) {
  if (organizationId.isEmpty ||
      sourceWorkspaceId.isEmpty ||
      connection.isOrganizationBound ||
      connection.workspaceId != sourceWorkspaceId ||
      connection.configurationChecks().any((check) => !check.passed)) {
    throw const FormatException('The legacy workspace connection is invalid.');
  }
  final existingGcp = current.gcp(legacyGcpResourceId);
  if (existingGcp != null &&
      (existingGcp.legacySourceWorkspaceId != sourceWorkspaceId ||
          jsonEncode(existingGcp.connection.toJson()) !=
              jsonEncode(connection.toJson()))) {
    throw const FormatException(
      'A different legacy workspace connection is already promoted.',
    );
  }
  var result = existingGcp != null
      ? current
      : current.upsertGcp(
          OrganizationGcpResource(
            id: legacyGcpResourceId,
            name: 'Existing GCP project',
            connection: connection,
            permissionEnvelope: gcpResourcePermissions,
            legacySourceWorkspaceId: sourceWorkspaceId,
          ),
        );
  if (installationId != null &&
      installationId > 0 &&
      connection.githubAppId.isNotEmpty &&
      connection.githubAppSecret.isNotEmpty) {
    final existing = current.github(legacyGithubResourceId);
    if (repositories.isEmpty ||
        existing != null &&
            (existing.secretGcpResourceId != legacyGcpResourceId ||
                existing.appId != connection.githubAppId ||
                existing.privateKeySecret != connection.githubAppSecret ||
                existing.installationId != installationId)) {
      throw const FormatException(
        'The accepted GitHub installation does not match the existing resource.',
      );
    }
    result = result.upsertGitHub(
      OrganizationGitHubResource(
        id: legacyGithubResourceId,
        name: existing?.name ?? 'Existing GitHub App',
        secretGcpResourceId: legacyGcpResourceId,
        appId: connection.githubAppId,
        privateKeySecret: connection.githubAppSecret,
        installationId: installationId,
        repositories: repositories,
        permissionEnvelope: githubPermissions,
        active: existing?.active ?? true,
      ),
    );
  }
  return result;
}
