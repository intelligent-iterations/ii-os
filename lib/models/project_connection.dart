/// One GitHub Project connection visible inside a workspace.
final class ProjectConnection {
  const ProjectConnection({
    required this.id,
    required this.number,
    required this.owner,
    required this.title,
  });

  factory ProjectConnection.fromJson(Map<String, Object?> json) =>
      ProjectConnection(
        id: json['id'] as String? ?? '',
        number: (json['number'] as num?)?.toInt() ?? 0,
        owner: json['owner'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );

  final String id;
  final int number;
  final String owner;
  final String title;

  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'owner': owner,
    'title': title,
  };
}
