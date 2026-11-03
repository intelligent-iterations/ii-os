import 'package:stacked/stacked.dart';

import '../models/data_plane_connection.dart';
import '../models/models.dart';
import '../repositories/organization_repository.dart';

/// Owns organization resource mutations and maps failures to stable copy.
final class OrganizationResourcesViewModel extends BaseViewModel {
  OrganizationResourcesViewModel({
    required this.organization,
    required this.repository,
    required this.onSaved,
    this.legacySourceWorkspaceId = '',
  });

  final OrganizationAccess organization;
  final OrganizationResourceRepository repository;
  final Future<void> Function() onSaved;
  final String legacySourceWorkspaceId;

  String? errorMessage;
  DataPlaneValidationModel? validation;

  bool get refreshingLegacySetup => organization.resources.gcp.any(
    (resource) =>
        resource.active &&
        resource.legacySourceWorkspaceId == legacySourceWorkspaceId,
  );

  bool get canPromoteLegacySetup =>
      legacySourceWorkspaceId.isNotEmpty &&
      organization.can('org.integrations.manage') &&
      (organization.resources.gcp.isEmpty || refreshingLegacySetup);

  Future<bool> promoteLegacySetup() => _save(
    action: () => repository.promoteLegacyWorkspace(
      organizationId: organization.id,
      sourceWorkspaceId: legacySourceWorkspaceId,
    ),
    failure:
        'The existing setup could not be attached to this organization. '
        'Run its checks from the original workspace and try again.',
  );

  Future<bool> addGcp(OrganizationGcpResourceDraft resource) async {
    if (isBusy) return false;
    setBusy(true);
    errorMessage = null;
    try {
      validation = await repository.saveGcpResource(
        organizationId: organization.id,
        resource: resource,
      );
      if (!validation!.ready) {
        errorMessage =
            'The GCP project was not added because its infrastructure checks '
            'need attention.';
        return false;
      }
      await onSaved();
      validation = null;
      return true;
    } on Object {
      errorMessage =
          'The GCP project could not be added. Check the service account and '
          'try again.';
      return false;
    } finally {
      setBusy(false);
    }
  }

  Future<bool> addRunner(OrganizationRunnerPoolDraft resource) => _save(
    action: () => repository.saveRunnerPool(
      organizationId: organization.id,
      resource: resource,
    ),
    failure:
        'The runner pool could not be added. Check its capacity and try again.',
  );

  Future<bool> syncFleetRunnerPool() => _save(
    action: () =>
        repository.syncFleetRunnerPool(organizationId: organization.id),
    failure:
        'Fleet capacity could not be synced. Confirm organization Fleet '
        'reporting is current and try again.',
  );

  Future<bool> _save({
    required Future<void> Function() action,
    required String failure,
  }) async {
    if (isBusy) return false;
    setBusy(true);
    errorMessage = null;
    try {
      await action();
      await onSaved();
      return true;
    } on Object {
      errorMessage = failure;
      return false;
    } finally {
      setBusy(false);
    }
  }
}
