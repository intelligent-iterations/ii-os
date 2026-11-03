import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/workshop_room.dart';
import 'package:ii_os/models/workshop_rooms.dart';

void main() {
  test('workspace keeps configured workshop rooms', () {
    final workspace = WorkspaceModel.fromJson({
      'id': 'workspace-1',
      'repositories': ['acme/app'],
      'projects': [
        {'id': 'project-1', 'number': 1, 'owner': 'acme', 'title': 'Build'},
      ],
      'workshopRooms': [
        {
          'id': 'mobile',
          'name': 'Mobile app',
          'color': 'violet',
          'repositories': ['acme/app'],
          'projectId': 'project-1',
          'permissionProfile': 'repository-maintainer',
        },
      ],
    });

    expect(workspace.resolvedWorkshopRooms.single.name, 'Mobile app');
    expect(
      workspace.resolvedWorkshopRooms.single.toJson(),
      workspace.workshopRooms.single.toJson(),
    );
  });

  test('legacy workspace gets one usable room without a migration', () {
    const workspace = WorkspaceModel(
      id: 'workspace-1',
      name: 'Example',
      environment: 'dev',
      githubInstallationId: 1,
      repositories: ['acme/app', 'acme/api'],
      projects: [
        ProjectConnection(
          id: 'project-1',
          number: 1,
          owner: 'acme',
          title: 'Build',
        ),
      ],
      workflows: [],
      artifactStorage: null,
    );

    final room = workspace.resolvedWorkshopRooms.single;
    expect(room.id, 'main');
    expect(room.repositories, ['acme/app', 'acme/api']);
    expect(room.permissionProfile, 'repository-maintainer');
  });

  test('unknown stored colour falls back to the verified identity palette', () {
    final room = WorkshopRoomModel.fromJson({
      'id': 'mobile',
      'name': 'Mobile app',
      'color': '#123456',
      'repositories': ['acme/app'],
      'projectId': 'project-1',
      'permissionProfile': 'repository-maintainer',
    });

    expect(room.color, 'cyan');
  });
}
