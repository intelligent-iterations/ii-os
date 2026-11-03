import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/people_repository.dart';
import 'people_view_model.dart';

final class WorkspaceAccessViewModel extends BaseViewModel {
  WorkspaceAccessViewModel({
    required this.organization,
    required OrganizationPersonModel person,
    required this.workspaces,
    required this.actorWorkspaceMemberships,
    required this.repository,
  }) : _organizationPerson = person;

  final OrganizationAccess organization;
  final List<OrganizationWorkspaceModel> workspaces;
  final Map<String, MembershipModel> actorWorkspaceMemberships;
  final PeopleRepository repository;

  OrganizationPersonModel _organizationPerson;
  final Map<String, WorkspaceAssignmentModel> _assignments = {};
  final Set<String> _changing = {};
  final Map<String, String> _messages = {};
  final Map<String, String> _errors = {};
  String? organizationError;
  String? loadError;
  bool loaded = false;
  bool changingOrganization = false;
  bool removingPerson = false;
  bool hasSavedChanges = false;

  String get organizationId => organization.id;
  OrganizationPersonModel get person => _organizationPerson;
  String get organizationRole => _organizationPerson.role;
  bool get canEditOrganization =>
      organization.can('org.members.manage') &&
      (_organizationPerson.role != 'owner' || organization.roleId == 'owner');
  bool get canRemovePerson => canEditOrganization;

  bool hasAccess(String workspaceId) =>
      _assignments[workspaceId]?.suspended == false;

  bool canChange(String workspaceId) =>
      organization.can('org.workspaces.access.manage') &&
      _assignments[workspaceId]?.role != 'owner';

  bool canEditWorkspacePermissions(String workspaceId) =>
      hasAccess(workspaceId) &&
      actorWorkspaceMemberships[workspaceId]?.can('members.manage') == true &&
      (_assignments[workspaceId]?.role != 'owner' ||
          canAssignWorkspaceOwner(workspaceId));

  bool canAssignWorkspaceOwner(String workspaceId) =>
      actorWorkspaceMemberships[workspaceId]?.role == 'owner';

  bool changing(String workspaceId) => _changing.contains(workspaceId);
  bool get hasChangesInFlight =>
      _changing.isNotEmpty || changingOrganization || removingPerson;
  String? messageFor(String workspaceId) => _messages[workspaceId];
  String? errorFor(String workspaceId) => _errors[workspaceId];
  String? roleFor(String workspaceId) => _assignments[workspaceId]?.roleLabel;
  WorkspaceAssignmentModel? assignmentFor(String workspaceId) =>
      _assignments[workspaceId];

  Set<String> grantableCapabilities(
    String workspaceId,
    PermissionRoleModel role,
  ) {
    final actor = actorWorkspaceMemberships[workspaceId];
    if (actor == null) return const {};
    return role.capabilities
        .map((capability) => capability.id)
        .where(actor.capabilities.contains)
        .toSet();
  }

  Future<void> load() async {
    setBusy(true);
    try {
      final access = await repository.loadWorkspaceAccess(
        organizationId: organizationId,
        uid: person.uid,
      );
      _assignments
        ..clear()
        ..addEntries(access.map((item) => MapEntry(item.workspaceId, item)));
      loadError = null;
      loaded = true;
    } on PeopleRepositoryFailure catch (failure) {
      loadError = peopleFailureMessage(failure);
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  Future<bool> saveOrganizationRole(String role) async {
    if (!canEditOrganization || changingOrganization) return false;
    changingOrganization = true;
    organizationError = null;
    notifyListeners();
    try {
      _organizationPerson = await repository.updateOrganizationMember(
        organizationId: organizationId,
        uid: person.uid,
        role: role,
        featureClaims: person.featureClaims,
      );
      hasSavedChanges = true;
      return true;
    } on PeopleRepositoryFailure catch (failure) {
      organizationError = peopleFailureMessage(failure);
      return false;
    } finally {
      changingOrganization = false;
      notifyListeners();
    }
  }

  Future<bool> saveWorkspacePermissions(
    OrganizationWorkspaceModel workspace, {
    required String role,
    required Set<String> featureClaims,
  }) async {
    if (!canEditWorkspacePermissions(workspace.id) || changing(workspace.id)) {
      return false;
    }
    _changing.add(workspace.id);
    _messages.remove(workspace.id);
    _errors.remove(workspace.id);
    notifyListeners();
    try {
      _assignments[workspace.id] = await repository.updateWorkspaceMember(
        workspaceId: workspace.id,
        uid: person.uid,
        role: role,
        featureClaims: featureClaims,
      );
      hasSavedChanges = true;
      _messages[workspace.id] = 'Permissions saved.';
      return true;
    } on PeopleRepositoryFailure catch (failure) {
      _errors[workspace.id] = peopleFailureMessage(failure);
      return false;
    } finally {
      _changing.remove(workspace.id);
      notifyListeners();
    }
  }

  Future<bool> removePerson() async {
    if (!canRemovePerson || removingPerson) return false;
    removingPerson = true;
    organizationError = null;
    notifyListeners();
    try {
      await repository.removeOrganizationMember(
        organizationId: organizationId,
        uid: person.uid,
      );
      hasSavedChanges = true;
      return true;
    } on PeopleRepositoryFailure catch (failure) {
      organizationError = peopleFailureMessage(failure);
      return false;
    } finally {
      removingPerson = false;
      notifyListeners();
    }
  }

  Future<void> setAccess(
    OrganizationWorkspaceModel workspace,
    bool enabled,
  ) async {
    if (!canChange(workspace.id) || changing(workspace.id)) return;
    _changing.add(workspace.id);
    _messages.remove(workspace.id);
    _errors.remove(workspace.id);
    notifyListeners();
    try {
      final change = await repository.setWorkspaceAccess(
        organizationId: organizationId,
        workspaceId: workspace.id,
        uid: person.uid,
        suspended: !enabled,
      );
      final existing = _assignments[workspace.id];
      _assignments[workspace.id] = existing == null
          ? WorkspaceAssignmentModel(
              workspaceId: workspace.id,
              role: 'view_only',
              roleLabel: 'Workspace Viewer',
              suspended: change.suspended,
            )
          : existing.withSuspended(change.suspended);
      hasSavedChanges = true;
      _messages[workspace.id] = _changeMessage(change);
    } on PeopleRepositoryFailure catch (failure) {
      _errors[workspace.id] = peopleFailureMessage(failure);
    } finally {
      _changing.remove(workspace.id);
      notifyListeners();
    }
  }
}

String _changeMessage(WorkspaceAccessChangeModel change) {
  if (change.granted && change.notificationDelivered == true) {
    return 'Access granted and email sent.';
  }
  if (change.granted) {
    return 'Access granted. The notification email could not be sent.';
  }
  return change.suspended ? 'Access removed.' : 'Access restored.';
}
