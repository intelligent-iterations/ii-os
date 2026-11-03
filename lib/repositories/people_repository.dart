import 'dart:async';

import '../models/models.dart';
import '../services/api_client.dart';

abstract interface class PeopleRepository {
  Future<OrganizationPeopleModel> loadDirectory(String organizationId);

  Future<List<WorkspaceAssignmentModel>> loadWorkspaceAccess({
    required String organizationId,
    required String uid,
  });

  Future<PeopleInviteResult> invite({
    required String organizationId,
    required String email,
    required String role,
    required List<String> workspaceIds,
  });

  Future<void> revokeInvitation({
    required String organizationId,
    required String invitationId,
  });

  Future<WorkspaceAccessChangeModel> setWorkspaceAccess({
    required String organizationId,
    required String workspaceId,
    required String uid,
    required bool suspended,
  });

  Future<OrganizationPersonModel> updateOrganizationMember({
    required String organizationId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  });

  Future<WorkspaceAssignmentModel> updateWorkspaceMember({
    required String workspaceId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  });

  Future<void> removeOrganizationMember({
    required String organizationId,
    required String uid,
  });

  Future<void> deleteOrganization(String organizationId);
}

final class PeopleApiRepository implements PeopleRepository {
  const PeopleApiRepository(this.api);

  final ApiClient api;

  @override
  Future<OrganizationPeopleModel> loadDirectory(String organizationId) =>
      _mapped(
        () async => OrganizationPeopleModel.fromJson(
          await api.get('v1/organizations/$organizationId/people'),
        ),
      );

  @override
  Future<List<WorkspaceAssignmentModel>> loadWorkspaceAccess({
    required String organizationId,
    required String uid,
  }) => _mapped(() async {
    final response = await api.get(
      'v1/organizations/$organizationId/members/$uid/workspaces',
    );
    return (response['access'] as List<Object?>? ?? const [])
        .map(asJsonMap)
        .map(WorkspaceAssignmentModel.fromJson)
        .toList(growable: false);
  });

  @override
  Future<PeopleInviteResult> invite({
    required String organizationId,
    required String email,
    required String role,
    required List<String> workspaceIds,
  }) => _mapped(() async {
    final response = await api.post(
      'v1/organizations/$organizationId/invitations',
      body: {
        'email': email,
        'role': role,
        'featureClaims': const <String>[],
        'workspaceGrants': workspaceIds,
      },
    );
    final data = asJsonMap(response['data']);
    return PeopleInviteResult(
      email: data['email']?.toString() ?? email,
      delivered: data['delivered'] == true,
    );
  });

  @override
  Future<void> revokeInvitation({
    required String organizationId,
    required String invitationId,
  }) => _mapped(
    () => api.delete(
      'v1/organizations/$organizationId/invitations/$invitationId',
    ),
  );

  @override
  Future<WorkspaceAccessChangeModel> setWorkspaceAccess({
    required String organizationId,
    required String workspaceId,
    required String uid,
    required bool suspended,
  }) => _mapped(() async {
    final response = await api.patch(
      'v1/organizations/$organizationId/workspace-access/$workspaceId/$uid',
      body: {'suspended': suspended},
    );
    return WorkspaceAccessChangeModel.fromJson(asJsonMap(response['data']));
  });

  @override
  Future<OrganizationPersonModel> updateOrganizationMember({
    required String organizationId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  }) => _mapped(() async {
    final response = await api.patch(
      'v1/organizations/$organizationId/members/$uid',
      body: {'role': role, 'featureClaims': featureClaims.toList()..sort()},
    );
    return OrganizationPersonModel.fromJson(asJsonMap(response['data']));
  });

  @override
  Future<WorkspaceAssignmentModel> updateWorkspaceMember({
    required String workspaceId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  }) => _mapped(() async {
    final response = await api.patch(
      'v1/workspaces/$workspaceId/members/$uid',
      body: {'role': role, 'featureClaims': featureClaims.toList()..sort()},
    );
    return WorkspaceAssignmentModel.fromJson(asJsonMap(response['data']));
  });

  @override
  Future<void> removeOrganizationMember({
    required String organizationId,
    required String uid,
  }) => _mapped(
    () => api.delete('v1/organizations/$organizationId/members/$uid'),
  );

  @override
  Future<void> deleteOrganization(String organizationId) =>
      _mapped(() => api.delete('v1/organizations/$organizationId'));
}

final class PeopleInviteResult {
  const PeopleInviteResult({required this.email, required this.delivered});

  final String email;
  final bool delivered;
}

enum PeopleFailureKind {
  forbidden,
  network,
  limit,
  invitationPending,
  invitationCooldown,
  invitationRateLimited,
  invalidEmail,
  notFound,
  organizationUnavailable,
  ownerRequired,
  lastOwner,
  unknown,
}

final class PeopleRepositoryFailure implements Exception {
  const PeopleRepositoryFailure(this.kind);

  final PeopleFailureKind kind;
}

Future<T> _mapped<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on ApiFailure catch (failure) {
    throw PeopleRepositoryFailure(_failureKind(failure));
  } on TimeoutException {
    throw const PeopleRepositoryFailure(PeopleFailureKind.network);
  } on Object {
    throw const PeopleRepositoryFailure(PeopleFailureKind.unknown);
  }
}

PeopleFailureKind _failureKind(ApiFailure failure) {
  if (failure.statusCode == 401 || failure.statusCode == 403) {
    return PeopleFailureKind.forbidden;
  }
  if (failure.code.contains('limit_exceeded') ||
      failure.code == 'too_many_invitations') {
    return PeopleFailureKind.limit;
  }
  return switch (failure.code) {
    'invite_already_pending' => PeopleFailureKind.invitationPending,
    'invite_cooldown' => PeopleFailureKind.invitationCooldown,
    'too_many_invitation_emails' ||
    'too_many_invitation_requests' => PeopleFailureKind.invitationRateLimited,
    'invalid_email' => PeopleFailureKind.invalidEmail,
    'organization_member_not_found' ||
    'member_not_found' ||
    'workspace_not_found' ||
    'workspace_access_not_found' => PeopleFailureKind.notFound,
    'organization_not_found' ||
    'organization_deleted' ||
    'organization_deletion_in_progress' =>
      PeopleFailureKind.organizationUnavailable,
    'organization_owner_required' ||
    'workspace_owner_required' => PeopleFailureKind.ownerRequired,
    'last_organization_owner' ||
    'last_workspace_owner' => PeopleFailureKind.lastOwner,
    _ => PeopleFailureKind.unknown,
  };
}
