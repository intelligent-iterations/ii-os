import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/organization_people.dart';

void main() {
  test('parses editable roles, claims, and workspace permission catalog', () {
    final directory = OrganizationPeopleModel.fromJson({
      'members': [
        {
          'uid': 'member-1',
          'email': 'member@example.com',
          'role': 'member',
          'roleLabel': 'Organization Member',
          'featureClaims': ['org.read'],
          'effectiveCapabilities': ['org.read'],
        },
      ],
      'workspaces': <Object?>[],
      'invitations': <Object?>[],
      'workspaceRoles': [
        {
          'id': 'admin',
          'label': 'Workspace Admin',
          'capabilities': [
            {'id': 'members.manage', 'label': 'Manage workspace members'},
          ],
        },
      ],
    });

    expect(directory.people.single.featureClaims, {'org.read'});
    expect(directory.people.single.effectiveCapabilities, {'org.read'});
    expect(directory.workspaceRoles.single.id, 'admin');
    expect(
      directory.workspaceRoles.single.capabilities.single.label,
      'Manage workspace members',
    );
  });

  test('parses independent claims for one workspace assignment', () {
    final assignment = WorkspaceAssignmentModel.fromJson({
      'workspaceId': 'workspace-1',
      'role': 'editor',
      'roleLabel': 'Workspace Editor',
      'featureClaims': ['workspace.read', 'jobs.trigger'],
      'effectiveCapabilities': ['workspace.read', 'jobs.read', 'jobs.trigger'],
    });

    expect(assignment.featureClaims, {'workspace.read', 'jobs.trigger'});
    expect(assignment.effectiveCapabilities, contains('jobs.read'));
  });
}
