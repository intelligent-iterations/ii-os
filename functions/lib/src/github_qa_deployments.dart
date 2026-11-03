part of 'github_client.dart';

const qaDeploymentRequestTimeout = Duration(seconds: 4);
const qaDeploymentCandidateLimit = 1;
const qaDeploymentStatusLimit = 10;

extension GitHubQaDeployments on GitHubClient {
  /// Reads the cached deployment receipt that can unlock human QA.
  ///
  /// Merge bursts can deploy one later `dev` commit. GitHub must prove that
  /// the successful environment Deployment contains the exact merge commit.
  Future<Map<String, Object?>> getPullRequestWithQaDeployment(
    Workspace workspace, {
    required String repository,
    required int number,
  }) async {
    final pull = await getPullRequest(
      workspace,
      repository: repository,
      number: number,
    );
    if (pull['merged'] != true) return pull;
    final sha = pull['mergeCommitSha'];
    if (sha is! String || !_gitSha.hasMatch(sha)) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid pull request merge identity.',
      );
    }
    const environment = 'dev';
    if (workspace.usesOrganizationResourceGrants &&
        !workspace.allowsGitHubPermission(
          'deployments:read',
          repository: repository,
        )) {
      return {
        ...pull,
        'qaDeployment': qaDeploymentUnavailable(
          sha: sha,
          environment: environment,
        ),
      };
    }
    final permissions = await _transport.installationPermissions(
      workspace,
      repository: repository,
    );
    if (!_permissionAllows(permissions['deployments'] ?? 'none', 'read')) {
      return {
        ...pull,
        'qaDeployment': qaDeploymentUnavailable(
          sha: sha,
          environment: environment,
        ),
      };
    }
    final proof = await _qaDeploymentCache.resolve(
      GitHubQaDeploymentCacheKey(
        workspaceId: workspace.id,
        installationId: workspace.githubInstallationId!,
        repository: repository,
        mergeCommitSha: sha,
      ),
      () => _resolveQaDeploymentProof(
        workspace,
        repository: repository,
        mergeCommitSha: sha,
        environment: environment,
      ),
    );
    return {...pull, 'qaDeployment': proof};
  }

  Future<Map<String, Object?>> _resolveQaDeploymentProof(
    Workspace workspace, {
    required String repository,
    required String mergeCommitSha,
    required String environment,
  }) async {
    final encodedEnvironment = Uri.encodeQueryComponent(environment);
    final response = await _rest(
      workspace,
      'GET',
      '/repos/$repository/deployments?environment=$encodedEnvironment&per_page=$qaDeploymentCandidateLimit',
      timeout: qaDeploymentRequestTimeout,
    );
    final deployment = selectLatestQaDeployment(
      repository: repository,
      environment: environment,
      values: response,
    );
    if (deployment == null) {
      return qaDeploymentNotFound(
        sha: mergeCommitSha,
        environment: environment,
      );
    }
    final deploymentId = deployment['id']! as int;
    final statuses = await _rest(
      workspace,
      'GET',
      '/repos/$repository/deployments/$deploymentId/statuses?per_page=$qaDeploymentStatusLimit',
      timeout: qaDeploymentRequestTimeout,
    );
    final proof = normalizeQaDeploymentProof(
      deployment: deployment,
      statuses: statuses,
    );
    if (proof['succeeded'] != true) {
      return {...proof, 'coversSha': '', 'coverage': 'none'};
    }
    final deployedSha = proof['sha']! as String;
    if (deployedSha == mergeCommitSha) {
      return {...proof, 'coversSha': mergeCommitSha, 'coverage': 'exact'};
    }
    final comparison = await _rest(
      workspace,
      'GET',
      '/repos/$repository/compare/$mergeCommitSha...$deployedSha',
      timeout: qaDeploymentRequestTimeout,
    );
    if (!deploymentCoversMergeCommit(
      mergeSha: mergeCommitSha,
      deployedSha: deployedSha,
      comparison: comparison,
    )) {
      return qaDeploymentNotFound(
        sha: mergeCommitSha,
        environment: environment,
      );
    }
    return {...proof, 'coversSha': mergeCommitSha, 'coverage': 'ancestor'};
  }
}

void requireMergedAgentPullRequest(Map<String, Object?> pull) {
  if (pull['state'] != 'closed' ||
      pull['merged'] != true ||
      pull['baseRef'] != 'dev' ||
      !(pull['headRef'] as String? ?? '').startsWith('ii-os-agent/')) {
    throw const ApiError(
      409,
      'pull_request_not_merged',
      'Merge the agent pull request before moving this ticket to QA.',
    );
  }
}

void requireSuccessfulQaDeployment(Map<String, Object?> pull) {
  requireMergedAgentPullRequest(pull);
  final mergeCommitSha = pull['mergeCommitSha'];
  final deployment = pull['qaDeployment'];
  if (mergeCommitSha is! String ||
      !_gitSha.hasMatch(mergeCommitSha) ||
      deployment is! Map<String, Object?> ||
      deployment['deploymentId'] is! int ||
      (deployment['deploymentId']! as int) <= 0 ||
      deployment['environment'] != 'dev' ||
      deployment['sha'] is! String ||
      !_gitSha.hasMatch(deployment['sha']! as String) ||
      deployment['coversSha'] != mergeCommitSha ||
      !const {'exact', 'ancestor'}.contains(deployment['coverage']) ||
      deployment['succeeded'] != true) {
    throw const ApiError(
      409,
      'qa_deployment_not_successful',
      'Wait for a dev deployment containing this merge to succeed before moving this ticket to QA.',
    );
  }
}

Map<String, Object?>? selectQaDeployment({
  required String repository,
  required String sha,
  required String environment,
  required Object? values,
}) {
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository) ||
      !_gitSha.hasMatch(sha) ||
      environment != 'dev' ||
      values is! List<Object?> ||
      values.length > 100 ||
      values.any((value) => value is! Map<String, Object?>)) {
    throw _invalidDeploymentResponse;
  }
  final deployments = <Map<String, Object?>>[];
  for (final value in values.whereType<Map<String, Object?>>()) {
    final id = value['id'];
    final createdAt = DateTime.tryParse(value['created_at'] as String? ?? '');
    if (id is! num ||
        id.toInt() <= 0 ||
        id.toInt() != id ||
        value['sha'] != sha ||
        value['environment'] != environment ||
        createdAt == null) {
      throw _invalidDeploymentResponse;
    }
    deployments.add({
      'id': id.toInt(),
      'repository': repository,
      'sha': sha,
      'environment': environment,
      'createdAt': createdAt.toUtc().toIso8601String(),
    });
  }
  deployments.sort(
    (left, right) => (right['id']! as int).compareTo(left['id']! as int),
  );
  return deployments.firstOrNull;
}

Map<String, Object?>? selectLatestQaDeployment({
  required String repository,
  required String environment,
  required Object? values,
}) {
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository) ||
      environment != 'dev' ||
      values is! List<Object?> ||
      values.length > qaDeploymentCandidateLimit ||
      values.any((value) => value is! Map<String, Object?>)) {
    throw _invalidDeploymentResponse;
  }
  final value = values.whereType<Map<String, Object?>>().firstOrNull;
  if (value == null) return null;
  final id = value['id'];
  final sha = value['sha'];
  final createdAt = DateTime.tryParse(value['created_at'] as String? ?? '');
  if (id is! num ||
      id.toInt() <= 0 ||
      id.toInt() != id ||
      sha is! String ||
      !_gitSha.hasMatch(sha) ||
      value['environment'] != environment ||
      createdAt == null) {
    throw _invalidDeploymentResponse;
  }
  return {
    'id': id.toInt(),
    'repository': repository,
    'sha': sha,
    'environment': environment,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

bool deploymentCoversMergeCommit({
  required String mergeSha,
  required String deployedSha,
  required Object? comparison,
}) {
  if (!_gitSha.hasMatch(mergeSha) || !_gitSha.hasMatch(deployedSha)) {
    throw _invalidDeploymentResponse;
  }
  if (mergeSha == deployedSha) return true;
  if (comparison is! Map<String, Object?>) {
    throw _invalidDeploymentResponse;
  }
  final status = comparison['status'];
  final aheadBy = comparison['ahead_by'];
  final behindBy = comparison['behind_by'];
  final mergeBase = comparison['merge_base_commit'];
  final mergeBaseSha = mergeBase is Map<String, Object?>
      ? mergeBase['sha']
      : null;
  if (!const {'ahead', 'behind', 'diverged', 'identical'}.contains(status) ||
      aheadBy is! num ||
      aheadBy.toInt() != aheadBy ||
      aheadBy.toInt() < 0 ||
      behindBy is! num ||
      behindBy.toInt() != behindBy ||
      behindBy.toInt() < 0 ||
      mergeBaseSha is! String ||
      !_gitSha.hasMatch(mergeBaseSha)) {
    throw _invalidDeploymentResponse;
  }
  if (status == 'identical') throw _invalidDeploymentResponse;
  return status == 'ahead' &&
      aheadBy.toInt() > 0 &&
      behindBy.toInt() == 0 &&
      mergeBaseSha == mergeSha;
}

Map<String, Object?> normalizeQaDeploymentProof({
  required Map<String, Object?>? deployment,
  required Object? statuses,
}) {
  if (deployment == null ||
      deployment['id'] is! int ||
      deployment['sha'] is! String ||
      !_gitSha.hasMatch(deployment['sha']! as String) ||
      deployment['environment'] != 'dev' ||
      statuses is! List<Object?> ||
      statuses.length > qaDeploymentStatusLimit ||
      statuses.any((value) => value is! Map<String, Object?>)) {
    throw _invalidDeploymentResponse;
  }
  final normalized = <Map<String, Object?>>[];
  for (final value in statuses.whereType<Map<String, Object?>>()) {
    final id = value['id'];
    final state = value['state'];
    final createdAt = DateTime.tryParse(value['created_at'] as String? ?? '');
    if (id is! num ||
        id.toInt() <= 0 ||
        id.toInt() != id ||
        !const {
          'error',
          'failure',
          'inactive',
          'in_progress',
          'queued',
          'pending',
          'success',
        }.contains(state) ||
        value['environment'] != 'dev' ||
        createdAt == null) {
      throw _invalidDeploymentResponse;
    }
    normalized.add({
      'id': id.toInt(),
      'state': state,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'environmentUrl': value['environment_url'] as String? ?? '',
      'logUrl': value['log_url'] as String? ?? '',
    });
  }
  normalized.sort(
    (left, right) => (right['id']! as int).compareTo(left['id']! as int),
  );
  final latest = normalized.firstOrNull;
  final effective = normalized
      .where((status) => status['state'] != 'inactive')
      .firstOrNull;
  return {
    'deploymentId': deployment['id'],
    'environment': deployment['environment'],
    'sha': deployment['sha'],
    'coversSha': deployment['sha'],
    'coverage': 'exact',
    'state': latest?['state'] ?? 'pending',
    'succeeded': effective?['state'] == 'success',
    'environmentUrl': latest?['environmentUrl'] ?? '',
    'logUrl': latest?['logUrl'] ?? '',
    'updatedAt': latest?['createdAt'] ?? deployment['createdAt'],
  };
}

Map<String, Object?> qaDeploymentNotFound({
  required String sha,
  required String environment,
}) => {
  'deploymentId': null,
  'environment': environment,
  'sha': sha,
  'coversSha': sha,
  'coverage': 'none',
  'state': 'not_found',
  'succeeded': false,
  'environmentUrl': '',
  'logUrl': '',
  'updatedAt': null,
};

Map<String, Object?> qaDeploymentUnavailable({
  required String sha,
  required String environment,
}) => {
  ...qaDeploymentNotFound(sha: sha, environment: environment),
  'state': 'unavailable',
};

const _invalidDeploymentResponse = ApiError(
  502,
  'github_response_invalid',
  'GitHub returned invalid deployment evidence.',
);
