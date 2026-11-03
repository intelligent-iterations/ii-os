const workshopRoomColors = <String>{
  'violet',
  'plum',
  'indigo',
  'cyan',
  'slate',
  'moss',
};

final class WorkshopRoomModel {
  const WorkshopRoomModel({
    required this.id,
    required this.name,
    required this.color,
    required this.repositories,
    required this.projectId,
    required this.permissionProfile,
  });

  factory WorkshopRoomModel.fromJson(Map<String, Object?> json) =>
      WorkshopRoomModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        color: workshopRoomColors.contains(json['color'])
            ? json['color']! as String
            : 'cyan',
        repositories: switch (json['repositories']) {
          final List<Object?> values => values.whereType<String>().toList(),
          _ => const [],
        },
        projectId: json['projectId'] as String? ?? '',
        permissionProfile:
            json['permissionProfile'] as String? ?? 'repository-maintainer',
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

  WorkshopRoomModel copyWith({
    String? id,
    String? name,
    String? color,
    List<String>? repositories,
    String? projectId,
    String? permissionProfile,
  }) => WorkshopRoomModel(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    repositories: repositories ?? this.repositories,
    projectId: projectId ?? this.projectId,
    permissionProfile: permissionProfile ?? this.permissionProfile,
  );
}
