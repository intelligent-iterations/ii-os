part of 'github_client.dart';

extension GitHubAgentReadinessHelpers on GitHubClient {
  Future<String> _trustedWorkflowSource(
    Workspace workspace, {
    required String repository,
    required String encodedRef,
    required String workflow,
    required Map<String, String> expectedBlobShas,
  }) async {
    final path = '.github/workflows/$workflow';
    final file = _asMap(
      await _rest(
        workspace,
        'GET',
        '/repos/$repository/contents/$path?ref=$encodedRef',
      ),
    );
    final content = file['content'];
    if (file['type'] != 'file' ||
        file['encoding'] != 'base64' ||
        content is! String ||
        file['sha'] != expectedBlobShas[path]) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an unreadable agent workflow.',
      );
    }
    return utf8.decode(base64Decode(content.replaceAll('\n', '')));
  }

  Future<(String, String, Map<String, Object?>)> _resolveTrustedAgentSource(
    Workspace workspace,
    String repository,
  ) async {
    final branch = _asMap(
      await _rest(
        workspace,
        'GET',
        '/repos/$repository/git/ref/${Uri.encodeComponent('heads/dev')}',
      ),
    );
    final branchObject = branch['object'];
    final sha = branchObject is Map<String, Object?>
        ? branchObject['sha'] as String? ?? ''
        : '';
    if (branch['ref'] != 'refs/heads/dev' ||
        branchObject is! Map<String, Object?> ||
        branchObject['type'] != 'commit' ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid dev commit identity.',
      );
    }
    final fallbackRef = 'ii-os-agent-v4-$sha';
    try {
      final exact = _asMap(
        await _rest(
          workspace,
          'GET',
          '/repos/$repository/git/ref/tags/${Uri.encodeComponent(fallbackRef)}',
        ),
      );
      final exactObject = exact['object'];
      if (exact['ref'] != 'refs/tags/$fallbackRef' ||
          exactObject is! Map<String, Object?> ||
          exactObject['type'] != 'commit' ||
          exactObject['sha'] != sha) {
        throw const ApiError(
          502,
          'github_response_invalid',
          'GitHub returned an invalid trusted agent tag.',
        );
      }
      return (
        sha,
        fallbackRef,
        readinessCheck(
          id: 'immutable_agent_source',
          label: 'Agent source tag is on the dev lineage',
          passed: true,
          repository: repository,
          detail: '$fallbackRef resolves to the current dev commit $sha.',
          guidance: '',
        ),
      );
    } on ApiError catch (error) {
      if (error.code != 'github_resource_not_found') rethrow;
    }

    var trustedRefsBySha = const <String, String>{};
    try {
      final response = await _rest(
        workspace,
        'GET',
        '/repos/$repository/git/matching-refs/tags/ii-os-agent-v4-?per_page=100',
      );
      trustedRefsBySha = trustedAgentSourceTags(response);
    } on ApiError catch (error) {
      if (error.code != 'github_resource_not_found') rethrow;
    }

    (String, String)? selected;
    // GitHub's matching-refs endpoint is not paginated and a repository can
    // accumulate hundreds of trusted tags. Comparing every tag to dev exhausts the
    // installation token's request budget. Walk dev history instead: one page
    // proves up to 100 commits are ancestors, and the first tagged commit is
    // the most recent trusted source in GitHub's history ordering.
    if (trustedRefsBySha.isNotEmpty) {
      const pageSize = 100;
      const maxPages = 100;
      for (var page = 1; page <= maxPages; page += 1) {
        final history = await _rest(
          workspace,
          'GET',
          '/repos/$repository/commits?sha=dev&per_page=$pageSize&page=$page',
        );
        if (history is! List<Object?> ||
            history.length > pageSize ||
            history.length !=
                history.whereType<Map<String, Object?>>().length) {
          throw const ApiError(
            502,
            'github_response_invalid',
            'GitHub returned invalid dev commit history.',
          );
        }
        for (final commit in history.whereType<Map<String, Object?>>()) {
          final candidateSha = commit['sha'];
          if (candidateSha is! String ||
              !RegExp(r'^[0-9a-f]{40}$').hasMatch(candidateSha)) {
            throw const ApiError(
              502,
              'github_response_invalid',
              'GitHub returned an invalid dev commit.',
            );
          }
          final trustedRef = trustedRefsBySha[candidateSha];
          if (trustedRef != null) {
            selected = (candidateSha, trustedRef);
            break;
          }
        }
        if (selected != null || history.length < pageSize) break;
      }
    }
    final sourceSha = selected?.$1 ?? sha;
    final sourceRef = selected?.$2 ?? fallbackRef;
    final exact = selected != null;
    return (
      sourceSha,
      sourceRef,
      readinessCheck(
        id: 'immutable_agent_source',
        label: 'Agent source tag is on the dev lineage',
        passed: exact,
        repository: repository,
        detail: exact
            ? '$sourceRef resolves to $sourceSha, the nearest trusted ancestor of current dev $sha.'
            : 'The dev lineage has no exact v4 agent tag.',
        guidance: exact
            ? ''
            : 'Run the v4 permission installer once on reviewed dev source to create its trusted tag.',
      ),
    );
  }

  Future<Map<String, Object?>> _environmentCheck(
    Workspace workspace, {
    required String repository,
    required String environment,
    required String trustedSourceRef,
  }) async {
    if (environment != iiOsAgentEnvironment) {
      return readinessCheck(
        id: 'agent_environment',
        label: 'Protected agent environment selected',
        passed: false,
        repository: repository,
        detail:
            'The permission profile must name the enforced $iiOsAgentEnvironment environment.',
        guidance: 'Set secret_injection.environment to $iiOsAgentEnvironment.',
      );
    }
    try {
      final encoded = Uri.encodeComponent(environment);
      final response = _asMap(
        await _rest(
          workspace,
          'GET',
          '/repos/$repository/environments/$encoded',
        ),
      );
      final policies = await _deploymentPolicies(
        workspace,
        repository: repository,
        environment: environment,
      );
      final protected = githubRuntimeEnvironmentProtected(
        response,
        policies,
        trustedSourceRef,
      );
      return readinessCheck(
        id: 'agent_environment',
        label: 'Agent credentials accept only immutable tags',
        passed: protected,
        repository: repository,
        detail: protected
            ? '$environment accepts only $trustedSourceRef, has no bypass, and needs no human approval for autonomous runs.'
            : '$environment is not bound exclusively to the exact reviewed tag $trustedSourceRef.',
        guidance: protected
            ? ''
            : 'Restrict $environment to the exact tag $trustedSourceRef and disable administrator bypass.',
      );
    } on ApiError catch (error) {
      return readinessFromGitHubError(
        id: 'agent_environment',
        label: 'Protected agent environment selected',
        repository: repository,
        error: error,
        missingCodes: const {'github_resource_not_found'},
        guidance:
            'Create $environment in repository Settings → Environments and allow only the exact reviewed tag $trustedSourceRef.',
      );
    }
  }

  Future<Map<String, Object?>> _bootstrapEnvironmentCheck(
    Workspace workspace, {
    required String repository,
  }) async {
    try {
      final encoded = Uri.encodeComponent(iiOsAgentBootstrapEnvironment);
      final response = _asMap(
        await _rest(
          workspace,
          'GET',
          '/repos/$repository/environments/$encoded',
        ),
      );
      final policies = await _deploymentPolicies(
        workspace,
        repository: repository,
        environment: iiOsAgentBootstrapEnvironment,
      );
      final protected = githubBootstrapEnvironmentProtected(response, policies);
      return readinessCheck(
        id: 'agent_bootstrap_environment',
        label: 'Agent setup source is restricted',
        passed: protected,
        repository: repository,
        detail: protected
            ? '$iiOsAgentBootstrapEnvironment accepts only immutable bootstrap tags, has no reviewer delay, and has no administrator bypass.'
            : '$iiOsAgentBootstrapEnvironment does not allow only ii-os-agent-v4-bootstrap-* tags with no reviewer delay and no administrator bypass.',
        guidance: protected
            ? ''
            : 'Create $iiOsAgentBootstrapEnvironment, allow only ii-os-agent-v4-bootstrap-* tags, add no required reviewers, and disable administrator bypass.',
      );
    } on ApiError catch (error) {
      return readinessFromGitHubError(
        id: 'agent_bootstrap_environment',
        label: 'Agent setup source is restricted',
        repository: repository,
        error: error,
        missingCodes: const {'github_resource_not_found'},
        guidance:
            'Create $iiOsAgentBootstrapEnvironment with an ii-os-agent-v4-bootstrap-* tag-only policy and no required reviewers.',
      );
    }
  }

  Future<List<Map<String, Object?>>> _deploymentPolicies(
    Workspace workspace, {
    required String repository,
    required String environment,
  }) async {
    final encoded = Uri.encodeComponent(environment);
    final response = _asMap(
      await _rest(
        workspace,
        'GET',
        '/repos/$repository/environments/$encoded/deployment-branch-policies?per_page=100',
      ),
    );
    final raw = response['branch_policies'];
    final total = response['total_count'];
    if (raw is! List<Object?> ||
        total is! num ||
        total.toInt() != raw.length ||
        raw.length > 100) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned invalid environment deployment policies.',
      );
    }
    return raw.whereType<Map<String, Object?>>().toList();
  }

  Future<Map<String, Object?>> _codexSecretCheck(
    Workspace workspace, {
    required String repository,
    required Map<String, Object?>? state,
  }) async {
    try {
      final metadata = _asMap(
        await _rest(
          workspace,
          'GET',
          '/repos/$repository/actions/secrets/CODEX_AUTH_JSON',
        ),
      );
      final status = state?['status'] as String? ?? 'unknown';
      final currentUpdatedAt = metadata['updated_at'] as String? ?? '';
      final validatedUpdatedAt = state?['secretUpdatedAt'] as String? ?? '';
      final exactSecret = codexSecretMetadataMatches(
        currentUpdatedAt,
        validatedUpdatedAt,
      );
      if (status == 'valid' && exactSecret) {
        return readinessCheck(
          id: 'codex_auth_secret',
          label: 'Codex live verified',
          passed: true,
          repository: repository,
          detail:
              'CODEX_AUTH_JSON passed a real Codex request and is ready for agent jobs.',
          guidance: '',
        );
      }
      final invalid = status == 'invalid' || status == 'revocation_required';
      final refreshing = status == 'refreshing';
      if (!invalid) {
        return {
          'id': 'codex_auth_secret',
          'label': refreshing
              ? 'Codex verification is in progress'
              : 'Codex OAuth credential needs verification',
          'status': 'securely_stored',
          'detail': refreshing
              ? 'A secure browser sign-in and live Codex request are running.'
              : status == 'valid'
              ? 'CODEX_AUTH_JSON changed after its last live verification.'
              : 'CODEX_AUTH_JSON exists, but ii-os has not seen this exact secret version pass a real Codex request.',
          'guidance': refreshing
              ? 'Finish the OpenAI sign-in or start again after it expires.'
              : 'Select Verify Codex and complete the OpenAI browser challenge.',
          'repository': repository,
          'action': 'connect_codex',
        };
      }
      return readinessCheck(
        id: 'codex_auth_secret',
        label: 'Codex sign-in has expired',
        passed: false,
        repository: repository,
        detail:
            (state?['detail'] as String?) ??
            'The latest agent run could not refresh the Codex credential.',
        guidance:
            'Select Verify Codex and complete the OpenAI browser challenge.',
        action: 'connect_codex',
      );
    } on ApiError catch (error) {
      if (error.code == 'github_resource_not_found') {
        return readinessCheck(
          id: 'codex_auth_secret',
          label: 'Codex OAuth credential is missing',
          passed: false,
          repository: repository,
          detail: 'GitHub does not have the CODEX_AUTH_JSON Actions secret.',
          guidance:
              'Select Verify Codex and complete the OpenAI browser challenge.',
          action: 'connect_codex',
        );
      }
      return readinessFromGitHubError(
        id: 'codex_auth_secret',
        label: 'Codex OAuth credential stored in GitHub',
        repository: repository,
        error: error,
        missingCodes: const {},
        guidance: 'Retry the check after GitHub is available.',
      );
    }
  }

  Future<Map<String, Object?>> _agentUsageSecretCheck(
    Workspace workspace, {
    required String repository,
  }) async {
    try {
      await _rest(
        workspace,
        'GET',
        '/repos/$repository/actions/secrets/II_OS_AGENT_USAGE_API_KEY',
      );
      return readinessCheck(
        id: 'agent_usage_secret',
        label: 'Agent usage reporting key stored in GitHub',
        passed: true,
        repository: repository,
        detail:
            'II_OS_AGENT_USAGE_API_KEY is available to the protected agent workflow.',
        guidance: '',
      );
    } on ApiError catch (error) {
      if (error.code == 'github_resource_not_found') {
        return readinessCheck(
          id: 'agent_usage_secret',
          label: 'Agent usage reporting key is missing',
          passed: false,
          repository: repository,
          detail:
              'GitHub does not have the II_OS_AGENT_USAGE_API_KEY Actions secret.',
          guidance:
              'Issue a workspace-scoped reporting key, store it as II_OS_AGENT_USAGE_API_KEY, and retry.',
        );
      }
      return readinessFromGitHubError(
        id: 'agent_usage_secret',
        label: 'Agent usage reporting key stored in GitHub',
        repository: repository,
        error: error,
        missingCodes: const {},
        guidance: 'Retry the check after GitHub is available.',
      );
    }
  }
}

const Set<String> agentDispatchReadinessCheckIds = {
  'workflow_allowlist',
  'agent_workflow',
  'codex_auth_workflow',
  'codex_auth_finalize_workflow',
  'immutable_agent_source',
  'agent_job_environment',
  'permission_profile',
  'fleet_capabilities',
  'codex_secret_binding',
  'agent_usage_secret_binding',
  'agent_environment',
  'codex_auth_secret',
  'agent_usage_secret',
};

const Set<String> codexAgentReadinessCheckIds = {
  'codex_auth_workflow',
  'codex_auth_finalize_workflow',
  'codex_secret_binding',
  'codex_auth_secret',
};

/// The queue gate contains only prerequisites needed by the next agent run.
///
/// Source manifests, installer receipts, bootstrap markers, and tag rulesets
/// may remain useful technical evidence, but they do not ask the workspace
/// owner for another setup ceremony after the exact workflow, profile,
/// environment, and short-lived credentials are already live-verifiable.
List<Map<String, Object?>> agentDispatchReadinessChecks(
  Iterable<Map<String, Object?>> checks, {
  String engine = codexAgentEngine,
}) => checks
    .where(
      (check) =>
          agentDispatchReadinessCheckIds.contains(check['id']) &&
          (agentEngineUsesCodexOAuth(engine) ||
              !codexAgentReadinessCheckIds.contains(check['id'])),
    )
    .toList();

/// Valid lightweight trusted-source tags, keyed by their commit SHA.
///
/// GitHub's matching-refs endpoint returns every match in one response. It is
/// not a normal 100-item REST page, so reaching 100 entries is not truncation.
/// Keeping this parser separate makes that contract regression-testable.
Map<String, String> trustedAgentSourceTags(Object? response) {
  if (response is! List<Object?> ||
      response.length > 10000 ||
      response.length != response.whereType<Map<String, Object?>>().length) {
    throw const ApiError(
      502,
      'github_response_invalid',
      'GitHub returned invalid trusted agent tags.',
    );
  }
  final result = <String, String>{};
  for (final tag in response.whereType<Map<String, Object?>>()) {
    final ref = tag['ref'];
    final tagObject = tag['object'];
    if (ref is! String ||
        !ref.startsWith('refs/tags/ii-os-agent-v4-') ||
        tagObject is! Map<String, Object?> ||
        tagObject['type'] != 'commit') {
      continue;
    }
    final sha = tagObject['sha'];
    final trustedRef = ref.substring('refs/tags/'.length);
    if (sha is String &&
        RegExp(r'^[0-9a-f]{40}$').hasMatch(sha) &&
        trustedRef == 'ii-os-agent-v4-$sha') {
      result[sha] = trustedRef;
    }
  }
  return result;
}

bool pythonImportCandidate(
  Map<String, Object?> entry, {
  Set<String> reviewedDirectories = const {},
}) {
  final name = entry['name'];
  final type = entry['type'];
  if (name is! String || name.isEmpty || type is! String) return true;
  final mode = entry['mode'];
  // A declared child namespace gets its own complete import-entry comparison.
  // Symlinks, gitlinks and undeclared directories still fail the parent gate.
  if (type == 'tree' &&
      mode == '040000' &&
      reviewedDirectories.contains(name)) {
    return false;
  }
  final regular =
      type == 'file' ||
      (type == 'blob' && (mode == '100644' || mode == '100755'));
  return !regular ||
      name.endsWith('.py') ||
      name.endsWith('.pyc') ||
      name.endsWith('.pyo') ||
      name.endsWith('.pyd') ||
      name.endsWith('.so');
}

String pythonImportEntryIdentity(Map<String, Object?> entry) {
  final name = entry['name'];
  final type = entry['type'];
  final mode = entry['mode'];
  if (name is! String || name.isEmpty || type is! String) {
    return '<invalid-entry>';
  }
  final regular =
      type == 'file' ||
      (type == 'blob' && (mode == '100644' || mode == '100755'));
  return regular ? name : '$name\u0000$type\u0000${mode ?? ''}';
}
