import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'agent_permission_profile.dart';
import 'agent_ticket_activation.dart';
import 'agent_ticket_dispatcher.dart';
import 'agent_workflow_recovery.dart';
import 'api_error.dart';
import 'auth_service.dart';
import 'github_actions_oidc.dart';
import 'provider_contracts/agent_execution.dart';
import 'providers/fleet/agent_execution.dart';
import 'ticket_content.dart';
import 'workspace_store.dart';

part 'agent_activation_workflow_store.dart';
part 'agent_execution_state_store.dart';
part 'agent_activation_recovery_state.dart';
part 'agent_ticket_reset.dart';
part 'agent_activation_reset_store.dart';

final class AgentActivationClaim {
  const AgentActivationClaim({
    required this.profile,
    required this.trustedSourceSha,
    required this.trustedSourceRef,
  });

  final AgentPermissionProfile profile;
  final String trustedSourceSha;
  final String trustedSourceRef;

  bool hasSameAuthority(AgentActivationClaim other) =>
      trustedSourceSha == other.trustedSourceSha &&
      trustedSourceRef == other.trustedSourceRef &&
      profile.id == other.profile.id &&
      profile.version == other.profile.version &&
      agentPermissionProfileDigest(profile) ==
          agentPermissionProfileDigest(other.profile);
}

/// Resolves execution authority only from the immutable human approval.
///
/// The mutable `dev` branch can advance after the click. That must neither
/// widen the approval nor make the approved pass ambiguous.
AgentActivationClaim? approvedAgentActivationClaim(
  Map<String, Object?> data, {
  required String projectId,
  required AgentQueueTicket ticket,
}) {
  final snapshotValue = data['permissionProfileSnapshot'];
  final snapshot = snapshotValue is Map
      ? snapshotValue.cast<String, Object?>()
      : null;
  AgentPermissionProfile? profile;
  try {
    profile = snapshot == null ? null : AgentPermissionProfile.parse(snapshot);
  } on ApiError {
    return null;
  }
  final trustedSourceSha = data['trustedSourceSha'];
  final trustedSourceRef = data['trustedSourceRef'];
  if (profile == null ||
      !_matchesActivationTicket(data, projectId, ticket) ||
      data['permissionVersion'] != profile.version ||
      data['permissionDigest'] != agentPermissionProfileDigest(profile) ||
      data['workflowFile'] != profile.workflow.file ||
      profile.workflow.file != iiOsAgentTaskWorkflow ||
      profile.workflow.ref != ticket.permissionRef ||
      trustedSourceSha is! String ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(trustedSourceSha) ||
      trustedSourceRef != 'ii-os-agent-v4-$trustedSourceSha') {
    return null;
  }
  return AgentActivationClaim(
    profile: profile,
    trustedSourceSha: trustedSourceSha,
    trustedSourceRef: trustedSourceRef as String,
  );
}

final class AgentActivationStore {
  AgentActivationStore(this.store);

  final WorkspaceStore store;

  Future<void> activate({
    required String workspaceId,
    required String projectId,
    required String projectStatusFieldId,
    required String projectInProgressOptionId,
    required String projectItemId,
    required int repositoryId,
    required String repository,
    required int issueNumber,
    required String title,
    required TicketContent ticket,
    required String activationResponse,
    required AgentPermissionProfile profile,
    required String trustedSourceSha,
    required String trustedSourceRef,
    required AuthenticatedUser actor,
    AgentWorkflowRecoveryProof? recoveryProof,
  }) async {
    final prompt = agentTicketPromptSnapshot(
      projectId: projectId,
      projectItemId: projectItemId,
      repositoryId: repositoryId,
      repository: repository,
      issueNumber: issueNumber,
      title: title,
      ticket: ticket,
      activationResponse: activationResponse,
    );
    final promptJson = _canonicalPromptJson(prompt);
    final now = Timestamp.now();
    final ref = _ref(workspaceId, projectItemId);
    final dispatchRef = _dispatchRef(workspaceId, projectItemId);
    await store.firestore.runTransaction<void>((transaction) async {
      final current = (await transaction.get(ref)).data();
      final dispatch = (await transaction.get(dispatchRef)).data();
      final currentRecoveryStatus = dispatch == null
          ? null
          : agentDispatchRecoveryStatus(
                  dispatch,
                  current ?? const {},
                  now.toDate().toUtc(),
                ) ??
                (agentWorkflowStopProofStatuses.contains(dispatch['status'])
                    ? dispatch['status'] as String
                    : null);
      if (currentRecoveryStatus != null &&
          !(recoveryProof?.matches(
                dispatch!,
                currentRecoveryStatus,
                activation: current ?? const {},
              ) ??
              false)) {
        throw _recoveryProofRequired;
      }
      if (agentPickupInFlight(current, dispatch, now.toDate().toUtc())) {
        throw _pickupStarted;
      }
      if (agentActivationRequiresResponse(
            current ?? const {},
            currentTicketBodyDigest: ticketBodyDigest(ticket),
          ) &&
          activationResponse.trim().isEmpty) {
        throw _responseRequired;
      }
      transaction.set(ref, {
        'workspaceId': workspaceId,
        'projectId': projectId,
        'projectStatusFieldId': projectStatusFieldId,
        'projectInProgressOptionId': projectInProgressOptionId,
        'projectItemId': projectItemId,
        'repositoryId': repositoryId,
        'repository': repository,
        'issueNumber': issueNumber,
        'ticketTitle': title,
        'ticketBodyDigest': ticketBodyDigest(ticket),
        'ticketPrompt': prompt,
        'ticketPromptDigest': sha256
            .convert(utf8.encode(promptJson))
            .toString(),
        'permissionProfile': profile.id,
        'permissionVersion': profile.version,
        'permissionDigest': agentPermissionProfileDigest(profile),
        'permissionRef': ticket.permissionRef,
        // A frozen copy of what this run was allowed to do, denormalized on
        // purpose. The profile is a file on a branch and will move on; months
        // later "what could this agent actually touch" has to be answerable
        // from the receipt itself, not from whatever the branch says now.
        // A sibling field, deliberately not inside `ticketPrompt`, whose
        // canonical digest above must not change.
        'permissionProfileSnapshot': boundedAgentPermissionSnapshot(profile),
        'workflowFile': profile.workflow.file,
        'trustedSourceSha': trustedSourceSha,
        'trustedSourceRef': trustedSourceRef,
        'approvedByUid': actor.uid,
        'approvedByEmail': actor.email,
        'approvedAt': now,
        'status': 'active',
        'claimId': null,
        'claimExpiresAt': null,
        'updatedAt': now,
      });
      transaction.set(dispatchRef, {
        'workspaceId': workspaceId,
        'projectId': projectId,
        'projectItemId': projectItemId,
        'repository': repository,
        'issueNumber': issueNumber,
        'status': 'queued',
        'approvedAt': now,
        'updatedAt': now,
      });
    });
  }

  Future<void> revoke({
    required String workspaceId,
    required String projectItemId,
    required AuthenticatedUser actor,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    final dispatchRef = _dispatchRef(workspaceId, projectItemId);
    await store.firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = snapshot.data();
      if (current == null) return;
      final now = DateTime.now().toUtc();
      final dispatch = (await transaction.get(dispatchRef)).data();
      if (agentPickupInFlight(current, dispatch, now)) throw _pickupStarted;
      final timestamp = Timestamp.fromDate(now);
      transaction.update(ref, {
        'status': 'revoked',
        'revokedByUid': actor.uid,
        'revokedAt': timestamp,
        'claimId': null,
        'claimExpiresAt': null,
        'updatedAt': timestamp,
      });
      transaction.set(dispatchRef, {
        'status': 'paused',
        'pausedByUid': actor.uid,
        'pausedAt': timestamp,
        'updatedAt': timestamp,
      }, options: const SetOptions.merge());
    });
  }

  Future<AgentActivationClaim?> claim({
    required String workspaceId,
    required String projectId,
    required AgentQueueTicket ticket,
    required String claimId,
  }) async {
    final ref = _ref(workspaceId, ticket.itemId);
    return store.firestore.runTransaction<AgentActivationClaim?>((
      transaction,
    ) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) return null;
      final now = DateTime.now().toUtc();
      final claimExpiresAt = data['claimExpiresAt'];
      final staleClaim =
          data['status'] == 'claiming' &&
          claimExpiresAt is Timestamp &&
          !claimExpiresAt.toDate().toUtc().isAfter(now);
      if (data['status'] != 'active' && !staleClaim) return null;
      final approval = approvedAgentActivationClaim(
        data,
        projectId: projectId,
        ticket: ticket,
      );
      if (approval == null) {
        final timestamp = Timestamp.fromDate(now);
        transaction.update(ref, {
          'status': 'invalidated',
          'invalidatedAt': timestamp,
          'claimId': null,
          'claimExpiresAt': null,
          'updatedAt': timestamp,
        });
        transaction.set(
          _dispatchRef(workspaceId, ticket.itemId),
          {
            'status': 'approval_invalidated',
            'failureCode': 'agent_approval_invalidated',
            'detail': agentApprovalInvalidatedDetail,
            'updatedAt': timestamp,
          },
          options: const SetOptions.merge(),
        );
        return null;
      }
      transaction.update(ref, {
        'status': 'claiming',
        'claimId': claimId,
        'claimedAt': Timestamp.fromDate(now),
        'claimExpiresAt': Timestamp.fromDate(
          now.add(const Duration(minutes: 15)),
        ),
        'updatedAt': Timestamp.fromDate(now),
      });
      return approval;
    });
  }

  Future<bool> confirmClaim({
    required String workspaceId,
    required String projectId,
    required AgentQueueTicket ticket,
    required AgentActivationClaim approval,
    required String claimId,
  }) async {
    final ref = _ref(workspaceId, ticket.itemId);
    return store.firestore.runTransaction<bool>((transaction) async {
      final data = (await transaction.get(ref)).data();
      final now = DateTime.now().toUtc();
      if (data?['status'] != 'claiming' ||
          data?['claimId'] != claimId ||
          !_claimInFlight(data, now)) {
        return false;
      }
      final currentApproval = approvedAgentActivationClaim(
        data!,
        projectId: projectId,
        ticket: ticket,
      );
      if (currentApproval == null ||
          !currentApproval.hasSameAuthority(approval)) {
        final timestamp = Timestamp.fromDate(now);
        transaction.update(ref, {
          'status': 'invalidated',
          'invalidatedAt': timestamp,
          'claimId': null,
          'claimExpiresAt': null,
          'updatedAt': timestamp,
        });
        transaction.set(
          _dispatchRef(workspaceId, ticket.itemId),
          {
            'status': 'approval_invalidated',
            'failureCode': 'agent_approval_invalidated',
            'detail': agentApprovalInvalidatedDetail,
            'updatedAt': timestamp,
          },
          options: const SetOptions.merge(),
        );
        return false;
      }
      transaction.update(ref, {
        'claimConfirmedAt': Timestamp.fromDate(now),
        'claimExpiresAt': Timestamp.fromDate(
          now.add(const Duration(minutes: 150)),
        ),
        'updatedAt': Timestamp.fromDate(now),
      });
      return true;
    });
  }

  Future<Map<String, Object?>> claimedPrompt({
    required String workspaceId,
    required String projectItemId,
    required String claimId,
  }) async {
    final data = (await _ref(workspaceId, projectItemId).get()).data();
    final promptValue = data?['ticketPrompt'];
    final prompt = promptValue is Map
        ? promptValue.cast<String, Object?>()
        : null;
    final digest = data?['ticketPromptDigest'];
    if (data?['status'] != 'claiming' ||
        data?['claimId'] != claimId ||
        prompt == null ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        sha256.convert(utf8.encode(_canonicalPromptJson(prompt))).toString() !=
            digest) {
      throw const ApiError(
        409,
        'agent_dispatch_prompt_invalid',
        'The exact human-approved ticket prompt is unavailable.',
      );
    }
    return {
      'prompt': prompt,
      'promptJson': _canonicalPromptJson(prompt),
      'digest': digest,
    };
  }

  Future<bool> release({
    required String workspaceId,
    required String projectItemId,
    required String claimId,
  }) => _transitionClaim(
    workspaceId: workspaceId,
    projectItemId: projectItemId,
    claimId: claimId,
    status: 'active',
  );

  Future<bool> consume({
    required String workspaceId,
    required String projectItemId,
    required String claimId,
  }) => _transitionClaim(
    workspaceId: workspaceId,
    projectItemId: projectItemId,
    claimId: claimId,
    status: 'consumed',
  );

  Future<bool> _transitionClaim({
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required String status,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    return store.firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data?['status'] != 'claiming' || data?['claimId'] != claimId) {
        return false;
      }
      transaction.update(ref, {
        'status': status,
        if (status == 'consumed') 'consumedAt': Timestamp.now(),
        'claimId': null,
        'claimExpiresAt': null,
        'updatedAt': Timestamp.now(),
      });
      return true;
    });
  }

  DocumentReference<Map<String, Object?>> _ref(
    String workspaceId,
    String projectItemId,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('agentActivations')
      .doc(projectItemId);

  DocumentReference<Map<String, Object?>> _dispatchRef(
    String workspaceId,
    String projectItemId,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('agentDispatches')
      .doc(projectItemId);
}

bool _matchesActivationTicket(
  Map<String, Object?> data,
  String projectId,
  AgentQueueTicket ticket,
) =>
    _activationTicketFieldsMatch(data, projectId, ticket) &&
    ticket.status == 'Todo';

/// Revalidates the exact ticket while it waits for authoritative Fleet-running
/// evidence. Dispatch and coordinator startup leave the Project status in Todo.
bool dispatchedAgentActivationTicketMatches(
  Map<String, Object?> data, {
  required String projectId,
  required AgentQueueTicket ticket,
}) =>
    _activationTicketFieldsMatch(data, projectId, ticket) &&
    ticket.status == 'Todo';

bool _activationTicketFieldsMatch(
  Map<String, Object?> data,
  String projectId,
  AgentQueueTicket ticket,
) =>
    data['projectId'] == projectId &&
    data['projectItemId'] == ticket.itemId &&
    data['repositoryId'] == ticket.repositoryId &&
    data['repository'] == ticket.repository &&
    data['issueNumber'] == ticket.issueNumber &&
    data['ticketTitle'] == ticket.title &&
    data['ticketBodyDigest'] == ticketBodyDigest(ticket.content) &&
    data['permissionProfile'] == ticket.permissionProfile &&
    data['permissionRef'] == ticket.permissionRef &&
    data['permissionProfile'] == ticket.content.permissionProfile &&
    data['permissionRef'] == ticket.content.permissionRef;

/// Matches one dispatch across GitHub rerun attempts until it is consumed.
///
/// GitHub keeps `run_id` and the immutable source SHA stable when rerunning a
/// workflow and increments `run_attempt`. Once consumed, callers pass
/// `allowNewerAttempt: false` so all later operations remain exact-attempt
/// bound.
bool agentActivationWorkflowRunMatches(
  Map<String, Object?>? data,
  GitHubActionsPrincipal principal, {
  required bool allowNewerAttempt,
}) {
  final storedAttempt = data?['workflowRunAttempt'];
  return data?['workflowRunId'] == principal.runId &&
      data?['workflowSha'] == principal.sha &&
      storedAttempt is int &&
      storedAttempt > 0 &&
      (allowNewerAttempt
          ? principal.runAttempt >= storedAttempt
          : principal.runAttempt == storedAttempt);
}

/// The verified workflow can bind its own immutable run identity when the
/// dispatching HTTP request did not survive long enough to observe GitHub's
/// workflow run. This removes the browser/API process as a split-brain owner.
bool agentActivationWorkflowMaySelfBind(
  Map<String, Object?>? data,
  GitHubActionsPrincipal principal,
  DateTime now,
) =>
    data?['workflowRunId'] == null &&
    data?['status'] == 'claiming' &&
    data?['claimConfirmedAt'] is Timestamp &&
    _claimInFlight(data, now) &&
    data?['repository'] == principal.repository &&
    data?['repositoryId'] == principal.repositoryId &&
    data?['trustedSourceSha'] == principal.sha &&
    data?['trustedSourceRef'] == principal.trustedRef;

bool _claimInFlight(Map<String, Object?>? data, DateTime now) {
  final expiresAt = data?['claimExpiresAt'];
  return data?['status'] == 'claiming' &&
      expiresAt is Timestamp &&
      expiresAt.toDate().toUtc().isAfter(now);
}

const _approvalInvalid = ApiError(
  409,
  'agent_dispatch_approval_invalid',
  'This workflow run is not bound to an unconsumed human approval.',
);

const _responseRequired = ApiError(
  422,
  'agent_response_required',
  'Answer the agent question before approving another agent pass.',
);

const agentApprovalInvalidatedDetail =
    'The ticket or its approved agent access changed. Review and deploy it again.';

const _runUnbound = ApiError(
  409,
  'agent_dispatch_run_unbound',
  'ii-os has not bound this exact GitHub workflow run yet.',
);

const _pickupStarted = ApiError(
  409,
  'agent_ticket_pickup_started',
  'The deployment has started and can no longer be changed.',
);

const _recoveryProofRequired = ApiError(
  409,
  'agent_recovery_workflow_active',
  'The previous workflow must be stopped and rechecked before this ticket can deploy again.',
);

String _canonicalPromptJson(Map<String, Object?> prompt) =>
    jsonEncode(_canonicalJsonValue(prompt));

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Prompt keys must be strings.');
      }
      sorted[entry.key as String] = _canonicalJsonValue(entry.value);
    }
    return sorted;
  }
  if (value is List) return value.map(_canonicalJsonValue).toList();
  return value;
}

String ticketBodyDigest(TicketContent ticket) =>
    sha256.convert(utf8.encode(ticket.toMarkdown())).toString();

Map<String, Object?> agentTicketPromptSnapshot({
  required String projectId,
  required String projectItemId,
  required int repositoryId,
  required String repository,
  required int issueNumber,
  required String title,
  required TicketContent ticket,
  required String activationResponse,
}) => {
  'schema_version': 1,
  'project_id': projectId,
  'project_item_id': projectItemId,
  'repository_id': repositoryId,
  'repository': repository,
  'issue_number': issueNumber,
  'title': title,
  'body': ticket.toMarkdown(),
  'activation_response': activationResponse,
};
