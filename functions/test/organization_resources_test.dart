import 'package:ii_os_functions/src/data_plane_connection.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/github_app_transport.dart';
import 'package:ii_os_functions/src/organization_resources.dart';
import 'package:ii_os_functions/src/workspace_resource_grants.dart';
import 'package:test/test.dart';

void main() {
  group('organization resource catalog', () {
    test('holds several GCP projects, GitHub Apps, and runner pools', () {
      final catalog = OrganizationResourceCatalog(
        gcpResources: [
          gcp('gcp_media', 'media-project'),
          gcp('gcp_analytics', 'analytics-project'),
        ],
        githubResources: [
          github(
            'github_product',
            gcpResourceId: 'gcp_media',
            installationId: 101,
            repositories: {'acme/product', 'acme/mobile'},
          ),
          github(
            'github_data',
            gcpResourceId: 'gcp_analytics',
            installationId: 202,
            repositories: {'acme/data'},
            secretProject: 'analytics-project',
          ),
        ],
        runnerPools: const [
          OrganizationRunnerPool(
            id: 'runner_general',
            name: 'General',
            provider: 'fleet',
            capabilities: {'docker'},
            maxCpu: 8,
            maxRamMiB: 16384,
            maxConcurrent: 4,
            providerPoolId: 'shared-coders',
          ),
          OrganizationRunnerPool(
            id: 'runner_gpu',
            name: 'GPU',
            provider: 'fleet',
            capabilities: {'comfyui', 'gpu.nvidia'},
            maxCpu: 16,
            maxRamMiB: 65536,
            maxConcurrent: 2,
            providerPoolId: 'gpu-workers',
          ),
        ],
      );

      expect(catalog.gcpResources, hasLength(2));
      expect(catalog.githubResources, hasLength(2));
      expect(catalog.runnerPools, hasLength(2));
      expect(catalog.github('github_data')?.installationId, 202);
      expect(
        (catalog.toJson()['runnerPools'] as List<Object?>)
            .whereType<Map<String, Object?>>()
            .first['providerPoolId'],
        'shared-coders',
      );
      expect(catalog.validate(), isEmpty);
    });

    test('derives deterministic resources from the singular connection', () {
      final catalog = OrganizationResourceCatalog.fromOrganizationData(
        '11111111-1111-4111-8111-111111111111',
        {
          'connection': gcp(
            legacyGcpResourceId,
            'legacy-project',
          ).connection.toJson(),
          'githubInstallationId': 303,
          'repositories': ['acme/legacy'],
        },
        emulated: true,
      );

      expect(catalog.gcp(legacyGcpResourceId), isNotNull);
      expect(catalog.github(legacyGithubResourceId)?.installationId, 303);
      expect(catalog.github(legacyGithubResourceId)?.repositories, {
        'acme/legacy',
      });
    });

    test('promotes a working legacy workspace without copying credentials', () {
      const sourceWorkspaceId = '22222222-2222-4222-8222-222222222222';
      final connection = legacyWorkspaceConnection(sourceWorkspaceId);

      final catalog = promoteLegacyWorkspaceResources(
        current: const OrganizationResourceCatalog.empty(),
        organizationId: '11111111-1111-4111-8111-111111111111',
        sourceWorkspaceId: sourceWorkspaceId,
        connection: connection,
        installationId: 303,
        repositories: const {'acme/product'},
        githubPermissions: githubResourcePermissions,
      );
      final restoredCatalog = underScopedLegacyCatalog(catalog);
      expect(
        restoredCatalog.github(legacyGithubResourceId)?.permissionEnvelope,
        containsAll(legacyGitHubWorkshopPermissions),
      );

      final gcpResource = catalog.gcp(legacyGcpResourceId)!;
      expect(gcpResource.connection, same(connection));
      expect(gcpResource.legacySourceWorkspaceId, sourceWorkspaceId);
      expect(catalog.github(legacyGithubResourceId)?.installationId, 303);
      expect(
        catalog.github(legacyGithubResourceId)?.permissionEnvelope,
        githubResourcePermissions,
      );
      expect(
        catalog.validateForOrganization('11111111-1111-4111-8111-111111111111'),
        isEmpty,
      );
    });

    test(
      'restores the pre-migration App scope only for its source workspace',
      () {
        const sourceWorkspaceId = '22222222-2222-4222-8222-222222222222';
        final catalog = promoteLegacyWorkspaceResources(
          current: const OrganizationResourceCatalog.empty(),
          organizationId: '11111111-1111-4111-8111-111111111111',
          sourceWorkspaceId: sourceWorkspaceId,
          connection: legacyWorkspaceConnection(sourceWorkspaceId),
          installationId: 303,
          repositories: const {'acme/product'},
          githubPermissions: githubResourcePermissions,
        );
        final restoredCatalog = catalog;
        const storedGrant = {
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
              'id': 'PVT_kwDO',
              'number': 4,
              'owner': 'acme',
              'title': 'Product',
            },
          ],
        };

        final source = Workspace.fromData(
          sourceWorkspaceId,
          storedGrant,
          emulated: true,
          organizationResources: restoredCatalog,
        );
        final sibling = Workspace.fromData(
          '33333333-3333-4333-8333-333333333333',
          storedGrant,
          emulated: true,
          organizationResources: restoredCatalog,
        );

        expect(source.allowsGitHubPermission('issues:write'), isTrue);
        expect(source.allowsGitHubPermission('administration:read'), isTrue);
        expect(source.allowsGitHubPermission('deployments:read'), isTrue);
        expect(source.allowsGitHubPermission('secrets:write'), isTrue);
        expect(
          source.allowsGitHubPermission('organization_projects:write'),
          isTrue,
        );
        expect(githubInstallationAccessRequestBody(source), {
          'repositories': ['product'],
          'permissions': {
            'actions': 'write',
            'administration': 'read',
            'contents': 'write',
            'deployments': 'read',
            'issues': 'write',
            'organization_projects': 'write',
            'pull_requests': 'write',
            'secrets': 'write',
          },
        });
        expect(sibling.allowsGitHubPermission('issues:write'), isFalse);
        expect(sibling.allowsGitHubPermission('administration:read'), isFalse);
        expect(sibling.allowsGitHubPermission('secrets:write'), isFalse);
        expect(
          sibling.allowsGitHubPermission('organization_projects:write'),
          isFalse,
        );
      },
    );

    test('rejects a GitHub resource outside its Secret Manager project', () {
      final catalog = OrganizationResourceCatalog(
        gcpResources: [gcp('gcp_media', 'media-project')],
        githubResources: [
          github(
            'github_product',
            gcpResourceId: 'gcp_media',
            installationId: 101,
            repositories: {'acme/product'},
            secretProject: 'different-project',
          ),
        ],
        runnerPools: const [],
      );

      expect(catalog.validate(), contains('github_secret_project_mismatch'));
    });
  });

  group('workspace resource grants', () {
    late OrganizationResourceCatalog catalog;

    setUp(() {
      catalog = OrganizationResourceCatalog(
        gcpResources: [gcp('gcp_media', 'media-project')],
        githubResources: [
          github(
            'github_product',
            gcpResourceId: 'gcp_media',
            installationId: 101,
            repositories: {'acme/product', 'acme/mobile'},
          ),
        ],
        runnerPools: const [
          OrganizationRunnerPool(
            id: 'runner_gpu',
            name: 'GPU',
            provider: 'fleet',
            capabilities: {'comfyui', 'gpu.nvidia'},
            maxCpu: 16,
            maxRamMiB: 65536,
            maxConcurrent: 2,
            providerPoolId: 'gpu-workers',
          ),
        ],
      );
    });

    test('accepts only narrower workspace grants', () {
      const grants = WorkspaceResourceGrants(
        gcp: [
          WorkspaceGcpGrant(
            resourceId: 'gcp_media',
            permissions: {'assets.read', 'assets.write'},
            primary: true,
          ),
        ],
        github: [
          WorkspaceGitHubGrant(
            resourceId: 'github_product',
            repositories: {'acme/product'},
            permissions: {'contents:write'},
            primary: true,
          ),
        ],
        runners: [
          WorkspaceRunnerGrant(
            resourceId: 'runner_gpu',
            capabilities: {'comfyui'},
            maxCpu: 8,
            maxRamMiB: 32768,
            maxConcurrent: 1,
            primary: true,
          ),
        ],
      );

      expect(grants.validateAgainst(catalog), isEmpty);
      expect(grants.allowsRepository(catalog, 'acme/product'), isTrue);
      expect(grants.allowsRepository(catalog, 'acme/mobile'), isFalse);
      expect(grants.primaryGitHub(catalog)?.installationId, 101);
    });

    test('refuses repository, permission, and capacity widening', () {
      const grants = WorkspaceResourceGrants(
        gcp: [],
        github: [
          WorkspaceGitHubGrant(
            resourceId: 'github_product',
            repositories: {'acme/not-in-the-organization'},
            permissions: {'administration:write'},
            primary: true,
          ),
        ],
        runners: [
          WorkspaceRunnerGrant(
            resourceId: 'runner_gpu',
            capabilities: {'gpu.nvidia', 'unbounded'},
            maxCpu: 64,
            maxRamMiB: 131072,
            maxConcurrent: 8,
            primary: true,
          ),
        ],
      );

      expect(
        grants.validateAgainst(catalog),
        containsAll(<String>{
          'github_repository_outside_organization',
          'github_permission_outside_organization',
          'runner_capability_outside_organization',
          'runner_capacity_outside_organization',
        }),
      );
    });

    test('requires one primary resource and nonempty runner capabilities', () {
      const grants = WorkspaceResourceGrants(
        gcp: [
          WorkspaceGcpGrant(
            resourceId: 'gcp_media',
            permissions: {'assets.read'},
            primary: false,
          ),
        ],
        github: [],
        runners: [
          WorkspaceRunnerGrant(
            resourceId: 'runner_gpu',
            capabilities: {},
            maxCpu: 1,
            maxRamMiB: 1024,
            maxConcurrent: 1,
            primary: true,
          ),
        ],
      );

      expect(
        grants.validateAgainst(catalog),
        containsAll({
          'missing_primary_gcp',
          'runner_capability_outside_organization',
        }),
      );
    });

    test('derives a legacy workspace grant without copying credentials', () {
      final grants = WorkspaceResourceGrants.fromWorkspaceData({
        'repositories': ['acme/product'],
      }, catalog);

      expect(grants.primaryGcp(catalog)?.id, 'gcp_media');
      expect(grants.primaryGitHub(catalog)?.id, 'github_product');
      expect(grants.github.single.repositories, {'acme/product'});
    });
  });
}

OrganizationGcpResource gcp(String id, String projectId) {
  return OrganizationGcpResource(
    id: id,
    name: id,
    connection: DataPlaneConnection(
      workspaceId: '',
      organizationId: '11111111-1111-4111-8111-111111111111',
      projectId: projectId,
      projectNumber: '123456789012',
      databaseId: '(default)',
      region: 'us-central1',
      bucket: '$projectId-media',
      dataServiceAccount: 'broker@$projectId.iam.gserviceaccount.com',
      uploadServiceAccount: 'upload@$projectId.iam.gserviceaccount.com',
      workloadIdentityProvider:
          'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
      authProjectId: 'control-project',
      webOrigin: 'https://ii-os.example.com',
      githubAppId: '123456',
      githubAppSecret: 'projects/$projectId/secrets/github-app',
      emulated: true,
    ),
    permissionEnvelope: const {
      'assets.read',
      'assets.write',
      'workflows.upload',
    },
  );
}

OrganizationGitHubResource github(
  String id, {
  required String gcpResourceId,
  required int installationId,
  required Set<String> repositories,
  String secretProject = 'media-project',
}) {
  return OrganizationGitHubResource(
    id: id,
    name: id,
    secretGcpResourceId: gcpResourceId,
    appId: '123456',
    privateKeySecret: 'projects/$secretProject/secrets/$id',
    installationId: installationId,
    repositories: repositories,
    permissionEnvelope: const {
      'actions:write',
      'contents:write',
      'pull_requests:write',
    },
  );
}

DataPlaneConnection legacyWorkspaceConnection(String workspaceId) {
  return DataPlaneConnection(
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
}

OrganizationResourceCatalog underScopedLegacyCatalog(
  OrganizationResourceCatalog catalog,
) {
  final storedCatalog = catalog.toJson();
  final storedGitHub =
      (storedCatalog['githubResources']! as List<Object?>).single
          as Map<String, Object?>;
  storedGitHub['permissionEnvelope'] = const [
    'actions:write',
    'contents:write',
    'pull_requests:write',
  ];
  return OrganizationResourceCatalog.fromOrganizationData(
    '11111111-1111-4111-8111-111111111111',
    storedCatalog,
    emulated: true,
  );
}
