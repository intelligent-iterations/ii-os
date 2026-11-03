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
}
