import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/github_client.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:test/test.dart';

void main() {
  test('Project reads name a missing App permission before GraphQL', () async {
    final client = GitHubClient(appId: '123', privateKey: 'unused');

    await expectLater(
      client.getProject(
        projectWorkspace(
          resourcePermissions: const {
            'actions:write',
            'contents:write',
            'pull_requests:write',
          },
          workspacePermissions: const {
            'actions:write',
            'contents:write',
            'pull_requests:write',
          },
        ),
        'PVT_workshop',
      ),
      throwsA(
        isA<ApiError>()
            .having(
              (error) => error.code,
              'code',
              'github_app_projects_permission_required',
            )
            .having((error) => error.status, 'status', 409),
      ),
    );
  });

  test('Project reads name a missing workspace permission', () async {
    final client = GitHubClient(appId: '123', privateKey: 'unused');

    await expectLater(
      client.getProject(
        projectWorkspace(
          resourcePermissions: const {'organization_projects:write'},
          workspacePermissions: const {'contents:read'},
        ),
        'PVT_workshop',
      ),
      throwsA(
        isA<ApiError>()
            .having(
              (error) => error.code,
              'code',
              'workspace_github_projects_permission_required',
            )
            .having((error) => error.status, 'status', 403),
      ),
    );
  });

  test('Workshop reads name a missing Issues permission', () async {
    final client = GitHubClient(appId: '123', privateKey: 'unused');

    await expectLater(
      client.getProject(
        projectWorkspace(
          resourcePermissions: const {'organization_projects:read'},
          workspacePermissions: const {'organization_projects:read'},
        ),
        'PVT_workshop',
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'github_app_issues_permission_required',
        ),
      ),
    );
  });
}

Workspace projectWorkspace({
  required Set<String> resourcePermissions,
  required Set<String> workspacePermissions,
  Set<String> repositories = const {'acme/product'},
}) {
  const resourceId = 'github_product';
  return Workspace(
    id: 'workspace-1',
    name: 'Product',
    organizationId: 'organization-1',
    environment: 'dev',
    githubInstallationId: 456,
    repositories: repositories.toList()..sort(),
    projects: const [
      GitHubProjectConfig(
        id: 'PVT_workshop',
        number: 7,
        owner: 'acme',
        title: 'Workshop',
      ),
    ],
    workflows: const [],
    artifactStorage: null,
    organizationResources: OrganizationResourceCatalog(
      gcpResources: const [],
      githubResources: [
        OrganizationGitHubResource(
          id: resourceId,
          name: 'Product App',
          secretGcpResourceId: 'gcp_product',
          appId: '123',
          privateKeySecret: 'projects/product/secrets/github-app',
          installationId: 456,
          repositories: repositories,
          permissionEnvelope: resourcePermissions,
        ),
      ],
      runnerPools: const [],
    ),
    resourceGrants: WorkspaceResourceGrants(
      gcp: const [],
      github: [
        WorkspaceGitHubGrant(
          resourceId: resourceId,
          repositories: repositories,
          permissions: workspacePermissions,
          primary: true,
        ),
      ],
      runners: const [],
    ),
    resourceGrantsExplicit: true,
  );
}
