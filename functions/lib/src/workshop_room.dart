import 'api_error.dart';

const workshopRoomColors = <String>{
  'violet',
  'plum',
  'indigo',
  'cyan',
  'slate',
  'moss',
};

final class WorkshopRoomConfig {
  const WorkshopRoomConfig({
    required this.id,
    required this.name,
    required this.color,
    required this.repositories,
    required this.projectId,
    required this.permissionProfile,
  });

  factory WorkshopRoomConfig.fromJson(Map<String, Object?> json) =>
      WorkshopRoomConfig(
        id: _requiredString(json['id'], 'room id'),
        name: _requiredString(json['name'], 'room name'),
        color: _requiredString(json['color'], 'room color'),
        repositories: _stringList(json['repositories']),
        projectId: _requiredString(json['projectId'], 'room project'),
        permissionProfile: _requiredString(
          json['permissionProfile'],
          'room permission profile',
        ),
      );

  final String id;
  final String name;
  final String color;
  final List<String> repositories;
  final String projectId;
  final String permissionProfile;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'repositories': repositories,
    'projectId': projectId,
    'permissionProfile': permissionProfile,
  };
}

List<WorkshopRoomConfig> parseWorkshopRooms(Object? value) {
  if (value is! List<Object?>) return const [];
  return value
      .whereType<Map<Object?, Object?>>()
      .map((room) => WorkshopRoomConfig.fromJson(room.cast<String, Object?>()))
      .toList();
}

List<WorkshopRoomConfig> validatedWorkshopRooms(
  Object? value, {
  required Set<String> workspaceRepositories,
  required Set<String> workspaceProjects,
}) {
  if (value is! List<Object?> || value.length > 24) {
    throw const ApiError(
      400,
      'invalid_workshop_rooms',
      'Workshop rooms must be a bounded list.',
    );
  }
  final rooms = <WorkshopRoomConfig>[];
  final ids = <String>{};
  for (final raw in value) {
    if (raw is! Map) {
      throw const ApiError(
        400,
        'invalid_workshop_rooms',
        'A workshop room is invalid.',
      );
    }
    final room = WorkshopRoomConfig.fromJson(raw.cast<String, Object?>());
    final valid =
        _roomId.hasMatch(room.id) &&
        room.name.length <= 60 &&
        workshopRoomColors.contains(room.color) &&
        room.repositories.isNotEmpty &&
        room.repositories.length <= 20 &&
        room.repositories.every(workspaceRepositories.contains) &&
        workspaceProjects.contains(room.projectId) &&
        _permissionProfile.hasMatch(room.permissionProfile) &&
        ids.add(room.id);
    if (!valid) {
      throw const ApiError(
        400,
        'invalid_workshop_rooms',
        'Each room needs a unique name, color, Project, repositories, and permission profile from this workspace.',
      );
    }
    rooms.add(room);
  }
  return rooms;
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw ApiError(400, 'invalid_workshop_rooms', 'A $field is required.');
  }
  return value.trim();
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) return const [];
  return value
      .whereType<String>()
      .map((value) => value.trim())
      .toSet()
      .toList();
}

final _roomId = RegExp(r'^[a-z0-9][a-z0-9-]{0,47}$');
final _permissionProfile = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
