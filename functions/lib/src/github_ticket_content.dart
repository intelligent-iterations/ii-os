part of 'github_client.dart';

Map<String, Object?> _normalizeProjectTickets(Map<String, Object?> project) {
  final items = project['items'];
  if (items is! Map<String, Object?>) return project;
  final nodes = items['nodes'];
  if (nodes is! List<Object?>) return project;
  final normalizedNodes = nodes.map((rawItem) {
    if (rawItem is! Map<String, Object?>) return rawItem;
    final content = rawItem['content'];
    if (content is! Map<String, Object?> || content['__typename'] != 'Issue') {
      return rawItem;
    }
    return {
      ...rawItem,
      'content': {
        ...content,
        'ticket': TicketContent.parse(content['body']).toJson(),
      },
    };
  }).toList();
  return {
    ...project,
    'items': {...items, 'nodes': normalizedNodes},
  };
}
