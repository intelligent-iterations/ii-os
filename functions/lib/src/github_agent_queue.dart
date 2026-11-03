part of 'github_client.dart';

extension GitHubAgentQueue on GitHubClient {
  Future<Map<String, Object?>> readAgentQueueProjectItem(
    Workspace workspace, {
    String? repository,
    required String projectId,
    required String itemId,
  }) async {
    if (repository != null) _requireRepository(workspace, repository);
    if (!workspace.containsProject(projectId) || itemId.isEmpty) {
      throw const ApiError(
        400,
        'project_not_allowed',
        'Project item is not configured for this workspace.',
      );
    }
    _requireGitHubProjectPermission(workspace, level: 'read');
    _requireGitHubIssuePermission(workspace, level: 'read');
    final data = await _graphql(
      workspace,
      r'''
        query AgentQueueItem($id: ID!) {
          node(id: $id) {
            ... on ProjectV2Item {
              id
              isArchived
              updatedAt
              project { id }
              content {
                __typename
                ... on Issue {
                  id number title body state url updatedAt
                  repository { databaseId nameWithOwner }
                }
              }
              fieldValues(first: 30) {
                nodes {
                  __typename
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    optionId name
                    field {
                      ... on ProjectV2SingleSelectField { id name }
                    }
                  }
                }
              }
            }
          }
        }
      ''',
      {'id': itemId},
      repository: repository,
    );
    final item = data['node'];
    final project = item is Map<String, Object?> ? item['project'] : null;
    if (item is! Map<String, Object?> ||
        item['id'] != itemId ||
        project is! Map<String, Object?> ||
        project['id'] != projectId) {
      throw const ApiError(
        404,
        'agent_ticket_not_found',
        'The current Project ticket could not be verified.',
      );
    }
    if (repository != null) {
      final content = item['content'];
      final actual = content is Map<String, Object?>
          ? content['repository']
          : null;
      if (actual is! Map<String, Object?> ||
          actual['nameWithOwner'] != repository) {
        throw const ApiError(
          409,
          'agent_ticket_repository_mismatch',
          'The Project ticket does not belong to the selected repository.',
        );
      }
    }
    return item;
  }

  Future<Map<String, Object?>> readAgentQueueProject(
    Workspace workspace,
    String projectId, {
    String? repository,
  }) async {
    if (repository != null) _requireRepository(workspace, repository);
    if (!workspace.containsProject(projectId)) {
      throw const ApiError(
        400,
        'project_not_allowed',
        'Project is not configured for this workspace.',
      );
    }
    _requireGitHubProjectPermission(workspace, level: 'read');
    _requireGitHubIssuePermission(workspace, level: 'read');
    Map<String, Object?>? project;
    final items = <Object?>[];
    String? cursor;
    do {
      final data = await _graphql(
        workspace,
        r'''
          query AgentQueue($id: ID!, $cursor: String) {
            node(id: $id) {
              ... on ProjectV2 {
                id
                title
                fields(first: 50) {
                  nodes {
                    __typename
                    ... on ProjectV2SingleSelectField {
                      id name options { id name }
                    }
                  }
                }
                items(first: 100, after: $cursor) {
                  pageInfo { hasNextPage endCursor }
                  nodes {
                    id
                    isArchived
                    content {
                      __typename
                      ... on Issue {
                        id number title body state url
                        repository { databaseId nameWithOwner }
                      }
                    }
                    fieldValues(first: 30) {
                      nodes {
                        __typename
                        ... on ProjectV2ItemFieldSingleSelectValue {
                          optionId name
                          field {
                            ... on ProjectV2SingleSelectField { id name }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        ''',
        {'id': projectId, 'cursor': cursor},
        repository: repository,
      );
      final node = data['node'];
      if (node is! Map<String, Object?> ||
          (repository != null && node['id'] != projectId)) {
        throw const ApiError(
          404,
          'project_not_found',
          'GitHub Project not found.',
        );
      }
      project ??= node;
      final connection = node['items'];
      if (connection is! Map<String, Object?>) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub returned invalid Project items.',
        );
      }
      final nodes = connection['nodes'];
      if (nodes is List<Object?>) items.addAll(nodes);
      final pageInfo = connection['pageInfo'];
      final hasNext =
          pageInfo is Map<String, Object?> && pageInfo['hasNextPage'] == true;
      cursor = hasNext ? pageInfo['endCursor'] as String? : null;
      if (hasNext && (cursor == null || cursor.isEmpty)) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub omitted the next Project page cursor.',
        );
      }
    } while (cursor != null);

    return {
      ...project,
      'items': {'nodes': items},
    };
  }
}
