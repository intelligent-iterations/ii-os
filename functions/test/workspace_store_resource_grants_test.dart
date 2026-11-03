import 'package:ii_os_functions/src/data_plane_connection.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:ii_os_functions/src/workspace_store.dart';
import 'package:test/test.dart';

void main() {
  test('workspace JSON carries its server-resolved GCP connection', () {
    const organizationId = '11111111-1111-4111-8111-111111111111';
    const workspaceId = '22222222-2222-4222-8222-222222222222';
    final promoted = promoteLegacyWorkspaceResources(
      current: const OrganizationResourceCatalog.empty(),
      organizationId: organizationId,
      sourceWorkspaceId: workspaceId,
      connection: _legacyConnection(workspaceId),
      installationId: 303,
      repositories: const {'acme/product'},
      githubPermissions: githubResourcePermissions,
    );
    final workspace = WorkspaceStore.materializeWorkspace(
      workspaceId: workspaceId,
      data: const {
        'organizationId': organizationId,
        'resourceGrantVersion': workspaceResourceGrantVersion,
        'resourceGrants': {
          'gcp': [
            {
              'resourceId': legacyGcpResourceId,
              'permissions': ['assets.read'],
              'primary': true,
            },
          ],
          'github': <Object?>[],
          'runners': <Object?>[],
        },
      },
      organization: promoted.toJson(),
      emulated: true,
    );

    final resolved =
        workspace.toJson()['resolvedConnection']! as Map<String, Object?>;

    expect(resolved['projectId'], 'legacy-project');
    expect(resolved['workspaceId'], workspaceId);
  });

  test(
    'production loader restores GitHub-exact grants for the promoted source',
    () {
      const organizationId = '11111111-1111-4111-8111-111111111111';
      const workspaceId = '22222222-2222-4222-8222-222222222222';
      final promoted = promoteLegacyWorkspaceResources(
        current: const OrganizationResourceCatalog.empty(),
        organizationId: organizationId,
        sourceWorkspaceId: workspaceId,
        connection: _legacyConnection(workspaceId),
        installationId: 303,
        repositories: const {'acme/product'},
        githubPermissions: githubResourcePermissions,
      );
      final organization = promoted.toJson();
      const workspace = {
        'organizationId': organizationId,
        'resourceGrantVersion': workspaceResourceGrantVersion,
        'resourceGrants': {
          'gcp': <Object?>[],
          'github': [
            {
              'resourceId': legacyGithubResourceId,
              'repositories': ['acme/product'],
              'permissions': [
                'actions:write',
                'contents:write',
                'pull_requests:write',
              ],
              'primary': true,
            },
          ],
          'runners': <Object?>[],
        },
        'projects': [
          {
            'id': 'PVT_workshop',
            'number': 4,
            'owner': 'acme',
            'title': 'Product',
          },
        ],
      };

      final loaded = WorkspaceStore.materializeWorkspace(
        workspaceId: workspaceId,
        data: workspace,
        organization: organization,
        emulated: true,
      );

      expect(loaded.allowsGitHubPermission('issues:write'), isTrue);
      expect(loaded.allowsGitHubPermission('administration:read'), isTrue);
      expect(loaded.allowsGitHubPermission('deployments:read'), isTrue);
      expect(loaded.allowsGitHubPermission('secrets:write'), isTrue);
      expect(
        loaded.allowsGitHubPermission('organization_projects:write'),
        isTrue,
      );
    },
  );
}

DataPlaneConnection _legacyConnection(
  String workspaceId,
) => DataPlaneConnection(
  workspaceId: workspaceId,
  projectId: 'legacy-project',
  projectNumber: '123456789012',
  databaseId: '(default)',
  region: 'us-central1',
  bucket: 'legacy-project-media',
  dataServiceAccount: 'broker@control-project.iam.gserviceaccount.com',
  uploadServiceAccount: 'upload@legacy-project.iam.gserviceaccount.com',
  workloadIdentityProvider:
      'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
  authProjectId: 'control-project',
  webOrigin: 'https://ii-os.example.com',
  githubAppId: '123456',
  githubAppSecret: 'projects/legacy-project/secrets/github-app',
  emulated: true,
);
