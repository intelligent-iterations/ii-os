import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/view_models/workspace_resources_view_model.dart';

import 'resource_view_model_fixtures.dart';

void main() {
  test('saves exact repository, permission, and runner subsets', () async {
    final fixture = resourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository();
    var refreshes = 0;
    final model = WorkspaceResourcesViewModel(
      organization: fixture.organization,
      workspace: fixture.workspace,
      canManage: true,
      repository: repository,
      onSaved: () async => refreshes += 1,
    );

    expect(model.runnerMaxCpu, 4);
    expect(model.runnerMaxRamMiB, 16384);
    expect(model.runnerMaxConcurrent, 1);

    model.setRunnerMaxCpu('8');
    model.setRunnerMaxRamMiB('32768');
    expect(await model.save(), isTrue);

    final grants = repository.grants!;
    expect(grants.gcp.single.permissions, {'assets.read'});
    expect(grants.github.single.repositories, {'acme/product'});
    expect(grants.github.single.permissions, {'contents:write'});
    expect(grants.runners.single.capabilities, {'comfyui'});
    expect(grants.runners.single.maxCpu, 8);
    expect(grants.runners.single.maxRamMiB, 32768);
    expect(grants.runners.single.maxConcurrent, 1);
    expect(refreshes, 1);
  });

  test('refuses runner limits outside the organization envelope', () async {
    final fixture = resourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository();
    final model = WorkspaceResourcesViewModel(
      organization: fixture.organization,
      workspace: fixture.workspace,
      canManage: true,
      repository: repository,
      onSaved: () async {},
    );

    model.setRunnerMaxCpu('17');

    expect(model.canSave, isFalse);
    expect(await model.save(), isFalse);
    expect(repository.grants, isNull);
  });

  test('new GitHub assignment starts with no repository or permission', () {
    final fixture = resourceViewModelFixture();
    final existing = fixture.workspace;
    final workspace = WorkspaceModel(
      id: existing.id,
      name: existing.name,
      organizationId: existing.organizationId,
      environment: existing.environment,
      githubInstallationId: existing.githubInstallationId,
      repositories: existing.repositories,
      projects: existing.projects,
      workflows: existing.workflows,
      artifactStorage: existing.artifactStorage,
      resourceGrantVersion: 1,
      resourceGrants: const WorkspaceResourceGrantsModel(),
    );
    final model = WorkspaceResourcesViewModel(
      organization: fixture.organization,
      workspace: workspace,
      canManage: true,
      repository: FakeOrganizationResourceRepository(),
      onSaved: () async {},
    );

    model.selectGitHub('github_product');

    expect(model.repositories, isEmpty);
    expect(model.githubPermissions, isEmpty);
  });

  test('preserves several grants and can promote another primary', () async {
    final fixture = multiResourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository();
    final model = WorkspaceResourcesViewModel(
      organization: fixture.organization,
      workspace: fixture.workspace,
      canManage: true,
      repository: repository,
      onSaved: () async {},
    );

    expect(model.assignedGcpIds, {'gcp_media', 'gcp_archive'});
    expect(model.assignedGitHubIds, {'github_product', 'github_ops'});
    expect(model.assignedRunnerIds, {'runner_gpu', 'runner_cpu'});

    model.selectGcp('gcp_archive');
    model.selectGitHub('github_ops');
    model.selectRunner('runner_cpu');

    expect(await model.save(), isTrue);
    final grants = repository.grants!;
    expect(grants.gcp, hasLength(2));
    expect(grants.github, hasLength(2));
    expect(grants.runners, hasLength(2));
    expect(
      grants.gcp.singleWhere((grant) => grant.primary).resourceId,
      'gcp_archive',
    );
    expect(
      grants.github.singleWhere((grant) => grant.primary).resourceId,
      'github_ops',
    );
    expect(
      grants.runners.singleWhere((grant) => grant.primary).resourceId,
      'runner_cpu',
    );
    expect(
      grants.github
          .singleWhere((grant) => grant.resourceId == 'github_product')
          .repositories,
      {'acme/product'},
    );
    expect(
      grants.runners
          .singleWhere((grant) => grant.resourceId == 'runner_gpu')
          .maxCpu,
      4,
    );
  });

  test(
    'can revoke every inherited resource with an explicit empty grant',
    () async {
      final fixture = multiResourceViewModelFixture();
      final repository = FakeOrganizationResourceRepository();
      final model = WorkspaceResourcesViewModel(
        organization: fixture.organization,
        workspace: fixture.workspace,
        canManage: true,
        repository: repository,
        onSaved: () async {},
      );

      model.selectGcp(null);
      model.selectGitHub(null);
      model.selectRunner(null);

      expect(model.canSave, isTrue);
      expect(await model.save(), isTrue);
      expect(repository.grants!.gcp, isEmpty);
      expect(repository.grants!.github, isEmpty);
      expect(repository.grants!.runners, isEmpty);
    },
  );

  test('viewer cannot mutate workspace grants', () async {
    final fixture = resourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository();
    final model = WorkspaceResourcesViewModel(
      organization: fixture.organization,
      workspace: fixture.workspace,
      canManage: false,
      repository: repository,
      onSaved: () async {},
    );

    expect(model.canSave, isFalse);
    expect(await model.save(), isFalse);
    expect(repository.grants, isNull);
  });
}
