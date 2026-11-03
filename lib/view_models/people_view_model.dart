import 'package:stacked/stacked.dart';

import '../models/models.dart';
import '../repositories/people_repository.dart';

final class PeopleViewModel extends BaseViewModel {
  PeopleViewModel({required this.organizationId, required this.repository});

  final String organizationId;
  final PeopleRepository repository;

  OrganizationPeopleModel? directory;
  String? errorMessage;
  String query = '';
  bool inviting = false;
  bool deletingOrganization = false;
  final Set<String> _revoking = {};

  bool get isFirstLoad => isBusy && directory == null;
  bool revoking(String invitationId) => _revoking.contains(invitationId);

  List<OrganizationPersonModel> get visiblePeople {
    final people = directory?.people ?? const <OrganizationPersonModel>[];
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return people;
    return people
        .where(
          (person) =>
              person.email.toLowerCase().contains(needle) ||
              person.roleLabel.toLowerCase().contains(needle),
        )
        .toList(growable: false);
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) setBusy(true);
    try {
      directory = await repository.loadDirectory(organizationId);
      errorMessage = null;
    } on PeopleRepositoryFailure catch (failure) {
      errorMessage = peopleFailureMessage(failure, directoryLoad: true);
    } finally {
      if (!quiet) setBusy(false);
      notifyListeners();
    }
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  Future<PeopleInviteFeedback?> invite({
    required String email,
    required String role,
    required List<String> workspaceIds,
  }) async {
    inviting = true;
    notifyListeners();
    try {
      final result = await repository.invite(
        organizationId: organizationId,
        email: email,
        role: role,
        workspaceIds: workspaceIds,
      );
      await load(quiet: true);
      return PeopleInviteFeedback(
        delivered: result.delivered,
        message: result.delivered
            ? 'Invitation emailed to ${result.email}.'
            : 'Invitation created for ${result.email}, but the email could not be sent.',
      );
    } on PeopleRepositoryFailure catch (failure) {
      errorMessage = peopleFailureMessage(failure);
      notifyListeners();
      return null;
    } finally {
      inviting = false;
      notifyListeners();
    }
  }

  Future<bool> revoke(String invitationId) async {
    _revoking.add(invitationId);
    notifyListeners();
    try {
      await repository.revokeInvitation(
        organizationId: organizationId,
        invitationId: invitationId,
      );
      await load(quiet: true);
      return true;
    } on PeopleRepositoryFailure catch (failure) {
      errorMessage = peopleFailureMessage(failure);
      return false;
    } finally {
      _revoking.remove(invitationId);
      notifyListeners();
    }
  }

  Future<bool> deleteOrganization() async {
    deletingOrganization = true;
    errorMessage = null;
    notifyListeners();
    try {
      await repository.deleteOrganization(organizationId);
      return true;
    } on PeopleRepositoryFailure catch (failure) {
      errorMessage = peopleFailureMessage(failure);
      return false;
    } finally {
      deletingOrganization = false;
      notifyListeners();
    }
  }
}

final class PeopleInviteFeedback {
  const PeopleInviteFeedback({required this.delivered, required this.message});

  final bool delivered;
  final String message;
}

String peopleFailureMessage(
  PeopleRepositoryFailure failure, {
  bool directoryLoad = false,
}) => switch (failure.kind) {
  PeopleFailureKind.forbidden =>
    'Your organization role cannot manage people or workspace access.',
  PeopleFailureKind.network =>
    directoryLoad
        ? 'ii-os could not reach the organization directory. Try again.'
        : 'ii-os could not save that change. Try again.',
  PeopleFailureKind.limit =>
    'This organization is too large to manage on one page. Contact support.',
  PeopleFailureKind.invitationPending =>
    'That email already has a pending invitation.',
  PeopleFailureKind.invitationCooldown =>
    'That email was invited moments ago. Try again shortly.',
  PeopleFailureKind.invitationRateLimited =>
    'Too many invitations were sent recently. Try again later.',
  PeopleFailureKind.invalidEmail => 'Enter a valid email address.',
  PeopleFailureKind.notFound =>
    'That person or workspace is no longer available. Refresh and try again.',
  PeopleFailureKind.organizationUnavailable =>
    'This organization is no longer available or is being deleted. Refresh and try again.',
  PeopleFailureKind.ownerRequired =>
    'Only an owner can assign or remove an Owner role.',
  PeopleFailureKind.lastOwner =>
    'Promote another owner before removing or changing the last owner.',
  PeopleFailureKind.unknown =>
    directoryLoad
        ? 'The organization directory could not be loaded. Try again.'
        : 'That change could not be saved. Try again.',
};
