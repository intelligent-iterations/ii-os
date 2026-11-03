import 'dart:convert';

import 'package:googleapis/secretmanager/v1.dart' as secretmanager;
import 'package:googleapis_auth/auth_io.dart';

import 'data_plane_connection.dart';
import 'github_app_secret.dart';
import 'github_app_transport.dart';
import 'organization_resources.dart';

final class DiscoveredGitHubResource {
  const DiscoveredGitHubResource({
    required this.appId,
    required this.privateKeySecret,
    required this.installationId,
    required this.repositories,
    required this.permissions,
  });

  final String appId;
  final String privateKeySecret;
  final int installationId;
  final Set<String> repositories;
  final Set<String> permissions;
}

final class GcpGitHubDiscovery {
  const GcpGitHubDiscovery({required this.resources, required this.checks});

  final List<DiscoveredGitHubResource> resources;
  final List<ConnectionCheck> checks;
}

final class GcpGitHubDiscoveryService {
  const GcpGitHubDiscoveryService({
    required this.client,
    required this.projectId,
    required this.organizationId,
  });

  final AuthClient client;
  final String projectId;
  final String organizationId;

  Future<GcpGitHubDiscovery> discover() async {
    try {
      final response = await secretmanager.SecretManagerApi(client)
          .projects
          .secrets
          .list(
            'projects/$projectId',
            filter: 'labels.ii_os_resource=github_app',
            pageSize: 21,
          );
      final secrets = response.secrets ?? const [];
      if (secrets.length > 20) {
        return _failed(
          'github_secret_limit',
          'Use no more than 20 GitHub App secrets in one organization project.',
        );
      }
      final owned = secrets
          .where(
            (secret) =>
                secret.labels?['ii_os_organization_id'] == organizationId,
          )
          .toList();
      if (owned.isEmpty) {
        return _failed(
          'github_secret_discovery',
          'Label at least one GitHub App secret for this organization.',
        );
      }
      final discovered = await Future.wait(owned.map(_discoverSecret));
      final resources = discovered.expand((value) => value).toList();
      if (resources.isEmpty || resources.length > 20) {
        return _failed(
          'github_installation_discovery',
          'Install the discovered GitHub Apps with no more than 20 installations total.',
        );
      }
      return GcpGitHubDiscovery(
        resources: resources,
        checks: const [
          ConnectionCheck(
            id: 'github_app_discovery',
            label: 'GitHub Apps',
            status: 'passed',
            detail: 'GitHub App secrets and installations were discovered.',
          ),
        ],
      );
    } on Object {
      return _failed(
        'github_app_discovery',
        'Grant secret access and use an organization-bound GitHub App secret.',
      );
    }
  }

  Future<List<DiscoveredGitHubResource>> _discoverSecret(
    secretmanager.Secret reference,
  ) async {
    final name = reference.name ?? '';
    if (!_secretName.hasMatch(name)) throw const FormatException();
    final response = await secretmanager.SecretManagerApi(
      client,
    ).projects.secrets.versions.access('$name/versions/latest');
    final encoded = response.payload?.data;
    if (encoded == null || encoded.isEmpty) throw const FormatException();
    final secret = GitHubAppSecret.parse(utf8.decode(base64.decode(encoded)));
    if (!secret.isDiscoverable || secret.organizationId != organizationId) {
      throw const FormatException();
    }
    final transport = GitHubAppTransport(
      appId: secret.appId,
      privateKey: secret.privateKey,
    );
    try {
      final installations = await transport.discoverInstallations();
      return installations
          .map(
            (installation) => DiscoveredGitHubResource(
              appId: secret.appId,
              privateKeySecret: name,
              installationId: installation.installationId,
              repositories: installation.repositories,
              permissions: discoveredGitHubPermissions(
                installation.permissions,
              ),
            ),
          )
          .toList();
    } finally {
      transport.close();
    }
  }
}

Set<String> discoveredGitHubPermissions(Map<String, String> values) {
  return githubPermissionEnvelope(values);
}

GcpGitHubDiscovery _failed(String id, String detail) => GcpGitHubDiscovery(
  resources: const [],
  checks: [
    ConnectionCheck(
      id: id,
      label: 'GitHub Apps',
      status: 'action_required',
      detail: detail,
    ),
  ],
);

final _secretName = RegExp(
  r'^projects/(?:[a-z][a-z0-9-]{4,28}[a-z0-9]|[1-9][0-9]{5,29})/secrets/[A-Za-z0-9_-]{1,255}$',
);
