part of 'codex_auth_store.dart';

bool codexAuthTransitionAllowed(String current, String next) {
  if (current == next) return true;
  const transitions = {
    'dispatching': {
      'waiting_for_user',
      'validating',
      'failed',
      'expired',
      'cancelled',
    },
    'waiting_for_user': {'validating', 'failed', 'expired', 'cancelled'},
    'validating': {'writing_secret', 'failed', 'expired', 'cancelled'},
    'writing_secret': {'awaiting_cleanup', 'failed', 'expired', 'cancelled'},
    'awaiting_cleanup': {'succeeded', 'failed', 'expired', 'cancelled'},
  };
  return transitions[current]?.contains(next) ?? false;
}

bool _isGitHubRunUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.pathSegments.contains('actions');
}

final _sessionNotFound = ApiError(
  404,
  'codex_auth_session_not_found',
  'Codex verification session not found.',
);
final _sessionExpired = ApiError(
  409,
  'codex_auth_session_expired',
  'The Codex verification session expired.',
);
final _transitionInvalid = ApiError(
  409,
  'codex_auth_transition_invalid',
  'The Codex verification session changed state.',
);

DateTime _utcNow() => DateTime.now().toUtc();

const _workflowStatuses = {
  'waiting_for_user',
  'validating',
  'writing_secret',
  'awaiting_cleanup',
  'succeeded',
  'failed',
  'expired',
  'cancelled',
};
const _terminalStatuses = {'succeeded', 'failed', 'expired', 'cancelled'};

bool _isActive(Object? status) => !_terminalStatuses.contains(status);

Map<String, Object?> _workflowMetadata(
  Map<String, Object?> event,
  String status,
  DateTime now,
) {
  final values = <String, Object?>{};
  if (status == 'waiting_for_user') {
    final url = event['verificationUrl'];
    final code = event['userCode'];
    if (url != 'https://auth.openai.com/codex/device' ||
        code is! String ||
        !RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4,8}$').hasMatch(code)) {
      throw const ApiError(
        400,
        'codex_auth_challenge_invalid',
        'Codex returned an invalid OpenAI sign-in challenge.',
      );
    }
    values['verificationUrl'] = url;
    values['userCode'] = code;
  }
  if (status == 'awaiting_cleanup') {
    values['secretUpdatedAt'] = Timestamp.fromDate(
      DateTime.parse(event['secretUpdatedAt'] as String).toUtc(),
    );
    values['writerTokenStatus'] = 'revoked';
    values['writerTokenRevokedAt'] = Timestamp.fromDate(now);
    values['secretDigest'] = event['secretDigest'];
  }
  if (_terminalStatuses.contains(status) && status != 'succeeded') {
    values['errorCode'] = _bounded(
      event['errorCode']?.toString() ?? status,
      100,
    );
    values['detail'] = _bounded(
      event['detail']?.toString() ?? 'Codex verification did not complete.',
      500,
    );
  }
  return values;
}

void _requireWorkflowSession(
  Map<String, Object?>? data,
  GitHubActionsPrincipal principal,
) {
  final verification = principal.jobUses(iiOsCodexAuthFinalizeWorkflow);
  final runId = verification ? 'verificationRunId' : 'runId';
  final runAttempt = verification ? 'verificationRunAttempt' : 'runAttempt';
  final workflowSha = verification ? 'verificationWorkflowSha' : 'workflowSha';
  if (data == null ||
      data['repository'] != principal.repository ||
      data['repositoryId'] != principal.repositoryId ||
      data[runId] != principal.runId ||
      data[runAttempt] != principal.runAttempt ||
      data[workflowSha] != principal.sha ||
      data['trustedSourceSha'] != principal.sha ||
      data['trustedSourceRef'] != principal.trustedRef) {
    throw _sessionNotFound;
  }
}

void _requireWorkflowRole(GitHubActionsPrincipal principal, String status) {
  final expected = status == 'succeeded'
      ? iiOsCodexAuthFinalizeWorkflow
      : iiOsCodexAuthWorkflow;
  if (!principal.jobUses(expected)) throw _sessionNotFound;
}

void _requireSecretStored(
  Map<String, Object?> data,
  Map<String, Object?> event,
) {
  final updatedAt = event['secretUpdatedAt'];
  final digest = event['secretDigest'];
  final committed =
      data['credentialCommitCompleted'] == true &&
      data['writerTokenStatus'] == 'revoked' &&
      data['secretDigest'] == digest &&
      data['secretUpdatedAt'] is Timestamp &&
      updatedAt is String &&
      (data['secretUpdatedAt']! as Timestamp).toDate().toUtc() ==
          DateTime.tryParse(updatedAt)?.toUtc();
  if ((!committed &&
          (data['writerTokenStatus'] != 'issued' ||
              data['writerTokenIssueCount'] != 1)) ||
      updatedAt is! String ||
      digest is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
      DateTime.tryParse(updatedAt)?.isUtc != true) {
    throw _transitionInvalid;
  }
}

void _requireFinalizationReady(
  Map<String, Object?> data,
  Map<String, Object?> event,
) {
  if (data['status'] != 'awaiting_cleanup' ||
      data['writerTokenStatus'] != 'revoked' ||
      data['writerTokenRevokedAt'] is! Timestamp ||
      data['secretUpdatedAt'] is! Timestamp ||
      data['secretDigest'] != event['secretDigest']) {
    throw _transitionInvalid;
  }
}

bool _sameRetry(
  Map<String, Object?> data,
  Map<String, Object?> event,
  String status,
) {
  if (status == 'waiting_for_user') {
    return data['verificationUrl'] == event['verificationUrl'] &&
        data['userCode'] == event['userCode'];
  }
  if (status == 'awaiting_cleanup') {
    final eventTime = DateTime.tryParse(
      event['secretUpdatedAt'] as String? ?? '',
    )?.toUtc();
    final stored = data['secretUpdatedAt'];
    return stored is Timestamp &&
        eventTime != null &&
        stored.toDate().toUtc() == eventTime &&
        data['writerTokenStatus'] == 'revoked' &&
        data['secretDigest'] == event['secretDigest'];
  }
  return true;
}

bool _writerTokenOutstanding(Map<String, Object?> data, DateTime now) {
  final expiresAt = data['writerTokenExpiresAt'];
  return (data['writerTokenStatus'] == 'issued' ||
          data['writerTokenStatus'] == 'reserved') &&
      data['writerTokenRevokedAt'] == null &&
      expiresAt is Timestamp &&
      expiresAt.toDate().toUtc().isAfter(now);
}

Map<String, Object?> _publicSession(String id, Map<String, Object?> data) => {
  'id': id,
  'repository': data['repository'],
  'status': data['status'],
  'createdAt': _iso(data['createdAt']),
  'updatedAt': _iso(data['updatedAt']),
  'expiresAt': _iso(data['expiresAt']),
  'verificationUrl': data['verificationUrl'],
  'userCode': data['userCode'],
  'runId': data['runId'],
  'runAttempt': data['runAttempt'],
  'runUrl': data['runUrl'],
  'verificationRunId': data['verificationRunId'],
  'verificationRunUrl': data['verificationRunUrl'],
  'errorCode': data['errorCode'],
  'detail': data['detail'],
  'terminal': _terminalStatuses.contains(data['status']),
};

Map<String, Object?> _publicState(Map<String, Object?> data) => {
  'repository': data['repository'],
  'status': data['status'],
  'failureCode': data['failureCode'],
  'detail': data['detail'],
  'workflowRunId': data['workflowRunId'],
  'workflowSha': data['workflowSha'],
  'secretUpdatedAt': _iso(data['secretUpdatedAt']),
  'secretDigest': data['secretDigest'],
  'validatedAt': _iso(data['validatedAt']),
  'storedAt': _iso(data['storedAt']),
  'failedAt': _iso(data['failedAt']),
  'updatedAt': _iso(data['updatedAt']),
};

String? _iso(Object? value) =>
    value is Timestamp ? value.toDate().toUtc().toIso8601String() : null;

String _bounded(String value, int max) {
  final trimmed = value.trim();
  return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
}

void _validateRepository(String repository, int repositoryId) {
  if (repositoryId <= 0 ||
      !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
    throw const ApiError(
      400,
      'repository_not_allowed',
      'Repository is not configured for this workspace.',
    );
  }
}
