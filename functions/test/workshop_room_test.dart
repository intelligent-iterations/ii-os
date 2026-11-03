import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workshop_room.dart';
import 'package:test/test.dart';

void main() {
  const repositories = {'acme/app', 'acme/api'};
  const projects = {'project-1'};

  test('validates a room against workspace repositories and Projects', () {
    final rooms = validatedWorkshopRooms(
      [
        {
          'id': 'mobile',
          'name': 'Mobile app',
          'color': 'violet',
          'repositories': ['acme/app'],
          'projectId': 'project-1',
          'permissionProfile': 'repository-maintainer',
        },
      ],
      workspaceRepositories: repositories,
      workspaceProjects: projects,
    );

    expect(rooms.single.id, 'mobile');
    expect(rooms.single.repositories, ['acme/app']);
  });

  test('allows a room to default to no agent access', () {
    final rooms = validatedWorkshopRooms(
      [
        {
          'id': 'human-review',
          'name': 'Human review',
          'color': 'slate',
          'repositories': ['acme/app'],
          'projectId': 'project-1',
          'permissionProfile': 'none',
        },
      ],
      workspaceRepositories: repositories,
      workspaceProjects: projects,
    );

    expect(rooms.single.permissionProfile, 'none');
  });

  for (final invalid in <Map<String, Object?>>[
    {
      'id': 'mobile',
      'name': 'Mobile app',
      'color': 'green',
      'repositories': ['acme/app'],
      'projectId': 'project-1',
      'permissionProfile': 'repository-maintainer',
    },
    {
      'id': 'mobile',
      'name': 'Mobile app',
      'color': 'violet',
      'repositories': ['other/private'],
      'projectId': 'project-1',
      'permissionProfile': 'repository-maintainer',
    },
    {
      'id': 'mobile',
      'name': 'Mobile app',
      'color': 'violet',
      'repositories': ['acme/app'],
      'projectId': 'other-project',
      'permissionProfile': 'repository-maintainer',
    },
  ]) {
    test('rejects out-of-scope room setting ${invalid.keys}', () {
      expect(
        () => validatedWorkshopRooms(
          [invalid],
          workspaceRepositories: repositories,
          workspaceProjects: projects,
        ),
        throwsA(isA<ApiError>()),
      );
    });
  }

  test('rejects duplicate room ids', () {
    final room = {
      'id': 'mobile',
      'name': 'Mobile app',
      'color': 'violet',
      'repositories': ['acme/app'],
      'projectId': 'project-1',
      'permissionProfile': 'repository-maintainer',
    };
    expect(
      () => validatedWorkshopRooms(
        [
          room,
          {...room, 'name': 'Another room'},
        ],
        workspaceRepositories: repositories,
        workspaceProjects: projects,
      ),
      throwsA(isA<ApiError>()),
    );
  });
}
