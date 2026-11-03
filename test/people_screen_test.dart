import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/people_repository.dart';
import 'package:ii_os/screens/people_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

void main() {
  testWidgets('invites one email into several selected workspaces', (
    tester,
  ) async {
    final repository = _PeopleFixtureRepository();
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller, repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Invite person'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('organization-invite-email')),
      'new@example.com',
    );
    await tester.tap(find.text('Campaigns').last);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send invitation'));
    await tester.pumpAndSettle();

    expect(repository.invitedEmail, 'new@example.com');
    expect(repository.invitedWorkspaceIds, {
      'workspace-admin',
      'workspace-campaigns',
    });
    expect(find.text('Invitation emailed to new@example.com.'), findsOneWidget);
  });

  testWidgets('assigns an existing person a workspace in place', (
    tester,
  ) async {
    final repository = _PeopleFixtureRepository();
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller, repository);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Manage workspaces').last,
    );
    await tester.pumpAndSettle();
    final campaigns = find.byKey(
      const Key('workspace-access-workspace-campaigns'),
    );
    expect(tester.widget<SwitchListTile>(campaigns).value, isFalse);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(campaigns);
    await tester.pumpAndSettle();

    expect(repository.changedUid, 'person-1');
    expect(repository.changedWorkspaceId, 'workspace-campaigns');
    expect(repository.changedSuspended, isFalse);
    expect(find.text('Access granted and email sent.'), findsOneWidget);
  });

  testWidgets('edits one workspace role without changing another', (
    tester,
  ) async {
    final repository = _PeopleFixtureRepository();
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller, repository);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Manage workspaces').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('workspace-permissions-workspace-admin')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-role-workspace-admin')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace Admin').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Manage workspace members'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save permissions'));
    await tester.pumpAndSettle();

    expect(repository.updatedWorkspaceId, 'workspace-admin');
    expect(repository.updatedWorkspaceRole, 'admin');
    expect(repository.updatedWorkspaceClaims, contains('workspace.read'));
    expect(
      repository.updatedWorkspaceClaims,
      isNot(contains('members.manage')),
    );
    expect(repository.campaignsRole, 'view_only');
  });

  testWidgets('changes an organization role and removes the person', (
    tester,
  ) async {
    final repository = _PeopleFixtureRepository();
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller, repository);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Manage workspaces').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organization-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Save organization role'),
    );
    await tester.pumpAndSettle();

    expect(repository.updatedOrganizationRole, 'admin');

    await tester.scrollUntilVisible(
      find.byKey(const Key('remove-from-organization')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('remove-from-organization')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-remove-person')));
    await tester.pumpAndSettle();

    expect(repository.removedUid, 'person-1');
  });

  testWidgets('an owner can delete the organization after naming it', (
    tester,
  ) async {
    final repository = _PeopleFixtureRepository();
    final controller = _controller();
    var refreshed = false;
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      repository,
      onOrganizationDeleted: () async => refreshed = true,
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Delete organization'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-organization-name')),
      'Acme',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-delete-organization')));
    await tester.pumpAndSettle();

    expect(repository.deletedOrganizationId, 'organization-1');
    expect(refreshed, isTrue);
  });

  testWidgets('invite and access dialogs fit a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = _PeopleFixtureRepository();
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller, repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Invite person'));
    await tester.pumpAndSettle();
    expect(find.text('Workspace access'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Manage workspaces').last,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Changes take effect immediately.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  PeopleRepository repository, {
  Future<void> Function()? onOrganizationDeleted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: IiOsTheme.light(),
      home: Scaffold(
        body: PeopleScreen(
          controller: controller,
          repository: repository,
          onOrganizationDeleted: onOrganizationDeleted,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

AppController _controller() {
  final session = SessionModel.fromJson({
    'user': {
      'uid': 'owner-1',
      'email': 'owner@example.com',
      'displayName': 'Owner',
      'isOwner': true,
    },
    'organizations': [
      {
        'organization': {'id': 'organization-1', 'name': 'Acme'},
        'membership': {
          'role': 'owner',
          'roleLabel': 'Organization Owner',
          'effectiveCapabilities': [
            'org.members.manage',
            'org.workspaces.access.manage',
          ],
        },
      },
    ],
    'workspaces': [
      {
        'workspace': {
          'id': 'workspace-admin',
          'name': 'Admin',
          'organizationId': 'organization-1',
          'environment': 'prod',
          'repositories': <Object?>[],
          'projects': <Object?>[],
          'workflows': <Object?>[],
        },
        'membership': {
          'workspaceId': 'workspace-admin',
          'uid': 'owner-1',
          'email': 'owner@example.com',
          'role': 'owner',
          'roleLabel': 'Workspace Owner',
          'effectiveCapabilities': ['workspace.read', 'members.manage'],
        },
      },
    ],
  });
  return AppController()
    ..session = session
    ..selectedAccess = session.workspaces.single;
}

final class _PeopleFixtureRepository implements PeopleRepository {
  String? invitedEmail;
  Set<String>? invitedWorkspaceIds;
  String? changedUid;
  String? changedWorkspaceId;
  bool? changedSuspended;
  String? updatedOrganizationRole;
  String? updatedWorkspaceId;
  String? updatedWorkspaceRole;
  Set<String>? updatedWorkspaceClaims;
  String campaignsRole = 'view_only';
  String? removedUid;
  String? deletedOrganizationId;

  @override
  Future<OrganizationPeopleModel> loadDirectory(String organizationId) async =>
      _directory;

  @override
  Future<List<WorkspaceAssignmentModel>> loadWorkspaceAccess({
    required String organizationId,
    required String uid,
  }) async => uid == 'owner-1'
      ? const [
          WorkspaceAssignmentModel(
            workspaceId: 'workspace-admin',
            role: 'owner',
            roleLabel: 'Workspace Owner',
            suspended: false,
            featureClaims: {},
            effectiveCapabilities: {},
          ),
        ]
      : const [
          WorkspaceAssignmentModel(
            workspaceId: 'workspace-admin',
            role: 'view_only',
            roleLabel: 'Workspace Viewer',
            suspended: false,
            featureClaims: {'workspace.read'},
            effectiveCapabilities: {'workspace.read'},
          ),
        ];

  @override
  Future<PeopleInviteResult> invite({
    required String organizationId,
    required String email,
    required String role,
    required List<String> workspaceIds,
  }) async {
    invitedEmail = email;
    invitedWorkspaceIds = workspaceIds.toSet();
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
    changedUid = uid;
    changedWorkspaceId = workspaceId;
    changedSuspended = suspended;
    return WorkspaceAccessChangeModel(
      workspaceId: workspaceId,
      suspended: suspended,
      granted: true,
      notificationDelivered: true,
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
    updatedWorkspaceId = workspaceId;
    updatedWorkspaceRole = role;
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
  Future<void> deleteOrganization(String organizationId) async {
    deletedOrganizationId = organizationId;
  }
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
