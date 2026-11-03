import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/people_repository.dart';
import 'package:ii_os/view_models/people_view_model.dart';
import 'package:ii_os/view_models/workspace_access_view_model.dart';

void main() {
  test(
    'loads the organization directory and filters people by email',
    () async {
      final repository = _FakePeopleRepository(directory: _directory);
      final model = PeopleViewModel(
        organizationId: 'organization-1',
        repository: repository,
      );

      await model.load();
      model.setQuery('person');

      expect(model.directory, _directory);
      expect(model.visiblePeople.single.email, 'person@example.com');
      expect(model.errorMessage, isNull);
    },
  );

  test(
    'an invite carries every selected workspace and reports delivery',
    () async {
      final repository = _FakePeopleRepository(directory: _directory);
      final model = PeopleViewModel(
        organizationId: 'organization-1',
        repository: repository,
      );
      await model.load();

      final result = await model.invite(
        email: 'new@example.com',
        role: 'member',
        workspaceIds: const ['workspace-admin', 'workspace-campaigns'],
      );

      expect(repository.invitedWorkspaceIds, [
        'workspace-admin',
        'workspace-campaigns',
      ]);
      expect(result?.delivered, isTrue);
      expect(result?.message, 'Invitation emailed to new@example.com.');
    },
  );

  test('grants a workspace the person has never had', () async {
    final repository = _FakePeopleRepository(directory: _directory);
    final model = WorkspaceAccessViewModel(
      organization: _organization,
      person: _directory.people.last,
      workspaces: _directory.workspaces,
      actorWorkspaceMemberships: _actorWorkspaceMemberships,
      repository: repository,
    );
    await model.load();

    expect(model.hasAccess('workspace-campaigns'), isFalse);
    await model.setAccess(_directory.workspaces.last, true);

    expect(repository.changedWorkspaceId, 'workspace-campaigns');
    expect(repository.changedSuspended, isFalse);
    expect(model.hasAccess('workspace-campaigns'), isTrue);
    expect(
      model.messageFor('workspace-campaigns'),
      'Access granted and email sent.',
    );
  });

  test('keeps a workspace owner assigned', () async {
    final repository = _FakePeopleRepository(
      directory: _directory,
      access: const [
        WorkspaceAssignmentModel(
          workspaceId: 'workspace-admin',
          role: 'owner',
          roleLabel: 'Workspace Owner',
          suspended: false,
        ),
      ],
    );
    final model = WorkspaceAccessViewModel(
      organization: _organization,
      person: _directory.people.first,
      workspaces: _directory.workspaces,
      actorWorkspaceMemberships: _actorWorkspaceMemberships,
      repository: repository,
    );
    await model.load();

    expect(model.canChange('workspace-admin'), isFalse);
    await model.setAccess(_directory.workspaces.first, false);
    expect(repository.changedWorkspaceId, isNull);
    expect(model.hasAccess('workspace-admin'), isTrue);
  });

  test(
    'edits organization standing without changing workspace roles',
    () async {
      final repository = _FakePeopleRepository(
        directory: _directory,
        access: const [
          WorkspaceAssignmentModel(
            workspaceId: 'workspace-admin',
            role: 'view_only',
            roleLabel: 'Workspace Viewer',
            suspended: false,
          ),
        ],
      );
      final model = WorkspaceAccessViewModel(
        organization: _organization,
        person: _directory.people.last,
        workspaces: _directory.workspaces,
        actorWorkspaceMemberships: _actorWorkspaceMemberships,
        repository: repository,
      );
      await model.load();

      await model.saveOrganizationRole('admin');

      expect(repository.updatedOrganizationRole, 'admin');
      expect(model.organizationRole, 'admin');
      expect(model.roleFor('workspace-admin'), 'Workspace Viewer');
    },
  );

  test('assigns different granular roles in different workspaces', () async {
    final repository = _FakePeopleRepository(
      directory: _directory,
      access: const [
        WorkspaceAssignmentModel(
          workspaceId: 'workspace-admin',
          role: 'view_only',
          roleLabel: 'Workspace Viewer',
          suspended: false,
          featureClaims: {'workspace.read'},
          effectiveCapabilities: {'workspace.read'},
        ),
        WorkspaceAssignmentModel(
          workspaceId: 'workspace-campaigns',
          role: 'view_only',
          roleLabel: 'Workspace Viewer',
          suspended: false,
          featureClaims: {'workspace.read'},
          effectiveCapabilities: {'workspace.read'},
        ),
      ],
    );
    final model = WorkspaceAccessViewModel(
      organization: _organization,
      person: _directory.people.last,
      workspaces: _directory.workspaces,
      actorWorkspaceMemberships: _actorWorkspaceMemberships,
      repository: repository,
    );
    await model.load();

    await model.saveWorkspacePermissions(
      _directory.workspaces.first,
      role: 'admin',
      featureClaims: const {'workspace.read', 'members.manage'},
    );

    expect(model.assignmentFor('workspace-admin')?.role, 'admin');
    expect(model.assignmentFor('workspace-campaigns')?.role, 'view_only');
    expect(repository.updatedWorkspaceClaims, {
      'workspace.read',
      'members.manage',
    });
  });

  test('removing a person calls the organization cascade', () async {
    final repository = _FakePeopleRepository(directory: _directory);
    final model = WorkspaceAccessViewModel(
      organization: _organization,
      person: _directory.people.last,
      workspaces: _directory.workspaces,
      actorWorkspaceMemberships: _actorWorkspaceMemberships,
      repository: repository,
    );

    expect(await model.removePerson(), isTrue);
    expect(repository.removedUid, 'person-1');
  });

  test('maps a directory failure onto product copy', () async {
    final repository = _FakePeopleRepository(
      directory: _directory,
      failure: const PeopleRepositoryFailure(PeopleFailureKind.network),
    );
    final model = PeopleViewModel(
      organizationId: 'organization-1',
      repository: repository,
    );

    await model.load();

    expect(
      model.errorMessage,
      'ii-os could not reach the organization directory. Try again.',
    );
    expect(model.errorMessage, isNot(contains('PeopleRepositoryFailure')));
  });

  test('explains an invitation send window without exposing API text', () {
    expect(
      peopleFailureMessage(
        const PeopleRepositoryFailure(PeopleFailureKind.invitationRateLimited),
      ),
      'Too many invitations were sent recently. Try again later.',
    );
  });
}

const _directory = OrganizationPeopleModel(
  people: [
    OrganizationPersonModel(
      uid: 'owner-1',
      email: 'owner@example.com',
      role: 'owner',
      roleLabel: 'Organization Owner',
      featureClaims: {},
      effectiveCapabilities: {'org.members.manage'},
    ),
    OrganizationPersonModel(
      uid: 'person-1',
      email: 'person@example.com',
      role: 'member',
      roleLabel: 'Organization Member',
      featureClaims: {},
      effectiveCapabilities: {'org.read'},
    ),
  ],
  workspaces: [
    OrganizationWorkspaceModel(
      id: 'workspace-admin',
      name: 'Admin',
      environment: 'prod',
    ),
    OrganizationWorkspaceModel(
      id: 'workspace-campaigns',
      name: 'Campaigns',
      environment: 'dev',
    ),
  ],
  invitations: [],
  workspaceRoles: [
    PermissionRoleModel(
      id: 'admin',
      label: 'Workspace Admin',
      capabilities: [
        PermissionCapabilityModel(
          id: 'workspace.read',
          label: 'View workspace',
        ),
        PermissionCapabilityModel(
          id: 'members.manage',
          label: 'Manage workspace members',
        ),
      ],
    ),
    PermissionRoleModel(
      id: 'view_only',
      label: 'Workspace Viewer',
      capabilities: [
        PermissionCapabilityModel(
          id: 'workspace.read',
          label: 'View workspace',
        ),
      ],
    ),
  ],
);

const _organization = OrganizationAccess(
  id: 'organization-1',
  name: 'Acme',
  role: 'Organization Owner',
  roleId: 'owner',
  capabilities: {'org.members.manage', 'org.workspaces.access.manage'},
);

const _actorWorkspaceMemberships = {
  'workspace-admin': MembershipModel(
    workspaceId: 'workspace-admin',
    uid: 'owner-1',
    email: 'owner@example.com',
    role: 'owner',
    roleLabel: 'Workspace Owner',
    featureClaims: {},
    capabilities: {'workspace.read', 'members.manage'},
  ),
  'workspace-campaigns': MembershipModel(
    workspaceId: 'workspace-campaigns',
    uid: 'owner-1',
    email: 'owner@example.com',
    role: 'admin',
    roleLabel: 'Workspace Admin',
    featureClaims: {'workspace.read', 'members.manage'},
    capabilities: {'workspace.read', 'members.manage'},
  ),
};

final class _FakePeopleRepository implements PeopleRepository {
  _FakePeopleRepository({
    required this.directory,
    this.access = const [],
    this.failure,
  });

  final OrganizationPeopleModel directory;
  final List<WorkspaceAssignmentModel> access;
  final PeopleRepositoryFailure? failure;
  List<String>? invitedWorkspaceIds;
  String? changedWorkspaceId;
  bool? changedSuspended;
  String? updatedOrganizationRole;
  Set<String>? updatedWorkspaceClaims;
  String? removedUid;

  @override
  Future<OrganizationPeopleModel> loadDirectory(String organizationId) async {
    if (failure case final value?) throw value;
    return directory;
  }

  @override
  Future<List<WorkspaceAssignmentModel>> loadWorkspaceAccess({
    required String organizationId,
    required String uid,
  }) async => access;

  @override
  Future<PeopleInviteResult> invite({
    required String organizationId,
    required String email,
    required String role,
    required List<String> workspaceIds,
  }) async {
    invitedWorkspaceIds = workspaceIds;
    return PeopleInviteResult(email: email, delivered: true);
  }

  @override
  Future<void> revokeInvitation({
    required String organizationId,
    required String invitationId,
  }) async {}

  @override
  Future<WorkspaceAccessChangeModel> setWorkspaceAccess({
    required String organizationId,
    required String workspaceId,
    required String uid,
    required bool suspended,
  }) async {
    changedWorkspaceId = workspaceId;
    changedSuspended = suspended;
    return WorkspaceAccessChangeModel(
      workspaceId: workspaceId,
      suspended: suspended,
      granted: !suspended,
      notificationDelivered: !suspended,
    );
  }

  @override
  Future<OrganizationPersonModel> updateOrganizationMember({
    required String organizationId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  }) async {
    updatedOrganizationRole = role;
    return OrganizationPersonModel(
      uid: uid,
      email: 'person@example.com',
      role: role,
      roleLabel: 'Organization Admin',
      featureClaims: featureClaims,
      effectiveCapabilities: const {'org.read'},
    );
  }

  @override
  Future<WorkspaceAssignmentModel> updateWorkspaceMember({
    required String workspaceId,
    required String uid,
    required String role,
    required Set<String> featureClaims,
  }) async {
    updatedWorkspaceClaims = featureClaims;
    return WorkspaceAssignmentModel(
      workspaceId: workspaceId,
      role: role,
      roleLabel: 'Workspace Admin',
      suspended: false,
      featureClaims: featureClaims,
      effectiveCapabilities: featureClaims,
    );
  }

  @override
  Future<void> removeOrganizationMember({
    required String organizationId,
    required String uid,
  }) async {
    removedUid = uid;
  }

  @override
  Future<void> deleteOrganization(String organizationId) async {}
}
