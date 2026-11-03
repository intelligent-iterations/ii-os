import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/organization_people.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/people_directory.dart';

void main() {
  testWidgets('shows organization people and their pending invitations', (
    tester,
  ) async {
    OrganizationPersonModel? managed;

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PeopleDirectory(
              directory: _directory,
              people: _directory.people,
              onManageAccess: (person) => managed = person,
              onRevokeInvitation: (_) {},
              isRevoking: (_) => false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2 people'), findsOneWidget);
    expect(find.text('2 workspaces'), findsOneWidget);
    expect(find.text('person@example.com'), findsOneWidget);
    expect(find.text('Email sent'), findsOneWidget);
    expect(find.text('Admin'), findsWidgets);
    expect(find.text('Campaigns'), findsWidgets);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Manage workspaces').last,
    );
    expect(managed?.email, 'person@example.com');
  });

  testWidgets('fits organization access at phone and desktop widths', (
    tester,
  ) async {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PeopleDirectory(
                directory: _directory,
                people: _directory.people,
                onManageAccess: (_) {},
                onRevokeInvitation: (_) {},
                isRevoking: (_) => false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Pending invitations'), findsOneWidget);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

const _directory = OrganizationPeopleModel(
  people: [
    OrganizationPersonModel(
      uid: 'owner-1',
      email: 'owner@example.com',
      role: 'owner',
      roleLabel: 'Organization Owner',
    ),
    OrganizationPersonModel(
      uid: 'person-1',
      email: 'person@example.com',
      role: 'member',
      roleLabel: 'Organization Member',
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
  invitations: [
    OrganizationInvitationModel(
      id: 'invite-1',
      email: 'new@example.com',
      role: 'member',
      roleLabel: 'Organization Member',
      workspaceIds: ['workspace-admin', 'workspace-campaigns'],
      deliveryStatus: 'delivered',
      expiresAt: null,
    ),
  ],
);
