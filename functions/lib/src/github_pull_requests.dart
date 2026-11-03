part of 'github_client.dart';

extension GitHubPullRequests on GitHubClient {
  Future<Map<String, Object?>> getPullRequest(
    Workspace workspace, {
    required String repository,
    required int number,
  }) async {
    _requirePullRequestIdentity(workspace, repository, number);
    final response = _asMap(
      await _rest(workspace, 'GET', '/repos/$repository/pulls/$number'),
    );
    String? resolvedMergeCommitSha;
    if (response['merged'] == true && response['merge_commit_sha'] == null) {
      final parts = repository.split('/');
      resolvedMergeCommitSha = mergeCommitShaFromPullRequestGraphql(
        await _graphql(
          workspace,
          r'''
            query PullRequestMergeCommit(
              $owner: String!, $name: String!, $number: Int!
            ) {
              repository(owner: $owner, name: $name) {
                nameWithOwner
                pullRequest(number: $number) {
                  number url merged
                  mergeCommit { oid }
                }
              }
            }
          ''',
          {'owner': parts.first, 'name': parts.last, 'number': number},
          repository: repository,
        ),
        repository: repository,
        number: number,
      );
    }
    return normalizePullRequestResponse(
      response,
      repository: repository,
      number: number,
      resolvedMergeCommitSha: resolvedMergeCommitSha,
    );
  }

  /// Merges the exact agent PR only if its reviewed head has not moved.
  ///
  /// The signed-in ii-os member supplies the approval. The workspace GitHub
  /// App performs the bounded merge and GitHub remains authoritative for
  /// branch protection, checks, and repository merge settings.
  Future<Map<String, Object?>> mergeAgentPullRequest(
    Workspace workspace, {
    required String repository,
    required int number,
    required String expectedHeadSha,
  }) async {
    if (!_gitSha.hasMatch(expectedHeadSha)) {
      throw const ApiError(
        400,
        'pull_request_head_invalid',
        'Refresh the pull request before approving it.',
      );
    }
    final pull = await getPullRequest(
      workspace,
      repository: repository,
      number: number,
    );
    requireMergeableAgentPullRequest(pull, expectedHeadSha: expectedHeadSha);
    final permissions = await _transport.installationPermissions(
      workspace,
      repository: repository,
    );
    if (!_permissionAllows(permissions['contents'] ?? 'none', 'write') ||
        !_permissionAllows(permissions['pull_requests'] ?? 'none', 'write')) {
      throw const ApiError(
        409,
        'github_merge_permission_required',
        'The ii-os GitHub App needs Contents and Pull requests read and write permission to merge.',
      );
    }
    final repositoryData = _asMap(
      await _rest(workspace, 'GET', '/repos/$repository'),
    );
    final mergeMethod = preferredPullRequestMergeMethod(repositoryData);
    if (mergeMethod == null) {
      throw const ApiError(
        409,
        'pull_request_merge_method_unavailable',
        'Enable a pull request merge method in the GitHub repository settings.',
      );
    }
    final result = _asMap(
      await _rest(
        workspace,
        'PUT',
        '/repos/$repository/pulls/$number/merge',
        body: {'sha': expectedHeadSha, 'merge_method': mergeMethod},
      ),
    );
    if (result['merged'] != true || result['sha'] is! String) {
      throw ApiError(
        409,
        'pull_request_not_mergeable',
        result['message'] as String? ??
            'GitHub has not made this pull request mergeable yet.',
      );
    }
    return {
      ...pull,
      'state': 'closed',
      'merged': true,
      'mergeCommitSha': result['sha'],
      'mergeMethod': mergeMethod,
      'qaDeployment': qaDeploymentNotFound(
        sha: result['sha']! as String,
        environment: 'dev',
      ),
    };
  }

  void _requirePullRequestIdentity(
    Workspace workspace,
    String repository,
    int number,
  ) {
    _requireRepository(workspace, repository);
    if (number <= 0) {
      throw const ApiError(
        400,
        'pull_request_invalid',
        'The pull request number is invalid.',
      );
    }
  }
}

void requireMergeableAgentPullRequest(
  Map<String, Object?> pull, {
  required String expectedHeadSha,
}) {
  if (!_gitSha.hasMatch(expectedHeadSha) ||
      pull['state'] != 'open' ||
      pull['draft'] == true ||
      pull['merged'] == true ||
      pull['baseRef'] != 'dev' ||
      pull['headSha'] != expectedHeadSha ||
      !(pull['headRef'] as String? ?? '').startsWith('ii-os-agent/')) {
    throw const ApiError(
      409,
      'pull_request_changed',
      'This pull request changed or is no longer ready. Refresh it before approving and merging.',
    );
  }
}

String? preferredPullRequestMergeMethod(Map<String, Object?> repository) =>
    repository['allow_merge_commit'] == true
    ? 'merge'
    : repository['allow_squash_merge'] == true
    ? 'squash'
    : repository['allow_rebase_merge'] == true
    ? 'rebase'
    : null;

Map<String, Object?> normalizePullRequestResponse(
  Map<String, Object?> value, {
  required String repository,
  required int number,
  String? resolvedMergeCommitSha,
}) {
  final head = value['head'];
  final base = value['base'];
  final headRepository = head is Map<String, Object?> ? head['repo'] : null;
  final baseRepository = base is Map<String, Object?> ? base['repo'] : null;
  final url = value['html_url'];
  final mergeCommitSha = value['merge_commit_sha'] ?? resolvedMergeCommitSha;
  final merged = value['merged'] == true;
  final headRef = head is Map<String, Object?> ? head['ref'] : null;
  final headRepositoryMatches =
      headRepository is Map<String, Object?> &&
      headRepository['full_name'] == repository;
  final cleanedMergedAgentHead =
      merged &&
      headRepository == null &&
      headRef is String &&
      headRef.startsWith('ii-os-agent/');
  if (value['number'] != number ||
      head is! Map<String, Object?> ||
      base is! Map<String, Object?> ||
      baseRepository is! Map<String, Object?> ||
      (!headRepositoryMatches && !cleanedMergedAgentHead) ||
      baseRepository['full_name'] != repository ||
      head['sha'] is! String ||
      !_gitSha.hasMatch(head['sha']! as String) ||
      base['sha'] is! String ||
      !_gitSha.hasMatch(base['sha']! as String) ||
      (merged &&
          (mergeCommitSha is! String || !_gitSha.hasMatch(mergeCommitSha))) ||
      url != 'https://github.com/$repository/pull/$number') {
    throw const ApiError(
      502,
      'github_response_invalid',
      'GitHub returned an invalid pull request identity.',
    );
  }
  return {
    'repository': repository,
    'number': number,
    'title': value['title'] as String? ?? 'Pull request #$number',
    'url': url,
    'state': value['state'] as String? ?? '',
    'draft': value['draft'] == true,
    'merged': merged,
    'mergeable': value['mergeable'],
    'mergeableState': value['mergeable_state'] as String? ?? '',
    'headRef': head['ref'] as String? ?? '',
    'headSha': head['sha'],
    'baseRef': base['ref'] as String? ?? '',
    'baseSha': base['sha'],
    if (value['merged'] == true) 'mergeCommitSha': mergeCommitSha,
  };
}

String mergeCommitShaFromPullRequestGraphql(
  Map<String, Object?> data, {
  required String repository,
  required int number,
}) {
  final repositoryData = data['repository'];
  final pullRequest = repositoryData is Map<String, Object?>
      ? repositoryData['pullRequest']
      : null;
  final mergeCommit = pullRequest is Map<String, Object?>
      ? pullRequest['mergeCommit']
      : null;
  final sha = mergeCommit is Map<String, Object?> ? mergeCommit['oid'] : null;
  if (repositoryData is! Map<String, Object?> ||
      repositoryData['nameWithOwner'] != repository ||
      pullRequest is! Map<String, Object?> ||
      pullRequest['number'] != number ||
      pullRequest['url'] != 'https://github.com/$repository/pull/$number' ||
      pullRequest['merged'] != true ||
      sha is! String ||
      !_gitSha.hasMatch(sha)) {
    throw const ApiError(
      502,
      'github_response_invalid',
      'GitHub returned an invalid pull request merge identity.',
    );
  }
  return sha;
}
