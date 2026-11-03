import 'models.dart';
import 'workshop_room.dart';

extension WorkshopRoomsForWorkspace on WorkspaceModel {
  List<WorkshopRoomModel> get resolvedWorkshopRooms {
    final valid = workshopRooms
        .where(
          (room) =>
              room.repositories.any(repositories.contains) &&
              projects.any((project) => project.id == room.projectId),
        )
        .toList(growable: false);
    if (valid.isNotEmpty) return valid;
    final project = projects.firstOrNull;
    if (repositories.isEmpty || project == null) return const [];
    return [
      WorkshopRoomModel(
        id: 'main',
        name: 'Main room',
        color: 'cyan',
        repositories: repositories,
        projectId: project.id,
        permissionProfile: 'repository-maintainer',
      ),
    ];
  }
}

extension _FirstWorkshopRoomOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
