import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'api_error.dart';

final class AgentPullRequestIntent {
  const AgentPullRequestIntent({
    required this.repository,
    required this.repositoryId,
    required this.head,
    required this.base,
    required this.headSha,
    required this.baseSha,
    required this.expectedOldHeadSha,
  });

  final String repository;
  final int repositoryId;
  final String head;
  final String base;
  final String headSha;
  final String baseSha;
  final String? expectedOldHeadSha;

  Map<String, Object?> get canonicalJson => {
    'base': base,
    'base_sha': baseSha,
    'expected_old_head_sha': expectedOldHeadSha,
    'head': head,
    'head_sha': headSha,
    'repository': repository,
    'repository_id': repositoryId,
  };
}

final class AgentAutomationFailure {
  const AgentAutomationFailure({required this.code, required this.detail});

  final String code;
  final String detail;

  Map<String, Object?> get canonicalJson => {'code': code, 'detail': detail};
}

final class AgentDispatchResult {
  const AgentDispatchResult({
    required this.dispatchId,
    required this.repository,
    required this.repositoryId,
    required this.issueNumber,
    required this.projectItemId,
    required this.outcome,
    required this.projectStatus,
    required this.comments,
    required this.pullRequest,
    required this.automationFailure,
  });

  factory AgentDispatchResult.parse(Map<String, Object?> value) {
    const keys = {
      'dispatch_id',
      'repository',
      'repository_id',
      'issue_number',
      'project_item_id',
      'outcome',
      'status',
      'comments',
      'pull_request',
      'automation_failure',
    };
    final comments = value['comments'];
    final normalizedComments = comments is List<Object?>
        ? comments.whereType<String>().toList()
        : const <String>[];
    final issueNumber = value['issue_number'];
    final repositoryId = value['repository_id'];
    final outcome = value['outcome'];
    final status = value['status'];
    final pullRequest = _parsePullRequest(
      value['pull_request'],
      value['dispatch_id'],
    );
    final automationFailure = _parseAutomationFailure(
      value['automation_failure'],
      allowed: outcome == 'not_ready' && status == 'todo',
    );
    final consistent =
        (outcome == 'ready_for_qa' && status == 'ready_for_qa') ||
        (outcome == 'not_ready' &&
            (status == 'todo' || status == 'needs_human_input'));
    if (value.keys.toSet().length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        value['dispatch_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9:_-]{1,200}$',
        ).hasMatch(value['dispatch_id']! as String) ||
        value['repository'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
        ).hasMatch(value['repository']! as String) ||
        repositoryId is! int ||
        repositoryId <= 0 ||
        issueNumber is! int ||
        issueNumber <= 0 ||
        value['project_item_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$',
        ).hasMatch(value['project_item_id']! as String) ||
        !consistent ||
        (outcome == 'ready_for_qa' && pullRequest == null) ||
        comments is! List<Object?> ||
        normalizedComments.length != comments.length ||
        normalizedComments.length > 8 ||
        normalizedComments.any(
          (comment) =>
              comment.trim().isEmpty ||
              comment != comment.trim() ||
              comment.length > 8000,
        ) ||
        normalizedComments.fold<int>(
              0,
              (total, comment) => total + comment.length,
            ) >
            24000) {
      throw const ApiError(
        400,
        'agent_dispatch_result_invalid',
        'The bounded agent result is invalid.',
      );
    }
    return AgentDispatchResult(
      dispatchId: value['dispatch_id']! as String,
      repository: value['repository']! as String,
      repositoryId: repositoryId,
      issueNumber: issueNumber,
      projectItemId: value['project_item_id']! as String,
      outcome: outcome! as String,
      projectStatus: status! as String,
      comments: List.unmodifiable(normalizedComments),
      pullRequest: pullRequest,
      automationFailure: automationFailure,
    );
  }

  final String dispatchId;
  final String repository;
  final int repositoryId;
  final int issueNumber;
  final String projectItemId;
  final String outcome;
  final String projectStatus;
  final List<String> comments;
  final AgentPullRequestIntent? pullRequest;
  final AgentAutomationFailure? automationFailure;

  /// Whether the cleaned Fleet run exported repository work that the broker
  /// may publish for review.
  ///
  /// Publication precedes the status transition. A pull request that still
  /// needs human review or agent follow-up is therefore publishable even when
  /// it is not yet Ready for QA; only an automation-failure result is excluded.
  bool get hasPublishableChange =>
      pullRequest != null && automationFailure == null;

  Map<String, Object?> get canonicalJson => {
    'comments': comments,
    'automation_failure': automationFailure?.canonicalJson,
    'dispatch_id': dispatchId,
    'issue_number': issueNumber,
    'outcome': outcome,
    'project_item_id': projectItemId,
    'pull_request': pullRequest?.canonicalJson,
    'repository': repository,
    'repository_id': repositoryId,
    'status': projectStatus,
  };
}

AgentAutomationFailure? _parseAutomationFailure(
  Object? value, {
  required bool allowed,
}) {
  if (value == null) return null;
  if (!allowed ||
      value is! Map<String, Object?> ||
      value.keys.toSet().length != 2 ||
      !value.keys.toSet().containsAll(const {'code', 'detail'})) {
    throw _invalidResult;
  }
  final code = value['code'];
  final detail = value['detail'];
  if (code is! String ||
      !RegExp(r'^[a-z][a-z0-9_]{0,99}$').hasMatch(code) ||
      detail is! String ||
      detail.isEmpty ||
      detail != detail.trim() ||
      detail.length > 500 ||
      detail.contains('\n') ||
      detail.contains('\r')) {
    throw _invalidResult;
  }
  return AgentAutomationFailure(code: code, detail: detail);
}

AgentPullRequestIntent? _parsePullRequest(Object? value, Object? dispatchId) {
  if (value == null) return null;
  if (value is! Map<String, Object?> ||
      value.keys.toSet().length != 7 ||
      !value.keys.toSet().containsAll(const {
        'repository',
        'repository_id',
        'head',
        'base',
        'head_sha',
        'base_sha',
        'expected_old_head_sha',
      }) ||
      dispatchId is! String) {
    throw _invalidResult;
  }
  final expectedHead =
      'ii-os-agent/${sha256.convert(utf8.encode(dispatchId)).toString().substring(0, 32)}';
  final headSha = value['head_sha'];
  final baseSha = value['base_sha'];
  final repository = value['repository'];
  final repositoryId = value['repository_id'];
  final expectedOldHeadSha = value['expected_old_head_sha'];
  final sha = RegExp(r'^[0-9a-f]{40}$');
  if (value['head'] != expectedHead ||
      value['base'] != 'dev' ||
      repository is! String ||
      !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository) ||
      repositoryId is! int ||
      repositoryId <= 0 ||
      headSha is! String ||
      !sha.hasMatch(headSha) ||
      baseSha is! String ||
      !sha.hasMatch(baseSha) ||
      (expectedOldHeadSha != null &&
          (expectedOldHeadSha is! String ||
              !sha.hasMatch(expectedOldHeadSha)))) {
    throw _invalidResult;
  }
  return AgentPullRequestIntent(
    repository: repository,
    repositoryId: repositoryId,
    head: expectedHead,
    base: 'dev',
    headSha: headSha,
    baseSha: baseSha,
    expectedOldHeadSha: expectedOldHeadSha as String?,
  );
}

const _invalidResult = ApiError(
  400,
  'agent_dispatch_result_invalid',
  'The bounded agent result is invalid.',
);
