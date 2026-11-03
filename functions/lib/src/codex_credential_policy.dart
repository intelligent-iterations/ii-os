import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'agent_permission_profile.dart';
import 'api_error.dart';
import 'github_actions_oidc.dart';

const credentialConflict = ApiError(
  409,
  'credential_binding_conflict',
  'The credential handoff does not match its reserved execution.',
);

String codexCredentialBindingId(int repositoryId) {
  if (repositoryId <= 0) throw credentialConflict;
  return 'github.com~$repositoryId~CODEX_AUTH_JSON';
}

bool credentialDigestValid(Object? value, {bool allowEmpty = false}) =>
    value is String &&
    ((allowEmpty && value.isEmpty) ||
        RegExp(r'^[0-9a-f]{64}$').hasMatch(value));

String codexCredentialConfiguration(Map<String, Object?> body) {
  final value = body['runtimeConfiguration'];
  if (value is! String || value.isEmpty || utf8.encode(value).length > 32768) {
    throw credentialConflict;
  }
  return value; // Exact file bytes include indentation and trailing newlines.
}

void requireCredentialMetadataSize(
  Object value, {
  int maxBytes = 8192,
  Object? Function(Object?)? toEncodable,
}) {
  if (utf8.encode(jsonEncode(value, toEncodable: toEncodable)).length >
      maxBytes) {
    throw credentialConflict;
  }
}

/// Verifies bytes against the human-approved reference, never mutable dev.
void requireCodexCredentialConfiguration({
  required AgentPermissionProfile profile,
  required String configuration,
  required String repository,
}) {
  final bytes = utf8.encode(configuration);
  if (profile.engine != codexAgentEngine ||
      profile.runtime == null ||
      bytes.length > 32768 ||
      sha256.convert(bytes).toString() !=
          profile.runtime!.configurationDigest) {
    throw credentialConflict;
  }
  _requireOAuthBinding(configuration, repository);
}

void _requireOAuthBinding(String configuration, String repository) {
  Object? value;
  try {
    value = jsonDecode(configuration);
  } on FormatException {
    throw credentialConflict;
  }
  final bindings = value is Map ? value['credentialBindings'] : null;
  final oauth = bindings is List
      ? bindings.where(
          (binding) =>
              binding is Map && binding['assignment'] == 'harness.codex.oauth',
        )
      : const <Object?>[];
  if (oauth.length != 1) throw credentialConflict;
  final binding = oauth.single as Map<Object?, Object?>;
  if (binding.length != 4 ||
      binding['provider'] != 'github-actions' ||
      binding['resource'] != repository ||
      binding['key'] != 'CODEX_AUTH_JSON') {
    throw credentialConflict;
  }
}

/// Authority metadata only. It is never an OAuth credential or bearer token.
final class CodexCredentialOwner {
  const CodexCredentialOwner({
    required this.workspaceId,
    required this.subjectId,
    required this.purpose,
    required this.principal,
    this.projectItemId,
    this.dispatchId,
  });

  final String workspaceId;
  final String subjectId;
  final String purpose;
  final GitHubActionsPrincipal principal;
  final String? projectItemId;
  final String? dispatchId;
  bool get initialAuth => purpose == 'codex-auth';
  bool get ticket => purpose == 'work-ticket';

  /// Purposes that may only lease a credential already verified as valid.
  bool get usesVerifiedCredential => const {'work-ticket'}.contains(purpose);
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'subjectId': subjectId,
    'purpose': purpose,
    'repository': principal.repository,
    'repositoryId': principal.repositoryId,
    'runId': principal.runId,
    'runAttempt': principal.runAttempt,
    'workflowSha': principal.sha,
    if (ticket) 'projectItemId': projectItemId,
    if (ticket) 'dispatchId': dispatchId,
  };

  bool matches(Object? other) =>
      other is Map &&
      other.length == toJson().length &&
      toJson().entries.every((entry) => other[entry.key] == entry.value);

  bool matchesCleanup(Object? other, Map<String, Object?> body) {
    if (matches(other)) return true;
    if (body['cleanupOnly'] != true ||
        other is! Map ||
        other.length != toJson().length ||
        other['runAttempt'] is! int ||
        principal.runAttempt <= (other['runAttempt']! as int)) {
      return false;
    }
    return toJson().entries
        .where((entry) => entry.key != 'runAttempt')
        .every((entry) => other[entry.key] == entry.value);
  }

  String get receiptField => purpose == 'codex-auth-verify'
      ? 'credentialVerificationReceipt'
      : 'credentialReceipt';

  /// Checks that [context] is the execution this owner leased for.
  ///
  /// With [cleanupOnly], a later attempt of the same run may finish the
  /// cleanup an earlier attempt's lease left behind.
  void requireContext(
    Map<String, Object?>? context, {
    bool cleanupOnly = false,
  }) {
    final verification = purpose == 'codex-auth-verify';
    final runAttemptField = ticket
        ? 'workflowRunAttempt'
        : verification
        ? 'verificationRunAttempt'
        : 'runAttempt';
    if (context == null ||
        context['repository'] != principal.repository ||
        context['repositoryId'] != principal.repositoryId ||
        context[ticket
                ? 'workflowRunId'
                : verification
                ? 'verificationRunId'
                : 'runId'] !=
            principal.runId ||
        (context[runAttemptField] != principal.runAttempt &&
            !(cleanupOnly &&
                context[runAttemptField] is int &&
                principal.runAttempt > (context[runAttemptField]! as int))) ||
        context[ticket
                ? 'workflowSha'
                : verification
                ? 'verificationWorkflowSha'
                : 'workflowSha'] !=
            principal.sha ||
        (ticket &&
            (context['status'] != 'consumed' ||
                context['claimId'] != dispatchId))) {
      throw credentialConflict;
    }
  }
}

Map<String, Object?> requireCredentialLease(
  Map<String, Object?>? binding,
  CodexCredentialOwner owner,
  Map<String, Object?> body,
) {
  final value = binding?['lease'];
  if (value is! Map) throw credentialConflict;
  final lease = value.cast<String, Object?>();
  if (!owner.matchesCleanup(lease['owner'], body) ||
      lease['reservationId'] != body['reservationId'] ||
      lease['fence'] != body['fence'] ||
      lease['originalDigest'] != body['originalDigest']) {
    throw credentialConflict;
  }
  return lease;
}

void requireCredentialCleanup(Map<String, Object?> body) {
  if (body['workerCleanupDigest'] is! String ||
      !RegExp(
        r'^sha256:[0-9a-f]{64}$',
      ).hasMatch(body['workerCleanupDigest']! as String)) {
    throw credentialConflict;
  }
}
