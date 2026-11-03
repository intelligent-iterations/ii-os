part of 'github_client.dart';

void _requireScopedGitHubPermission(
  Workspace workspace, {
  required String name,
  required String codeName,
  required String label,
  required String level,
}) {
  if (!workspace.usesOrganizationResourceGrants) return;
  final accepted = level == 'read'
      ? {'$name:read', '$name:write'}
      : {'$name:write'};
  final resource = workspace.primaryGitHubResource;
  if (resource == null ||
      resource.permissionEnvelope.intersection(accepted).isEmpty) {
    final requiredLabel = level == 'write' ? 'Read and write' : 'Read-only';
    throw ApiError(
      409,
      'github_app_${codeName}_permission_required',
      'The connected GitHub App does not include $label access. An '
          'Organization Admin must set it to $requiredLabel, approve the '
          'installation update, reconnect the GCP project in Organization '
          'resources, and grant it in Workspace access.',
    );
  }
  final grant = workspace.primaryGitHubGrant;
  if (grant == null || grant.permissions.intersection(accepted).isEmpty) {
    final requiredLabel = level == 'write'
        ? 'read and write'
        : 'read-only or read and write';
    throw ApiError(
      403,
      'workspace_github_${codeName}_permission_required',
      'Grant $label $requiredLabel in Workspace access before using this '
          'GitHub resource.',
    );
  }
}

void _requireGitHubProjectPermission(
  Workspace workspace, {
  required String level,
}) => _requireScopedGitHubPermission(
  workspace,
  name: 'organization_projects',
  codeName: 'projects',
  label: 'Organization Projects',
  level: level,
);

void _requireGitHubIssuePermission(
  Workspace workspace, {
  required String level,
}) => _requireScopedGitHubPermission(
  workspace,
  name: 'issues',
  codeName: 'issues',
  label: 'Issues',
  level: level,
);

extension GitHubProjects on GitHubClient {
  Future<Map<String, Object?>> getProject(
    Workspace workspace,
    String projectId, {
    String? repository,
  }) async {
    if (!workspace.containsProject(projectId)) {
      throw const ApiError(
        400,
        'project_not_allowed',
        'Project is not configured for this workspace.',
      );
    }
    if (repository != null) _requireRepository(workspace, repository);
    _requireGitHubProjectPermission(workspace, level: 'read');
    _requireGitHubIssuePermission(workspace, level: 'read');
    final data = await _graphql(
      workspace,
      r'''
        query Project($id: ID!) {
          node(id: $id) {
            ... on ProjectV2 {
              id
              title
              url
              fields(first: 50) {
                nodes {
                  __typename
                  ... on ProjectV2Field { id name dataType }
                  ... on ProjectV2SingleSelectField { id name options { id name color description } }
                  ... on ProjectV2IterationField { id name }
                }
              }
              items(first: 100) {
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
                        field { ... on ProjectV2SingleSelectField { id name } }
                      }
                      ... on ProjectV2ItemFieldTextValue {
                        text
                        field { ... on ProjectV2Field { id name } }
                      }
                      ... on ProjectV2ItemFieldNumberValue {
                        number
                        field { ... on ProjectV2Field { id name } }
                      }
                      ... on ProjectV2ItemFieldDateValue {
                        date
                        field { ... on ProjectV2Field { id name } }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      ''',
      {'id': projectId},
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
    return _normalizeProjectTickets(node);
  }

  /// Lists the open GitHub Projects already linked to one allowed repository.
  ///
  /// The picker is deliberately bounded to one repository and one page. A
  /// person chooses the repository first, then sees at most 50 relevant
  /// Projects instead of entering owner, number, title, and node id by hand.
  Future<List<Map<String, Object?>>> listLinkedProjects(
    Workspace workspace,
    String repository,
  ) async {
    _requireRepository(workspace, repository);
    _requireGitHubProjectPermission(workspace, level: 'read');
    final parts = repository.split('/');
    final data = await _graphql(
      workspace,
      r'''
        query LinkedProjects($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            projectsV2(
              first: 50
              orderBy: {field: UPDATED_AT, direction: DESC}
            ) {
              nodes { id number title url closed }
            }
          }
        }
      ''',
      {'owner': parts.first, 'name': parts.last},
    );
    return parseLinkedGitHubProjects(
      data,
      owner: parts.first,
    ).map((project) => project.toJson()).toList(growable: false);
  }

  Future<Map<String, Object?>> updateProjectItemField(
    Workspace workspace, {
    String? repository,
    required String projectId,
    required String itemId,
    required String fieldId,
    required Map<String, Object?> value,
  }) async {
    if (repository != null) _requireRepository(workspace, repository);
    if (!workspace.containsProject(projectId)) {
      throw const ApiError(
        400,
        'project_not_allowed',
        'Project is not configured for this workspace.',
      );
    }
    _requireGitHubProjectPermission(workspace, level: 'write');
    final allowedKeys = {
      'text',
      'number',
      'date',
      'singleSelectOptionId',
      'iterationId',
    };
    if (value.length != 1 || !allowedKeys.contains(value.keys.single)) {
      throw const ApiError(
        400,
        'invalid_field_value',
        'Project field value is invalid.',
      );
    }
    return _graphql(
      workspace,
      r'''
        mutation UpdateField(
          $projectId: ID!, $itemId: ID!, $fieldId: ID!,
          $value: ProjectV2FieldValue!
        ) {
          updateProjectV2ItemFieldValue(input: {
            projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: $value
          }) { projectV2Item { id updatedAt } }
        }
      ''',
      {
        'projectId': projectId,
        'itemId': itemId,
        'fieldId': fieldId,
        'value': value,
      },
      repository: repository,
    );
  }

  Future<Map<String, Object?>> clearProjectItemField(
    Workspace workspace, {
    String? repository,
    required String projectId,
    required String itemId,
    required String fieldId,
  }) async {
    if (repository != null) _requireRepository(workspace, repository);
    if (!workspace.containsProject(projectId) ||
        itemId.isEmpty ||
        fieldId.isEmpty) {
      throw const ApiError(
        400,
        'project_not_allowed',
        'Project item is not configured for this workspace.',
      );
    }
    _requireGitHubProjectPermission(workspace, level: 'write');
    return _graphql(
      workspace,
      r'''
        mutation ClearField($projectId: ID!, $itemId: ID!, $fieldId: ID!) {
          clearProjectV2ItemFieldValue(input: {
            projectId: $projectId, itemId: $itemId, fieldId: $fieldId
          }) { projectV2Item { id updatedAt } }
        }
      ''',
      {'projectId': projectId, 'itemId': itemId, 'fieldId': fieldId},
      repository: repository,
    );
  }

  Future<Map<String, Object?>> updateProjectFieldOptions(
    Workspace workspace, {
    required String projectId,
    required String fieldId,
    required List<Map<String, Object?>> options,
  }) async {
    if (!workspace.containsProject(projectId)) {
      throw const ApiError(
        400,
        'project_not_allowed',
        'Project is not configured for this workspace.',
      );
    }
    _requireGitHubProjectPermission(workspace, level: 'write');
    if (options.isEmpty || options.length > 20) {
      throw const ApiError(
        400,
        'invalid_status_options',
        'Provide between 1 and 20 status options.',
      );
    }
    const colors = {
      'BLUE',
      'GRAY',
      'GREEN',
      'ORANGE',
      'PINK',
      'PURPLE',
      'RED',
      'YELLOW',
    };
    final normalized = <Map<String, Object?>>[];
    for (final option in options) {
      final name = option['name'];
      final color = option['color'];
      final description = option['description'];
      if (name is! String || name.trim().isEmpty || name.length > 50) {
        throw const ApiError(
          400,
          'invalid_status_options',
          'Every status needs a short name.',
        );
      }
      if (color is! String || !colors.contains(color)) {
        throw const ApiError(
          400,
          'invalid_status_options',
          'A status color is invalid.',
        );
      }
      normalized.add({
        'name': name.trim(),
        'color': color,
        'description': description is String ? description.trim() : '',
      });
    }
    return _graphql(
      workspace,
      r'''
        mutation UpdateOptions($fieldId: ID!, $options: [ProjectV2SingleSelectFieldOptionInput!]) {
          updateProjectV2Field(input: {fieldId: $fieldId, singleSelectOptions: $options}) {
            projectV2Field {
              ... on ProjectV2SingleSelectField { id name options { id name color description } }
            }
          }
        }
      ''',
      {'fieldId': fieldId, 'options': normalized},
    );
  }
}
