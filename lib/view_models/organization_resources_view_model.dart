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

  /// Why the last runner change failed, shown in the runner card beside the
  /// action rather than at the top of the page.
  String? runnerErrorMessage;

  bool get canManageRunners => organization.can('org.runners.manage');

  /// Rendered beside the runner actions when the viewer's role cannot use
  /// them, with the way to get unblocked.
  String? get runnerManageBlockedReason => canManageRunners
      ? null
      : runnerPoolFailureCopy[RunnerPoolFailureKind.forbidden];

  /// Ids saved through this view model. The organization snapshot above is
  /// taken once and the refresh after a save does not reach it, so without
  /// these a second pool with the same name would replace the first.
  final Set<String> _savedRunnerIds = {};

  Future<bool> addCustomerRunner(CustomerRunnerPoolInput input) {
    final id = customerRunnerPoolId(input.name, {
      ...organization.resources.runners.map((pool) => pool.id),
      ..._savedRunnerIds,
    });
    return _runnerChange(
      () => repository.saveRunnerPool(
        organizationId: organization.id,
        resource: input.toDraft(id),
      ),
      savedId: id,
    );
  }

  Future<bool> updateCustomerRunner(
    OrganizationRunnerPoolModel pool,
    CustomerRunnerPoolInput input,
  ) async {
    if (!pool.keptByHand) {
      runnerErrorMessage =
          runnerPoolFailureCopy[RunnerPoolFailureKind.reportedPool];
      notifyListeners();
      return false;
    }
    return _runnerChange(
      () => repository.saveRunnerPool(
        organizationId: organization.id,
        resource: input.toDraft(pool.id),
      ),
      savedId: pool.id,
    );
  }

  Future<bool> syncFleetRunnerPool() => _runnerChange(
    () => repository.syncFleetRunnerPool(organizationId: organization.id),
  );

  Future<bool> _runnerChange(
    Future<void> Function() action, {
    String? savedId,
  }) async {
    if (isBusy) return false;
    if (!canManageRunners) {
      runnerErrorMessage = runnerManageBlockedReason;
      notifyListeners();
      return false;
    }
    setBusy(true);
    runnerErrorMessage = null;
    try {
      await action();
      if (savedId != null) _savedRunnerIds.add(savedId);
      await onSaved();
      return true;
    } on RunnerPoolFailure catch (failure) {
      runnerErrorMessage = runnerPoolFailureCopy[failure.kind];
      return false;
    } on Object {
      runnerErrorMessage = runnerPoolFailureCopy[RunnerPoolFailureKind.unknown];
      return false;
    } finally {
      setBusy(false);
    }
  }

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

/// One sentence per runner failure, written for the person who pressed the
/// button. A deployment may have no runner control plane at all, so none of
/// these name one; each says what the person can do next.
const runnerPoolFailureCopy = <RunnerPoolFailureKind, String>{
  RunnerPoolFailureKind.notReported:
      'No capacity report has arrived from your runners. Use Add your '
      'runners to describe them instead.',
  RunnerPoolFailureKind.staleReport:
      'The last capacity report from your runners is out of date. Sync again '
      'once they report, or use Add your runners.',
  RunnerPoolFailureKind.noReportedCapacity:
      'The capacity report lists no runner a workspace can use. Check that '
      'your runners are online, or use Add your runners.',
  RunnerPoolFailureKind.limitReached:
      'This organization already holds as many runner pools as it can. Edit '
      'one of yours instead of adding another.',
  RunnerPoolFailureKind.reportedPool:
      'These runners come from your capacity report. Sync again to change '
      'them.',
  RunnerPoolFailureKind.invalid:
      'Your runners were not saved. Check the name, runner group, '
      'capabilities, and limits, then try again.',
  RunnerPoolFailureKind.forbidden:
      'Only an Organization Admin can add or change runners. Ask one to add '
      'yours or to give you that role.',
  RunnerPoolFailureKind.unknown:
      'The runner change did not go through. Try again in a moment.',
};
