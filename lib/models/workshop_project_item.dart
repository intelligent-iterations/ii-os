import 'models.dart';

/// Combines the last Project response with tickets created in this session.
///
/// GitHub may briefly return a Project snapshot from before the create
/// mutation. Keeping the created item until that snapshot includes the same
/// id makes the successful mutation visible immediately without polling or an
/// additional provider read.
List<JsonMap> workshopProjectItemsWithCreatedCache(
  List<JsonMap> projectItems,
  Map<String, JsonMap> createdItems,
) {
  final projectItemIds = projectItems
      .map((item) => item['id'])
      .whereType<String>()
      .toSet();
  return [
    ...projectItems,
    ...createdItems.entries
        .where((entry) => !projectItemIds.contains(entry.key))
        .map((entry) => entry.value),
  ];
}

JsonMap workshopProjectItemFromCreatedIssue(
  JsonMap issue, {
  required String repository,
  String? statusFieldId,
  String? statusOptionId,
  String statusName = '',
}) {
  final itemId = issue['projectItemId'] as String?;
  if (itemId == null || itemId.isEmpty) return const {};
  return {
    'id': itemId,
    'fieldValues': {
      'nodes': [
        if (statusFieldId != null && statusOptionId != null)
          {
            'field': {'id': statusFieldId},
            'name': statusName,
            'optionId': statusOptionId,
          },
      ],
    },
    'content': {
      '__typename': 'Issue',
      'id': issue['id'],
      'number': issue['number'],
      'title': issue['title'],
      'state': issue['state'],
      'url': issue['url'],
      'repository': {'nameWithOwner': repository},
      'ticket': {
        'definitionOfDone': issue['definitionOfDone'],
        'howToTest': issue['howToTest'],
        'permissions': issue['permissions'],
        'context': issue['context'],
        'structured': issue['structured'],
      },
    },
  };
}
