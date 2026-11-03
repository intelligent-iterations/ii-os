import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/data_plane_connection.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/github_app_transport.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:test/test.dart';

void main() {
  test('installation token request is narrowed to the workspace grant', () {
    final workspace = scopedWorkspace(
      id: 'workspace-a',
      repository: 'acme/product',
    );

    expect(githubInstallationAccessRequestBody(workspace), {
      'repositories': ['product'],
      'permissions': {
        'actions': 'read',
        'contents': 'write',
        'deployments': 'read',
        'pull_requests': 'write',
      },
    });
  });

  test('repository REST scope excludes an unrelated stale grant', () {
    final workspace = scopedWorkspace(
      id: 'workspace-a',
      repository: 'acme/product',
      repositories: {'acme/product', 'acme/renamed-framework'},
    );

    expect(
      githubInstallationAccessRequestBody(
        workspace,
        repository: githubRepositoryFromRestPath(
          '/repos/acme/product/actions/workflows/deliver.yml/dispatches',
        ),
      ),
      {
        'repositories': ['product'],
        'permissions': {
          'actions': 'read',
          'contents': 'write',
          'deployments': 'read',
          'pull_requests': 'write',
        },
      },
    );
  });

  test('token cache identity includes repositories and permissions', () {
    final product = scopedWorkspace(
      id: 'workspace-a',
      repository: 'acme/product',
    );
    final mobile = scopedWorkspace(
      id: 'workspace-b',
      repository: 'acme/mobile',
    );

    expect(
      githubInstallationAccessCacheKey(product),
      isNot(githubInstallationAccessCacheKey(mobile)),
    );
  });

  test('explicit workspace cannot mint an unscoped installation token', () {
    final scoped = scopedWorkspace(
      id: 'workspace-empty',
      repository: 'acme/product',
    );
    final workspace = Workspace(
      id: scoped.id,
      name: scoped.name,
      organizationId: scoped.organizationId,
      environment: scoped.environment,
      githubInstallationId: scoped.githubInstallationId,
      repositories: const [],
      projects: const [],
      workflows: const [],
      artifactStorage: null,
      organizationResources: scoped.organizationResources,
      resourceGrants: const WorkspaceResourceGrants.empty(),
      resourceGrantsExplicit: true,
    );

    expect(
      () => githubInstallationAccessRequestBody(workspace),
      throwsA(isA<Exception>()),
    );
  });

  test('legacy workspace keeps its unscoped migration token', () {
    final workspace = scopedWorkspace(
      id: 'workspace-legacy',
      repository: 'acme/product',
      explicit: false,
    );

    expect(githubInstallationAccessRequestBody(workspace), isNull);
    expect(workspace.toJson(), isNot(contains('resourceGrantVersion')));
    expect(
      (workspace.toJson()['resourceGrants']! as Map)['github'],
      isNotEmpty,
    );
  });

  test('secret writer rejects a repository outside the workspace grant', () {
    final workspace = scopedWorkspace(
      id: 'workspace-secret',
      repository: 'acme/product',
    );
    final transport = GitHubAppTransport(appId: '1', privateKey: 'unused');

    expectLater(
      transport.issueRepositorySecretWriterToken(
        workspace,
        repository: 'acme/mobile',
        repositoryId: 202,
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'workspace_github_permission_required',
        ),
      ),
    );
  });
}

Workspace scopedWorkspace({
  required String id,
  required String repository,
  Set<String>? repositories,
  bool explicit = true,
}) {
  final grantedRepositories = repositories ?? {repository};
  final connection = DataPlaneConnection(
    workspaceId: '',
    organizationId: '11111111-1111-4111-8111-111111111111',
    projectId: 'media-project',
    projectNumber: '123456789012',
    databaseId: '(default)',
    region: 'us-central1',
    bucket: 'media-project-media',
    dataServiceAccount: 'broker@media-project.iam.gserviceaccount.com',
    uploadServiceAccount: 'upload@media-project.iam.gserviceaccount.com',
    workloadIdentityProvider:
        'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
    authProjectId: 'control-project',
    webOrigin: 'https://ii-os.example.com',
    githubAppId: '123456',
    githubAppSecret: 'projects/media-project/secrets/github-app',
    emulated: true,
  );
  final catalog = OrganizationResourceCatalog(
    gcpResources: [
      OrganizationGcpResource(
        id: 'gcp_media',
        name: 'Media',
        connection: connection,
        permissionEnvelope: gcpResourcePermissions,
      ),
    ],
    githubResources: [
      OrganizationGitHubResource(
        id: 'github_product',
        name: 'Product App',
        secretGcpResourceId: 'gcp_media',
        appId: '123456',
        privateKeySecret: 'projects/media-project/secrets/github-app',
        installationId: 101,
        repositories: {'acme/product', 'acme/mobile'},
        permissionEnvelope: githubResourcePermissions,
      ),
    ],
    runnerPools: const [],
  );
  final grants = WorkspaceResourceGrants(
    gcp: const [],
    github: [
      WorkspaceGitHubGrant(
        resourceId: 'github_product',
        repositories: grantedRepositories,
        permissions: const {
          'actions:read',
          'contents:write',
          'deployments:read',
          'pull_requests:write',
        },
        primary: true,
      ),
    ],
    runners: const [],
  );
  return Workspace(
    id: id,
    name: id,
    organizationId: connection.organizationId,
    environment: 'dev',
    githubInstallationId: 101,
    repositories: grantedRepositories.toList()..sort(),
    projects: const [],
    workflows: const [],
    artifactStorage: null,
    organizationResources: catalog,
    resourceGrants: grants,
    resourceGrantsExplicit: explicit,
  );
}
