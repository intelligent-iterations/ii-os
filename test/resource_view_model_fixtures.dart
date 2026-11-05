import 'package:ii_os/models/data_plane_connection.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/organization_repository.dart';

final class FakeOrganizationResourceRepository
    implements OrganizationResourceRepository {
  DataPlaneValidationModel gcpValidation = DataPlaneValidationModel(
    status: 'ready',
    checks: const [
      DataPlaneCheckModel(
        id: 'project',
        label: 'Project',
        status: 'passed',
        detail: 'Ready',
      ),
    ],
    validatedAt: DateTime.utc(2026, 8, 22),
  );
  Object? failure;
  OrganizationGcpResourceDraft? gcp;
  OrganizationRunnerPoolDraft? runner;
  final List<OrganizationRunnerPoolDraft> savedRunners = [];
  WorkspaceResourceGrantsModel? grants;
  String? promotedSourceWorkspaceId;
  int fleetSyncs = 0;

  void _failIfNeeded() {
    final value = failure;
    if (value != null) throw value;
  }

  @override
  Future<DataPlaneValidationModel> saveGcpResource({
    required String organizationId,
    required OrganizationGcpResourceDraft resource,
  }) async {
    _failIfNeeded();
    gcp = resource;
    return gcpValidation;
  }

  @override
  Future<void> saveRunnerPool({
    required String organizationId,
    required OrganizationRunnerPoolDraft resource,
  }) async {
    _failIfNeeded();
    runner = resource;
    savedRunners.add(resource);
  }

  @override
  Future<void> saveWorkspaceResourceGrants({
    required String workspaceId,
    required WorkspaceResourceGrantsModel grants,
  }) async {
    _failIfNeeded();
    this.grants = grants;
  }

  @override
  Future<void> promoteLegacyWorkspace({
    required String organizationId,
    required String sourceWorkspaceId,
  }) async {
    _failIfNeeded();
    promotedSourceWorkspaceId = sourceWorkspaceId;
  }

  @override
  Future<void> syncFleetRunnerPool({required String organizationId}) async {
    _failIfNeeded();
    fleetSyncs += 1;
  }
}

({OrganizationAccess organization, WorkspaceModel workspace})
resourceViewModelFixture() {
  const connection = DataPlaneConnectionModel(
    organizationId: 'org-1',
    projectId: 'media-project',
    projectNumber: '123456789012',
    databaseId: '(default)',
    region: 'us-central1',
    bucket: 'media-project-assets',
    dataServiceAccount: 'broker@platform.iam.gserviceaccount.com',
    uploadServiceAccount: 'upload@media-project.iam.gserviceaccount.com',
    workloadIdentityProvider: 'provider',
    authProjectId: 'platform',
    webOrigin: 'https://ii-os.example.com',
    gcpOnly: true,
  );
  const resources = OrganizationResourceCatalogModel(
    gcp: [
      OrganizationGcpResourceModel(
        id: 'gcp_media',
        name: 'Media project',
        connection: connection,
        permissions: {'assets.read', 'assets.write', 'workflows.upload'},
        active: true,
      ),
    ],
    github: [
      OrganizationGitHubResourceModel(
        id: 'github_product',
        name: 'Product App',
        secretGcpResourceId: 'gcp_media',
        appId: '123',
        privateKeySecret:
            'projects/media-project/secrets/github-app/versions/latest',
        installationId: 456,
        repositories: {'acme/product', 'acme/mobile'},
        permissions: {'contents:write', 'pull_requests:write'},
        active: true,
      ),
    ],
    runners: [
      OrganizationRunnerPoolModel(
        id: 'runner_gpu',
        name: 'GPU pool',
        provider: 'fleet',
        capabilities: {'comfyui', 'gpu.nvidia'},
        maxCpu: 16,
        maxRamMiB: 65536,
        maxConcurrent: 2,
        active: true,
        providerPoolId: 'gpu-workers',
      ),
    ],
  );
  const organization = OrganizationAccess(
    id: 'org-1',
    name: 'Acme',
    role: 'Organization Admin',
    capabilities: {'org.integrations.manage', 'org.runners.manage'},
    resources: resources,
  );
  const workspace = WorkspaceModel(
    id: 'workspace-1',
    name: 'Product',
    organizationId: 'org-1',
    environment: 'dev',
    githubInstallationId: null,
    repositories: [],
    projects: [],
    workflows: [],
    artifactStorage: null,
    resourceGrantVersion: 1,
    resourceGrants: WorkspaceResourceGrantsModel(
      gcp: [
        WorkspaceGcpGrantModel(
          resourceId: 'gcp_media',
          permissions: {'assets.read'},
          primary: true,
        ),
      ],
      github: [
        WorkspaceGitHubGrantModel(
          resourceId: 'github_product',
          repositories: {'acme/product'},
          permissions: {'contents:write'},
          primary: true,
        ),
      ],
      runners: [
        WorkspaceRunnerGrantModel(
          resourceId: 'runner_gpu',
          capabilities: {'comfyui'},
          maxCpu: 4,
          maxRamMiB: 16384,
          maxConcurrent: 1,
          primary: true,
        ),
      ],
    ),
  );
  return (organization: organization, workspace: workspace);
}

({OrganizationAccess organization, WorkspaceModel workspace})
multiResourceViewModelFixture() {
  final base = resourceViewModelFixture();
  final resources = OrganizationResourceCatalogModel(
    gcp: [
      ...base.organization.resources.gcp,
      OrganizationGcpResourceModel(
        id: 'gcp_archive',
        name: 'Archive project',
        connection: base.organization.resources.gcp.single.connection,
        permissions: const {'assets.read'},
        active: true,
      ),
    ],
    github: [
      ...base.organization.resources.github,
      const OrganizationGitHubResourceModel(
        id: 'github_ops',
        name: 'Operations App',
        secretGcpResourceId: 'gcp_media',
        appId: '789',
        privateKeySecret:
            'projects/media-project/secrets/github-ops/versions/latest',
        installationId: 987,
        repositories: {'acme/operations'},
        permissions: {'contents:read', 'issues:write'},
        active: true,
      ),
    ],
    runners: [
      ...base.organization.resources.runners,
      const OrganizationRunnerPoolModel(
        id: 'runner_cpu',
        name: 'CPU pool',
        provider: 'fleet',
        capabilities: {'build.linux'},
        maxCpu: 8,
        maxRamMiB: 16384,
        maxConcurrent: 4,
        active: true,
        providerPoolId: 'cpu-workers',
      ),
    ],
  );
  final organization = OrganizationAccess(
    id: base.organization.id,
    name: base.organization.name,
    role: base.organization.role,
    capabilities: base.organization.capabilities,
    resources: resources,
  );
  final workspace = WorkspaceModel(
    id: base.workspace.id,
    name: base.workspace.name,
    organizationId: base.workspace.organizationId,
    environment: base.workspace.environment,
    githubInstallationId: base.workspace.githubInstallationId,
    repositories: base.workspace.repositories,
    projects: base.workspace.projects,
    workflows: base.workspace.workflows,
    artifactStorage: base.workspace.artifactStorage,
    resourceGrantVersion: base.workspace.resourceGrantVersion,
    resourceGrants: WorkspaceResourceGrantsModel(
      gcp: [
        ...base.workspace.resourceGrants.gcp,
        const WorkspaceGcpGrantModel(
          resourceId: 'gcp_archive',
          permissions: {'assets.read'},
          primary: false,
        ),
      ],
      github: [
        ...base.workspace.resourceGrants.github,
        const WorkspaceGitHubGrantModel(
          resourceId: 'github_ops',
          repositories: {'acme/operations'},
          permissions: {'contents:read'},
          primary: false,
        ),
      ],
      runners: [
        ...base.workspace.resourceGrants.runners,
        const WorkspaceRunnerGrantModel(
          resourceId: 'runner_cpu',
          capabilities: {'build.linux'},
          maxCpu: 4,
          maxRamMiB: 8192,
          maxConcurrent: 2,
          primary: false,
        ),
      ],
    ),
  );
  return (organization: organization, workspace: workspace);
}

OrganizationGcpResourceDraft gcpDraft() {
  return OrganizationGcpResourceDraft(
    id: 'gcp_media',
    name: 'Media project',
    serviceAccountJson:
        '{"type":"service_account","project_id":"media-project"}',
    permissions: const {'assets.read'},
  );
}
