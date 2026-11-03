import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'agent_permission_profile.dart';
import 'api_error.dart';
import 'auth_service.dart';
import 'github_actions_oidc.dart';
import 'workspace_store.dart';

/// Immutable record that one human authorized one exact permission install.
///
/// The installer workflow is trusted to change what an agent may do, so it may
/// not simply assert its own authority. It carries an approval id and a fence,
/// and calls back here to have both checked against what a human actually
/// approved before it installs anything.
final class AgentPermissionApprovalStore {
  AgentPermissionApprovalStore(this.store);

  final WorkspaceStore store;

  /// Records an approval and returns the values the dispatch must carry.
  ///
  /// The fence is monotonic per repository. A dispatch carrying a fence below
  /// the repository's current one is a replay of a superseded approval and is
  /// refused at consume time, so an older approved profile cannot be installed
  /// over a newer one.
  Future<AgentPermissionApproval> approve({
    required String workspaceId,
    required String repository,
    required String ref,
    required AgentPermissionProfile profile,
    required AuthenticatedUser actor,
  }) async {
    final approvalId = _identifier('apv');
    final dispatchId = _identifier('dsp');
    final digest = agentPermissionProfileDigest(profile);
    final now = Timestamp.now();
    final fenceRef = _fenceRef(workspaceId, repository);
    final fence = await store.firestore.runTransaction<int>((
      transaction,
    ) async {
      final current = (await transaction.get(fenceRef)).data();
      final previous = current?['fence'];
      final next = (previous is int && previous > 0 ? previous : 0) + 1;
      transaction.set(fenceRef, {
        'fence': next,
        'repository': repository,
        'updatedAt': now,
      });
      transaction.set(_approvalRef(workspaceId, approvalId), {
        'approvalId': approvalId,
        'dispatchId': dispatchId,
        'dispatchFence': next,
        'workspaceId': workspaceId,
        'repository': repository,
        'permissionRef': ref,
        'profileId': profile.id,
        'profileVersion': profile.version,
        'profileDigest': digest,
        'profileJson': jsonEncode(profile.toJson()),
        'status': 'approved',
        'approvedBy': actor.uid,
        'approvedAt': now,
      });
      return next;
    });
    return AgentPermissionApproval(
      approvalId: approvalId,
      dispatchId: dispatchId,
      dispatchFence: fence,
      profileDigest: digest,
    );
  }

  /// Authorizes one run against one approval, exactly once.
  ///
  /// Returns true the first time and on a retry of the same run, so a rerun of
  /// the same attempt is not punished, while a second run against a spent
  /// approval is refused.
  Future<bool> consume({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String approvalId,
    required AgentPermissionCallback callback,
  }) => _transition(
    principal: principal,
    workspaceId: workspaceId,
    approvalId: approvalId,
    callback: callback,
    from: const {'approved', 'consumed'},
    to: 'consumed',
  );

  /// Marks the approval spent after the installer published its result.
  Future<bool> complete({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String approvalId,
    required AgentPermissionCallback callback,
  }) => _transition(
    principal: principal,
    workspaceId: workspaceId,
    approvalId: approvalId,
    callback: callback,
    from: const {'consumed', 'completed'},
    to: 'completed',
  );

  Future<bool> _transition({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String approvalId,
    required AgentPermissionCallback callback,
    required Set<String> from,
    required String to,
  }) async {
    final ref = _approvalRef(workspaceId, approvalId);
    final fenceRef = _fenceRef(workspaceId, principal.repository);
    return store.firestore.runTransaction<bool>((transaction) async {
      final data = (await transaction.get(ref)).data();
      final fence = (await transaction.get(fenceRef)).data()?['fence'];
      if (data == null || !agentPermissionApprovalMatches(data, callback)) {
        throw _approvalInvalid;
      }
      if (data['repository'] != principal.repository) throw _approvalInvalid;
      if (fence is! int || callback.dispatchFence < fence) throw _superseded;
      if (!from.contains(data['status'])) throw _approvalSpent;
      final boundRun = data['workflowRunId'];
      if (boundRun != null &&
          (boundRun != principal.runId ||
              data['workflowRunAttempt'] != principal.runAttempt ||
              data['workflowSha'] != principal.sha)) {
        throw _runUnbound;
      }
      transaction.set(ref, {
        'status': to,
        'workflowRunId': principal.runId,
        'workflowRunAttempt': principal.runAttempt,
        'workflowSha': principal.sha,
        '${to}At': Timestamp.now(),
      }, options: const SetOptions.merge());
      return true;
    });
  }

  DocumentReference<Map<String, Object?>> _approvalRef(
    String workspaceId,
    String approvalId,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('agentPermissionApprovals')
      .doc(approvalId);

  DocumentReference<Map<String, Object?>> _fenceRef(
    String workspaceId,
    String repository,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('agentPermissionFences')
      .doc(sha256.convert(utf8.encode(repository)).toString());
}

/// Values a dispatch must carry so the run can prove it was approved.
final class AgentPermissionApproval {
  const AgentPermissionApproval({
    required this.approvalId,
    required this.dispatchId,
    required this.dispatchFence,
    required this.profileDigest,
  });

  final String approvalId;
  final String dispatchId;
  final int dispatchFence;
  final String profileDigest;
}

/// What an installer run claims it is installing.
final class AgentPermissionCallback {
  const AgentPermissionCallback({
    required this.workspaceId,
    required this.dispatchId,
    required this.dispatchFence,
    required this.profileId,
    required this.profileVersion,
    required this.profileDigest,
    required this.profileJson,
  });

  final String workspaceId;
  final String dispatchId;
  final int dispatchFence;
  final String profileId;
  final String profileVersion;
  final String profileDigest;
  final String profileJson;
}

/// Whether a callback describes exactly the approved install, field for field.
bool agentPermissionApprovalMatches(
  Map<String, Object?> approval,
  AgentPermissionCallback callback,
) =>
    approval['workspaceId'] == callback.workspaceId &&
    approval['dispatchId'] == callback.dispatchId &&
    approval['dispatchFence'] == callback.dispatchFence &&
    approval['profileId'] == callback.profileId &&
    approval['profileVersion'] == callback.profileVersion &&
    approval['profileDigest'] == callback.profileDigest &&
    approval['profileJson'] == callback.profileJson;

/// Parses an installer callback body, rejecting anything the workflow itself
/// would not have been allowed to send.
AgentPermissionCallback parseAgentPermissionCallback(
  Map<String, Object?> body,
) {
  String text(String name, RegExp pattern, {int maxLength = 200}) {
    final value = body[name];
    if (value is! String ||
        value.length > maxLength ||
        !pattern.hasMatch(value)) {
      throw _callbackInvalid;
    }
    return value;
  }

  final fence = body['dispatch_fence'];
  final profileJson = body['profile_json'];
  if (fence is! int ||
      fence <= 0 ||
      profileJson is! String ||
      profileJson.length > 50000) {
    throw _callbackInvalid;
  }
  return AgentPermissionCallback(
    workspaceId: text('workspace_id', _identifierPattern),
    dispatchId: text('dispatch_id', _dispatchPattern),
    dispatchFence: fence,
    profileId: text('profile_id', _profilePattern),
    profileVersion: text('profile_version', _profilePattern),
    profileDigest: text('profile_digest', _digestPattern, maxLength: 64),
    profileJson: profileJson,
  );
}

String _identifier(String prefix) {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return '$prefix-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _identifierPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final _dispatchPattern = RegExp(r'^[A-Za-z0-9_-]{20,128}$');
final _profilePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

const _callbackInvalid = ApiError(
  400,
  'agent_permission_callback_invalid',
  'The permission installer sent an unreadable authorization request.',
);
const _approvalInvalid = ApiError(
  403,
  'agent_permission_approval_invalid',
  'No human approval matches this permission install.',
);
const _approvalSpent = ApiError(
  409,
  'agent_permission_approval_spent',
  'This permission approval was already used.',
);
const _superseded = ApiError(
  409,
  'agent_permission_approval_superseded',
  'A newer permission approval supersedes this install.',
);
const _runUnbound = ApiError(
  403,
  'agent_permission_run_unbound',
  'This approval belongs to a different workflow run.',
);
