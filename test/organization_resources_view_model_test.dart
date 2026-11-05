import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/data_plane_connection.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/view_models/organization_resources_view_model.dart';

import 'resource_view_model_fixtures.dart';

void main() {
  test('validated organization GCP resource refreshes the catalog', () async {
    final fixture = resourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository();
    var refreshes = 0;
    final model = OrganizationResourcesViewModel(
      organization: fixture.organization,
      repository: repository,
      onSaved: () async => refreshes += 1,
    );

    expect(await model.addGcp(gcpDraft()), isTrue);

    expect(repository.gcp?.id, 'gcp_media');
    expect(refreshes, 1);
    expect(model.errorMessage, isNull);
  });

  test('failed validation is not reported as an added resource', () async {
    final fixture = resourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository()
      ..gcpValidation = const DataPlaneValidationModel(
        status: 'action_required',
        checks: [],
        validatedAt: null,
      );
    var refreshes = 0;
    final model = OrganizationResourcesViewModel(
      organization: fixture.organization,
      repository: repository,
      onSaved: () async => refreshes += 1,
    );

    expect(await model.addGcp(gcpDraft()), isFalse);

    expect(refreshes, 0);
    expect(model.errorMessage, contains('infrastructure checks'));
    expect(model.validation, same(repository.gcpValidation));
  });

  test('promotes the existing workspace setup and refreshes', () async {
    final fixture = resourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository();
    var refreshes = 0;
    final model = OrganizationResourcesViewModel(
      organization: fixture.organization,
      repository: repository,
      onSaved: () async => refreshes += 1,
      legacySourceWorkspaceId: 'workspace-existing',
    );

    expect(await model.promoteLegacySetup(), isTrue);

    expect(repository.promotedSourceWorkspaceId, 'workspace-existing');
    expect(refreshes, 1);
    expect(model.errorMessage, isNull);
  });

  test('an attached legacy setup can refresh its exact GitHub permissions', () {
    final fixture = resourceViewModelFixture();
    final legacyOrganization = OrganizationAccess(
      id: fixture.organization.id,
      name: fixture.organization.name,
      role: fixture.organization.role,
      capabilities: fixture.organization.capabilities,
      resources: OrganizationResourceCatalogModel(
        gcp: [
          OrganizationGcpResourceModel(
            id: 'gcp_legacy_primary',
            name: 'Existing GCP project',
            connection: fixture.organization.resources.gcp.single.connection,
            permissions: const {'assets.read'},
            active: true,
            legacySourceWorkspaceId: 'workspace-existing',
          ),
        ],
      ),
    );
    final model = OrganizationResourcesViewModel(
      organization: legacyOrganization,
      repository: FakeOrganizationResourceRepository(),
      onSaved: () async {},
      legacySourceWorkspaceId: 'workspace-existing',
    );

    expect(model.canPromoteLegacySetup, isTrue);
    expect(model.refreshingLegacySetup, isTrue);
  });

  test('syncs the existing organization Fleet report', () async {
    final fixture = resourceViewModelFixture();
    final repository = FakeOrganizationResourceRepository();
    var refreshes = 0;
    final model = OrganizationResourcesViewModel(
      organization: fixture.organization,
      repository: repository,
      onSaved: () async => refreshes += 1,
    );

    expect(await model.syncFleetRunnerPool(), isTrue);

    expect(repository.fleetSyncs, 1);
    expect(refreshes, 1);
  });

  group('your runners', () {
    test('are added as a customer pool under an unused id', () async {
      final fixture = resourceViewModelFixture();
      final repository = FakeOrganizationResourceRepository();
      var refreshes = 0;
      final model = OrganizationResourcesViewModel(
        organization: fixture.organization,
        repository: repository,
        onSaved: () async => refreshes += 1,
      );

      expect(await model.addCustomerRunner(_gpuRunners(name: 'GPU')), isTrue);

      // The fixture already holds a reported pool with id runner_gpu.
      expect(repository.runner?.id, 'runner_gpu_2');
      expect(repository.runner?.provider, 'customer');
      expect(repository.runner?.providerPoolId, 'gpu-runners');
      expect(repository.runner?.active, isTrue);
      expect(refreshes, 1);
      expect(model.runnerErrorMessage, isNull);
    });

    test('a second pool with the same name never replaces the first', () async {
      final fixture = resourceViewModelFixture();
      final repository = FakeOrganizationResourceRepository();
      // The organization snapshot is taken once; the refresh that follows a
      // save does not reach this view model, so it must remember its own ids.
      final model = OrganizationResourcesViewModel(
        organization: fixture.organization,
        repository: repository,
        onSaved: () async {},
      );

      await model.addCustomerRunner(_gpuRunners(name: 'Render'));
      await model.addCustomerRunner(_gpuRunners(name: 'Render'));

      expect(repository.savedRunners.map((draft) => draft.id), [
        'runner_render',
        'runner_render_2',
      ]);
    });

    test('editing keeps the pool id and can turn it off', () async {
      final fixture = resourceViewModelFixture();
      final repository = FakeOrganizationResourceRepository();
      final model = OrganizationResourcesViewModel(
        organization: fixture.organization,
        repository: repository,
        onSaved: () async {},
      );

      expect(
        await model.updateCustomerRunner(
          _customerPool,
          _gpuRunners(name: 'Renamed runners', active: false),
        ),
        isTrue,
      );

      expect(repository.runner?.id, 'runner_studio');
      expect(repository.runner?.name, 'Renamed runners');
      expect(repository.runner?.provider, 'customer');
      expect(repository.runner?.active, isFalse);
    });

    test('a pool from a capacity report is not edited by hand', () async {
      final fixture = resourceViewModelFixture();
      final repository = FakeOrganizationResourceRepository();
      final model = OrganizationResourcesViewModel(
        organization: fixture.organization,
        repository: repository,
        onSaved: () async {},
      );
      final reported = fixture.organization.resources.runners.single;

      expect(
        await model.updateCustomerRunner(reported, _gpuRunners()),
        isFalse,
      );

      expect(repository.runner, isNull);
      expect(model.runnerErrorMessage, contains('capacity report'));
    });

    test('a role without runner management is told why, not refused', () async {
      final fixture = resourceViewModelFixture();
      final repository = FakeOrganizationResourceRepository();
      final model = OrganizationResourcesViewModel(
        organization: OrganizationAccess(
          id: fixture.organization.id,
          name: fixture.organization.name,
          role: 'Organization Member',
          capabilities: const {'org.integrations.manage'},
          resources: fixture.organization.resources,
        ),
        repository: repository,
        onSaved: () async {},
      );

      expect(model.canManageRunners, isFalse);
      expect(model.runnerManageBlockedReason, contains('Organization Admin'));
      expect(await model.addCustomerRunner(_gpuRunners()), isFalse);
      expect(await model.syncFleetRunnerPool(), isFalse);
      expect(repository.runner, isNull);
      expect(repository.fleetSyncs, 0);
    });

    test('an organization admin has no blocked reason', () {
      final fixture = resourceViewModelFixture();
      final model = OrganizationResourcesViewModel(
        organization: fixture.organization,
        repository: FakeOrganizationResourceRepository(),
        onSaved: () async {},
      );

      expect(model.canManageRunners, isTrue);
      expect(model.runnerManageBlockedReason, isNull);
    });
  });

  group('runner failures read as a next step', () {
    final cases = <RunnerPoolFailureKind, String>{
      RunnerPoolFailureKind.notReported: 'Add your runners',
      RunnerPoolFailureKind.staleReport: 'out of date',
      RunnerPoolFailureKind.noReportedCapacity: 'online',
      RunnerPoolFailureKind.limitReached: 'Edit one of yours',
      RunnerPoolFailureKind.invalid: 'capabilities',
      RunnerPoolFailureKind.forbidden: 'Organization Admin',
      RunnerPoolFailureKind.unknown: 'Try again',
    };
    for (final entry in cases.entries) {
      test('a sync refused for ${entry.key.name}', () async {
        final fixture = resourceViewModelFixture();
        final repository = FakeOrganizationResourceRepository()
          ..failure = RunnerPoolFailure(entry.key);
        var refreshes = 0;
        final model = OrganizationResourcesViewModel(
          organization: fixture.organization,
          repository: repository,
          onSaved: () async => refreshes += 1,
        );

        expect(await model.syncFleetRunnerPool(), isFalse);

        expect(model.runnerErrorMessage, contains(entry.value));
        // A deployment without a runner control plane has never heard of
        // ours; the sentence names the person's runners instead.
        expect(model.runnerErrorMessage, isNot(contains('Fleet')));
        expect(refreshes, 0);
      });
    }

    test('an unexpected save failure is not interpolated', () async {
      final fixture = resourceViewModelFixture();
      final repository = FakeOrganizationResourceRepository()
        ..failure = StateError('socket closed at 10.0.0.1');
      final model = OrganizationResourcesViewModel(
        organization: fixture.organization,
        repository: repository,
        onSaved: () async {},
      );

      expect(await model.addCustomerRunner(_gpuRunners()), isFalse);

      expect(model.runnerErrorMessage, contains('Try again'));
      expect(model.runnerErrorMessage, isNot(contains('socket')));
    });
  });
}

CustomerRunnerPoolInput _gpuRunners({
  String name = 'GPU runners',
  bool active = true,
}) => CustomerRunnerPoolInput(
  name: name,
  runnerGroup: 'gpu-runners',
  capabilities: const {'runtime-docker', 'gpu.nvidia'},
  maxCpu: 16,
  maxRamMiB: 65536,
  maxConcurrent: 2,
  active: active,
);

const _customerPool = OrganizationRunnerPoolModel(
  id: 'runner_studio',
  name: 'Studio runners',
  provider: 'customer',
  capabilities: {'runtime-docker'},
  maxCpu: 8,
  maxRamMiB: 16384,
  maxConcurrent: 1,
  active: true,
  providerPoolId: 'studio',
);
