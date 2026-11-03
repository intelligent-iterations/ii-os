import 'api_error.dart';
import 'domain.dart';
import 'organization.dart';

/// Protects organization ownership while allowing ordinary roles to change.
void requireOrganizationMemberUpdateAllowed({
  required OrganizationMembership actor,
  required OrganizationMembership target,
  required OrganizationRole nextRole,
  required Iterable<OrganizationMembership> members,
}) {
  final changesOwner =
      target.role == OrganizationRole.owner ||
      nextRole == OrganizationRole.owner;
  if (changesOwner && actor.role != OrganizationRole.owner) {
    throw const ApiError(
      403,
      'organization_owner_required',
      'Only an organization owner can assign or remove the Owner role.',
    );
  }
  if (target.role == OrganizationRole.owner &&
      nextRole != OrganizationRole.owner &&
      !_hasAnotherOrganizationOwner(members, target.uid)) {
    throw const ApiError(
      409,
      'last_organization_owner',
      'Promote another organization owner before changing the last owner.',
    );
  }
}

/// Protects both tenant ownership and the independent owner of every project.
void requireOrganizationMemberRemovalAllowed({
  required OrganizationMembership actor,
  required OrganizationMembership target,
  required Iterable<OrganizationMembership> organizationMembers,
  required Iterable<Membership> targetWorkspaceMemberships,
  required Iterable<Membership> workspaceOwnerMemberships,
}) {
  if (target.role == OrganizationRole.owner &&
      actor.role != OrganizationRole.owner) {
    throw const ApiError(
      403,
      'organization_owner_required',
      'Only an organization owner can remove another owner.',
    );
  }
  if (target.role == OrganizationRole.owner &&
      !_hasAnotherOrganizationOwner(organizationMembers, target.uid)) {
    throw const ApiError(
      409,
      'last_organization_owner',
      'Promote another organization owner before removing the last owner.',
    );
  }

  final ownersByWorkspace = <String, Set<String>>{};
  for (final membership in workspaceOwnerMemberships) {
    if (membership.role != WorkspaceRole.owner) continue;
    ownersByWorkspace
        .putIfAbsent(membership.workspaceId, () => <String>{})
        .add(membership.uid);
  }
  for (final membership in targetWorkspaceMemberships) {
    if (membership.role != WorkspaceRole.owner) continue;
    final otherOwners = (ownersByWorkspace[membership.workspaceId] ?? const {})
        .where((uid) => uid != target.uid);
    if (otherOwners.isEmpty) {
      throw const ApiError(
        409,
        'last_workspace_owner',
        'Promote another workspace owner before removing this person.',
      );
    }
  }
}

bool _hasAnotherOrganizationOwner(
  Iterable<OrganizationMembership> members,
  String targetUid,
) => members.any(
  (member) => member.uid != targetUid && member.role == OrganizationRole.owner,
);
