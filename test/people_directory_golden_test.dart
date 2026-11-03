@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/organization_people.dart';
import 'package:ii_os/widgets/people_card.dart';
import 'package:ii_os/widgets/people_directory.dart';
import 'package:ii_os/widgets/people_invitation_card.dart';
import 'package:ii_os/widgets/people_invitations.dart';

import 'golden_harness.dart';

void main() {
  setUpAll(loadIiOsFonts);
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
      ..physicalSize = const Size(800, 800)
      ..devicePixelRatio = 1;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  testWidgets('organization people directory', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const SingleChildScrollView(
          child: PeopleDirectory(
            directory: _directory,
            people: _people,
            onManageAccess: _noopPerson,
            onRevokeInvitation: _noopInvitation,
            isRevoking: _neverRevoking,
          ),
        ),
        width: 720,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PeopleDirectory),
      matchesGoldenFile('goldens/people_directory.png'),
    );
  });

  testWidgets('person card', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: PeopleCard(person: _owner, onManage: _noop),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PeopleCard),
      matchesGoldenFile('goldens/people_card.png'),
    );
  });

  testWidgets('pending invitations collection', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: PeopleInvitations(
            directory: _directory,
            onRevoke: _noopInvitation,
            isRevoking: _neverRevoking,
          ),
        ),
        width: 520,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PeopleInvitations),
      matchesGoldenFile('goldens/people_invitations.png'),
    );
  });

  testWidgets('pending invitation card', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: PeopleInvitationCard(
            invitation: _invitation,
            workspaceNames: ['Admin', 'Campaigns'],
            onRevoke: _noop,
            revoking: false,
          ),
        ),
        width: 520,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PeopleInvitationCard),
      matchesGoldenFile('goldens/people_invitation_card.png'),
    );
  });
}

void _noop() {}
void _noopPerson(OrganizationPersonModel _) {}
void _noopInvitation(OrganizationInvitationModel _) {}
bool _neverRevoking(String _) => false;

const _people = [
  _owner,
  OrganizationPersonModel(
    uid: 'person-1',
    email: 'person@example.com',
    role: 'member',
    roleLabel: 'Organization Member',
  ),
];

const _owner = OrganizationPersonModel(
  uid: 'owner-1',
  email: 'owner@example.com',
  role: 'owner',
  roleLabel: 'Organization Owner',
);

const _invitation = OrganizationInvitationModel(
  id: 'invite-1',
  email: 'new.collaborator@example.com',
  role: 'member',
  roleLabel: 'Organization Member',
  workspaceIds: ['workspace-admin', 'workspace-campaigns'],
  deliveryStatus: 'delivered',
  expiresAt: null,
);

const _directory = OrganizationPeopleModel(
  people: _people,
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
  invitations: [_invitation],
);
