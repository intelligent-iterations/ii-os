part of 'github_client.dart';

extension GitHubCodexAuth on GitHubClient {
  /// Metadata only, using the existing explicitly selected repository access.
  Future<Map<String, Object?>> codexAuthSecretVersion(
    Workspace workspace, {
    required String repository,
  }) async {
    _requireRepository(workspace, repository);
    try {
      final metadata = _asMap(
        await _rest(
          workspace,
          'GET',
          '/repos/$repository/actions/secrets/CODEX_AUTH_JSON',
        ),
      );
      final updated = metadata['updated_at'];
      final timestamp = updated is String ? DateTime.tryParse(updated) : null;
      if (metadata['name'] != 'CODEX_AUTH_JSON' || timestamp?.isUtc != true) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub returned invalid credential version metadata.',
        );
      }
      return {'exists': true, 'secretUpdatedAt': timestamp!.toUtc()};
    } on ApiError catch (error) {
      if (error.code != 'github_resource_not_found') rethrow;
      return {'exists': false, 'secretUpdatedAt': null};
    }
  }

  Future<Map<String, Object?>> codexAuthRepositoryIdentity(
    Workspace workspace, {
    required String repository,
  }) async {
    _requireRepository(workspace, repository);
    final response = _asMap(
      await _rest(workspace, 'GET', '/repos/$repository'),
    );
    final id = (response['id'] as num?)?.toInt() ?? 0;
    if (id <= 0 || response['full_name'] != repository) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid repository identity.',
      );
    }
    return {'repository': repository, 'repositoryId': id};
  }

  Future<Map<String, Object?>> getCodexAuthWorkflowRun(
    Workspace workspace, {
    required String repository,
    required int runId,
  }) async {
    _requireRepository(workspace, repository);
    if (runId <= 0) {
      throw const ApiError(
        400,
        'github_workflow_run_invalid',
        'The GitHub workflow run ID is invalid.',
      );
    }
    return _asMap(
      await _rest(workspace, 'GET', '/repos/$repository/actions/runs/$runId'),
    );
  }

  Future<void> requireCodexAuthDispatchReady(
    Workspace workspace, {
    required String repository,
    required String trustedSourceRef,
  }) async {
    _requireRepository(workspace, repository);
    final permissions = await _transport.installationPermissions(
      workspace,
      repository: repository,
    );
    if (!_permissionAllows(permissions['actions'] ?? 'none', 'write')) {
      throw const ApiError(
        409,
        'github_actions_permission_required',
        'The GitHub App must have Actions read and write permission.',
      );
    }
    if (!_permissionAllows(permissions['secrets'] ?? 'none', 'write')) {
      throw const ApiError(
        409,
        'github_secrets_permission_required',
        'The GitHub App must have Secrets read and write permission.',
      );
    }
    final environment = await _environmentCheck(
      workspace,
      repository: repository,
      environment: iiOsAgentEnvironment,
      trustedSourceRef: trustedSourceRef,
    );
    if (environment['status'] != 'passed') {
      throw const ApiError(
        409,
        'codex_auth_environment_unprotected',
        'Protect the ii-os agent environment on dev before connecting Codex.',
      );
    }
    final workflows = await listRepositoryWorkflows(workspace, repository);
    final checks = repositoryWorkflowChecks(workflows, repository: repository);
    if (checks.any((check) => check['status'] != 'passed')) {
      throw const ApiError(
        409,
        'codex_auth_workflow_required',
        'Install and enable the ii-os agent and Codex verification workflows on dev.',
      );
    }
  }

  Future<GitHubInstallationToken> issueCodexSecretWriterToken(
    Workspace workspace, {
    required String repository,
    required int repositoryId,
  }) async {
    _requireRepository(workspace, repository);
    return _transport.issueRepositorySecretWriterToken(
      workspace,
      repository: repository,
      repositoryId: repositoryId,
    );
  }

  Future<List<Map<String, Object?>>> listIssueComments(
    Workspace workspace, {
    required String repository,
    required int number,
    DateTime? createdSince,
  }) async {
    _requireRepository(workspace, repository);
    if (number <= 0) {
      throw const ApiError(
        400,
        'invalid_issue_number',
        'The issue number must be positive.',
      );
    }
    final comments = <Map<String, Object?>>[];
    for (var page = 1; page <= 10; page++) {
      final query = <String, String>{
        'per_page': '100',
        'page': '$page',
        if (createdSince != null)
          'since': createdSince.toUtc().toIso8601String(),
      };
      final response = await _rest(
        workspace,
        'GET',
        '/repos/$repository/issues/$number/comments?${Uri(queryParameters: query).query}',
      );
      if (response is! List<Object?>) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub returned invalid issue comment data.',
        );
      }
      comments.addAll(response.whereType<Map<String, Object?>>());
      if (response.length < 100) return comments;
    }
    throw const ApiError(
      409,
      'github_issue_comments_ambiguous',
      'More than 1,000 comments were added during this agent run; ii-os cannot safely identify the latest result.',
    );
  }
}
