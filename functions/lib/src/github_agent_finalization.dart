part of 'github_client.dart';

extension GitHubAgentFinalization on GitHubClient {
  Future<String> agentBrokerBotLogin() => _transport.appBotLogin();

  Future<GitHubInstallationToken> issueAgentBranchWriterToken(
    Workspace workspace, {
    required String repository,
    required int repositoryId,
  }) {
    _requireRepository(workspace, repository);
    return _transport.issueRepositoryContentsWriterToken(
      workspace,
      repository: repository,
      repositoryId: repositoryId,
    );
  }

  Future<String> ensureAgentPullRequest(
    Workspace workspace, {
    required String repository,
    required int issueNumber,
    required String issueTitle,
    required String head,
    required String base,
    required String headSha,
    required String baseSha,
  }) async {
    _requireRepository(workspace, repository);
    if (issueNumber <= 0 ||
        issueTitle.trim().isEmpty ||
        base != 'dev' ||
        !RegExp(r'^ii-os-agent/[0-9a-f]{32}$').hasMatch(head) ||
        !_gitSha.hasMatch(headSha) ||
        !_gitSha.hasMatch(baseSha)) {
      throw const ApiError(
        400,
        'agent_pull_request_invalid',
        'The bounded pull request intent is invalid.',
      );
    }
    await _requireAgentRefSha(
      workspace,
      repository: repository,
      ref: head,
      expectedSha: headSha,
    );
    await _requireAgentRefSha(
      workspace,
      repository: repository,
      ref: base,
      expectedSha: baseSha,
    );
    final permissions = await _transport.installationPermissions(
      workspace,
      repository: repository,
    );
    if (!_permissionAllows(permissions['pull_requests'] ?? 'none', 'write')) {
      throw const ApiError(
        409,
        'github_pull_requests_permission_required',
        'The ii-os GitHub App needs Pull requests read and write permission. This server-side authority is never injected into an agent.',
      );
    }
    final existing = await _exactAgentPullRequests(
      workspace,
      repository: repository,
      head: head,
      base: base,
      headSha: headSha,
      baseSha: baseSha,
    );
    if (existing.length == 1) return existing.single;
    try {
      final response = _asMap(
        await _rest(
          workspace,
          'POST',
          '/repos/$repository/pulls',
          body: {
            'title': agentPullRequestTitle(issueTitle, issueNumber),
            'head': head,
            'base': base,
            'body': agentPullRequestBody(issueNumber),
          },
        ),
      );
      return _validatedAgentPullRequest(
        response,
        repository: repository,
        head: head,
        base: base,
        headSha: headSha,
        baseSha: baseSha,
      );
    } on ApiError catch (error) {
      final details = error.details;
      final githubStatus = details is Map ? details['githubStatus'] : null;
      if (githubStatus != 422) rethrow;
      final raced = await _exactAgentPullRequests(
        workspace,
        repository: repository,
        head: head,
        base: base,
        headSha: headSha,
        baseSha: baseSha,
      );
      if (raced.length == 1) return raced.single;
      rethrow;
    }
  }

  Future<List<String>> _exactAgentPullRequests(
    Workspace workspace, {
    required String repository,
    required String head,
    required String base,
    required String headSha,
    required String baseSha,
  }) async {
    final owner = repository.split('/').first;
    final query = Uri(
      queryParameters: {
        'state': 'open',
        'head': '$owner:$head',
        'base': base,
        'per_page': '2',
      },
    ).query;
    final response = await _rest(
      workspace,
      'GET',
      '/repos/$repository/pulls?$query',
    );
    if (response is! List<Object?> || response.length > 1) {
      throw const ApiError(
        409,
        'agent_pull_request_ambiguous',
        'The exact agent branch has an ambiguous pull request.',
      );
    }
    final pulls = <String>[];
    for (final value in response) {
      if (value is! Map<String, Object?>) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub returned invalid pull request data.',
        );
      }
      pulls.add(
        _validatedAgentPullRequest(
          value,
          repository: repository,
          head: head,
          base: base,
          headSha: headSha,
          baseSha: baseSha,
        ),
      );
    }
    return pulls;
  }

  Future<void> _requireAgentRefSha(
    Workspace workspace, {
    required String repository,
    required String ref,
    required String expectedSha,
  }) async {
    final encoded = Uri.encodeComponent('heads/$ref');
    final response = _asMap(
      await _rest(workspace, 'GET', '/repos/$repository/git/ref/$encoded'),
    );
    final object = response['object'];
    if (response['ref'] != 'refs/heads/$ref' ||
        object is! Map<String, Object?> ||
        object['type'] != 'commit' ||
        object['sha'] != expectedSha) {
      throw const ApiError(
        409,
        'agent_pull_request_ref_changed',
        'The exact reviewed agent or base commit changed before finalization.',
      );
    }
  }
}

/// Builds a descriptive, bounded PR title from the immutable ticket snapshot.
///
/// GitHub issue titles are already human-written summaries. Reusing that
/// trusted title avoids asking the worker to supply mutable PR metadata while
/// preserving the issue number for traceability.
String agentPullRequestTitle(String issueTitle, int issueNumber) {
  final normalized = issueTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
  final suffix = ' (#$issueNumber)';
  const maximumLength = 256;
  final availableRunes = maximumLength - suffix.runes.length;
  final titleRunes = normalized.runes.toList();
  final bounded = titleRunes.length <= availableRunes
      ? normalized
      : String.fromCharCodes(titleRunes.take(availableRunes));
  return '$bounded$suffix';
}

String agentPullRequestBody(int issueNumber) =>
    'Automated repository work for #$issueNumber.\n\n'
    'ii-os created this pull request only after the exact agent runtime was '
    'cleaned and its bounded result was verified. '
    'Human QA is required before completion.';

String _validatedAgentPullRequest(
  Map<String, Object?> pull, {
  required String repository,
  required String head,
  required String base,
  required String headSha,
  required String baseSha,
}) {
  final headData = pull['head'];
  final baseData = pull['base'];
  final url = pull['html_url'];
  final headRepository = headData is Map<String, Object?>
      ? headData['repo']
      : null;
  final baseRepository = baseData is Map<String, Object?>
      ? baseData['repo']
      : null;
  if (headData is! Map<String, Object?> ||
      baseData is! Map<String, Object?> ||
      headRepository is! Map<String, Object?> ||
      baseRepository is! Map<String, Object?> ||
      headData['ref'] != head ||
      headData['sha'] != headSha ||
      headRepository['full_name'] != repository ||
      baseData['ref'] != base ||
      baseData['sha'] != baseSha ||
      baseRepository['full_name'] != repository ||
      url is! String ||
      !url.startsWith('https://github.com/$repository/pull/')) {
    throw const ApiError(
      502,
      'github_response_invalid',
      'GitHub returned an invalid pull request identity.',
    );
  }
  return url;
}

final _gitSha = RegExp(r'^[0-9a-f]{40}$');
