import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/domain.dart';
import 'package:ii_os_functions/src/organization.dart';
import 'package:ii_os_functions/src/organization_membership_policy.dart';
import 'package:test/test.dart';

void main() {
  group('organization member changes', () {
    test('only an organization owner can assign the Owner role', () {
      expect(
        () => requireOrganizationMemberUpdateAllowed(
          actor: _organizationMember('admin', OrganizationRole.admin),
          target: _organizationMember('member', OrganizationRole.member),
          nextRole: OrganizationRole.owner,
          members: [
            _organizationMember('owner', OrganizationRole.owner),
            _organizationMember('admin', OrganizationRole.admin),
            _organizationMember('member', OrganizationRole.member),
          ],
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'organization_owner_required',
          ),
        ),
      );
    });

    test('the last organization owner cannot be demoted', () {
      expect(
        () => requireOrganizationMemberUpdateAllowed(
          actor: _organizationMember('owner', OrganizationRole.owner),
          target: _organizationMember('owner', OrganizationRole.owner),
          nextRole: OrganizationRole.admin,
          members: [
            _organizationMember('owner', OrganizationRole.owner),
            _organizationMember('member', OrganizationRole.member),
          ],
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'last_organization_owner',
          ),
        ),
      );
    });

    test('one of two owners can be changed', () {
      expect(
        () => requireOrganizationMemberUpdateAllowed(
          actor: _organizationMember('owner-a', OrganizationRole.owner),
          target: _organizationMember('owner-b', OrganizationRole.owner),
          nextRole: OrganizationRole.admin,
          members: [
            _organizationMember('owner-a', OrganizationRole.owner),
            _organizationMember('owner-b', OrganizationRole.owner),
          ],
        ),
        returnsNormally,
      );
    });
  });

  group('organization member removal', () {
    test('an organization admin cannot remove an owner', () {
      expect(
        () => requireOrganizationMemberRemovalAllowed(
          actor: _organizationMember('admin', OrganizationRole.admin),
          target: _organizationMember('owner-a', OrganizationRole.owner),
          organizationMembers: [
            _organizationMember('owner-a', OrganizationRole.owner),
            _organizationMember('owner-b', OrganizationRole.owner),
            _organizationMember('admin', OrganizationRole.admin),
          ],
          targetWorkspaceMemberships: const [],
          workspaceOwnerMemberships: const [],
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'organization_owner_required',
          ),
        ),
      );
    });

    test('the last organization owner cannot be removed', () {
      expect(
        () => requireOrganizationMemberRemovalAllowed(
          actor: _organizationMember('owner', OrganizationRole.owner),
          target: _organizationMember('owner', OrganizationRole.owner),
          organizationMembers: [
            _organizationMember('owner', OrganizationRole.owner),
            _organizationMember('member', OrganizationRole.member),
          ],
          targetWorkspaceMemberships: const [],
          workspaceOwnerMemberships: const [],
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'last_organization_owner',
          ),
        ),
      );
    });

    test('removes a workspace owner when another owner remains', () {
      expect(
        () => requireOrganizationMemberRemovalAllowed(
          actor: _organizationMember('owner-a', OrganizationRole.owner),
          target: _organizationMember('member', OrganizationRole.member),
          organizationMembers: [
            _organizationMember('owner-a', OrganizationRole.owner),
            _organizationMember('member', OrganizationRole.member),
          ],
          targetWorkspaceMemberships: [
            _workspaceMember('workspace-a', 'member', WorkspaceRole.owner),
          ],
          workspaceOwnerMemberships: [
            _workspaceMember('workspace-a', 'member', WorkspaceRole.owner),
            _workspaceMember('workspace-a', 'owner-a', WorkspaceRole.owner),
          ],
        ),
        returnsNormally,
      );
    });

    test('refuses to leave a workspace without an owner', () {
      expect(
        () => requireOrganizationMemberRemovalAllowed(
          actor: _organizationMember('owner', OrganizationRole.owner),
          target: _organizationMember('member', OrganizationRole.member),
          organizationMembers: [
            _organizationMember('owner', OrganizationRole.owner),
            _organizationMember('member', OrganizationRole.member),
          ],
          targetWorkspaceMemberships: [
            _workspaceMember('workspace-a', 'member', WorkspaceRole.owner),
          ],
          workspaceOwnerMemberships: [
            _workspaceMember('workspace-a', 'member', WorkspaceRole.owner),
          ],
        ),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'last_workspace_owner',
          ),
        ),
      );
    });
  });
}

OrganizationMembership _organizationMember(String uid, OrganizationRole role) =>
    OrganizationMembership(
      organizationId: 'organization-1',
      uid: uid,
      email: '$uid@example.com',
      role: role,
      featureClaims: const {},
    );

Membership _workspaceMember(
  String workspaceId,
  String uid,
  WorkspaceRole role,
) => Membership(
  workspaceId: workspaceId,
  uid: uid,
  email: '$uid@example.com',
  role: role,
  featureClaims: const {},
);
