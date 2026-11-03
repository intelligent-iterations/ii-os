part of 'agent_activation_store.dart';

extension AgentActivationWorkflowStore on AgentActivationStore {
  Future<Map<String, Object?>> recordFleetState({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
    required String fleetJobId,
    required String fleetLeaseId,
    required String state,
  }) async {
    final execution = FleetAgentExecution.parseCallback(
      repositoryId: principal.repositoryId,
      runId: principal.runId,
      runAttempt: principal.runAttempt,
      jobId: fleetJobId,
      leaseId: fleetLeaseId,
      state: state,
    );
    if (execution == null) throw _fleetStateInvalid;
    final activationRef = _ref(workspaceId, projectItemId);
    final dispatchRef = _dispatchRef(workspaceId, projectItemId);
    return store.firestore.runTransaction<Map<String, Object?>>((
      transaction,
    ) async {
      final activation = (await transaction.get(activationRef)).data();
      final dispatch = (await transaction.get(dispatchRef)).data();
      if (activation?['status'] != 'consumed' ||
          activation?['claimId'] != claimId ||
          activation?['repository'] != principal.repository ||
          activation?['repositoryId'] != principal.repositoryId ||
          activation?['projectItemId'] != projectItemId ||
          activation?['issueNumber'] != issueNumber ||
          !agentActivationWorkflowRunMatches(
            activation,
            principal,
            allowNewerAttempt: false,
          ) ||
          dispatch?['workflowRunId'] != principal.runId ||
          dispatch?['workflowRunAttempt'] != principal.runAttempt ||
          dispatch?['workflowSha'] != principal.sha ||
          (dispatch?['fleetJobId'] != null &&
              dispatch?['fleetJobId'] != execution.identity.executionId) ||
          (dispatch?['fleetLeaseId'] != null &&
              fleetLeaseId.isNotEmpty &&
              dispatch?['fleetLeaseId'] != execution.identity.reservationId)) {
        throw _fleetStateInvalid;
      }
      final nextStatus = agentFleetDispatchStatusTransition(
        dispatch?['status'] as String? ?? '',
        state,
      );
      if (nextStatus == null) throw _fleetStateInvalid;
      final timestamp = Timestamp.now();
      transaction.set(dispatchRef, {
        'status': nextStatus,
        'fleetJobId': fleetJobId,
        if (fleetLeaseId.isNotEmpty) 'fleetLeaseId': fleetLeaseId,
        if (state == 'submitting') 'fleetSubmissionAuthorizedAt': timestamp,
        if (state == 'submission_failed') 'fleetSubmissionFailedAt': timestamp,
        if (state == 'queued') 'fleetQueuedAt': timestamp,
        if (state == 'running') 'fleetRunningAt': timestamp,
        if (state == 'cleaning') 'fleetCleaningAt': timestamp,
        if (state == 'cleaned') 'fleetCleanedAt': timestamp,
        'updatedAt': timestamp,
      }, options: const SetOptions.merge());
      return {
        'recorded': true,
        'status': nextStatus,
        'fleetJobId': fleetJobId,
        'projectId': activation!['projectId'],
        'projectStatusFieldId': activation['projectStatusFieldId'],
        'projectInProgressOptionId': activation['projectInProgressOptionId'],
      };
    });
  }

  Future<Map<String, Object?>> consumeFromWorkflow({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
    required String permissionProfile,
    required String permissionDigest,
    AgentQueueTicket? currentTicket,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    return store.firestore.runTransaction<Map<String, Object?>>((
      transaction,
    ) async {
      final data = (await transaction.get(ref)).data();
      final now = DateTime.now().toUtc();
      final promptValue = data?['ticketPrompt'];
      final prompt = promptValue is Map
          ? promptValue.cast<String, Object?>()
          : null;
      final promptDigest = data?['ticketPromptDigest'];
      final promptJson = prompt == null ? '' : _canonicalPromptJson(prompt);
      final promptValid =
          prompt != null &&
          promptDigest is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(promptDigest) &&
          sha256.convert(utf8.encode(promptJson)).toString() == promptDigest;
      final exactRun = agentActivationWorkflowRunMatches(
        data,
        principal,
        allowNewerAttempt: false,
      );
      if (data?['status'] == 'consumed' &&
          data?['claimId'] == claimId &&
          exactRun &&
          promptValid) {
        return {
          'consumed': true,
          'idempotent': true,
          'ticketPrompt': prompt,
          'ticketPromptJson': promptJson,
          'ticketPromptDigest': promptDigest,
        };
      }
      final projectId = data?['projectId'];
      final workflowMayBind = agentActivationWorkflowMaySelfBind(
        data,
        principal,
        now,
      );
      if (data?['status'] != 'claiming' ||
          data?['claimId'] != claimId ||
          !_claimInFlight(data, now) ||
          projectId is! String ||
          projectId.isEmpty ||
          data?['repository'] != principal.repository ||
          data?['repositoryId'] != principal.repositoryId ||
          data?['projectItemId'] != projectItemId ||
          data?['issueNumber'] != issueNumber ||
          data?['permissionProfile'] != permissionProfile ||
          data?['permissionDigest'] != permissionDigest ||
          data?['permissionRef'] != 'dev' ||
          data?['workflowFile'] != iiOsAgentTaskWorkflow ||
          data?['trustedSourceSha'] != principal.sha ||
          data?['trustedSourceRef'] != principal.trustedRef ||
          !promptValid ||
          data?['claimConfirmedAt'] is! Timestamp ||
          currentTicket == null ||
          !dispatchedAgentActivationTicketMatches(
            data!,
            projectId: projectId,
            ticket: currentTicket,
          ) ||
          (!exactRun && !workflowMayBind)) {
        throw _approvalInvalid;
      }
      if (!workflowMayBind &&
          !agentActivationWorkflowRunMatches(
            data,
            principal,
            allowNewerAttempt: true,
          )) {
        throw _runUnbound;
      }
      final boundAt = Timestamp.fromDate(now);
      transaction.update(ref, {
        'status': 'consumed',
        'consumedAt': Timestamp.fromDate(now),
        if (workflowMayBind) 'workflowRunId': principal.runId,
        'workflowRunAttempt': principal.runAttempt,
        if (workflowMayBind) 'workflowSha': principal.sha,
        if (workflowMayBind)
          'workflowRunUrl':
              'https://github.com/${principal.repository}/actions/runs/${principal.runId}',
        if (workflowMayBind) 'workflowBoundAt': boundAt,
        'workflowActor': principal.actor,
        'claimExpiresAt': null,
        'updatedAt': Timestamp.fromDate(now),
      });
      transaction.set(_dispatchRef(workspaceId, projectItemId), {
        'status': 'workflow_bound',
        'workflowRunId': principal.runId,
        'workflowRunAttempt': principal.runAttempt,
        'workflowSha': principal.sha,
        'workflowRunUrl':
            'https://github.com/${principal.repository}/actions/runs/${principal.runId}',
        'workflowBoundAt': boundAt,
        'updatedAt': boundAt,
      }, options: const SetOptions.merge());
      return {
        'consumed': true,
        'idempotent': false,
        'ticketPrompt': prompt,
        'ticketPromptJson': promptJson,
        'ticketPromptDigest': promptDigest,
      };
    });
  }

  Future<Map<String, Object?>> workflowApproval({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
    required String permissionProfile,
    required String permissionDigest,
  }) async {
    final data = (await _ref(workspaceId, projectItemId).get()).data();
    final promptValue = data?['ticketPrompt'];
    final prompt = promptValue is Map
        ? promptValue.cast<String, Object?>()
        : null;
    final promptDigest = data?['ticketPromptDigest'];
    final promptValid =
        prompt != null &&
        promptDigest is String &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(promptDigest) &&
        sha256.convert(utf8.encode(_canonicalPromptJson(prompt))).toString() ==
            promptDigest;
    final boundRun = agentActivationWorkflowRunMatches(
      data,
      principal,
      allowNewerAttempt: data?['status'] == 'claiming',
    );
    final now = DateTime.now().toUtc();
    final workflowMayBind = agentActivationWorkflowMaySelfBind(
      data,
      principal,
      now,
    );
    final common =
        data?['claimId'] == claimId &&
        data?['repository'] == principal.repository &&
        data?['repositoryId'] == principal.repositoryId &&
        data?['projectItemId'] == projectItemId &&
        data?['issueNumber'] == issueNumber &&
        data?['permissionProfile'] == permissionProfile &&
        data?['permissionDigest'] == permissionDigest &&
        data?['permissionRef'] == 'dev' &&
        data?['workflowFile'] == iiOsAgentTaskWorkflow &&
        data?['trustedSourceSha'] == principal.sha &&
        data?['trustedSourceRef'] == principal.trustedRef &&
        data?['projectId'] is String &&
        (data?['projectId'] as String).isNotEmpty &&
        data?['projectStatusFieldId'] is String &&
        (data?['projectStatusFieldId'] as String).isNotEmpty &&
        data?['projectInProgressOptionId'] is String &&
        (data?['projectInProgressOptionId'] as String).isNotEmpty &&
        promptValid;
    if (!common ||
        (data?['status'] != 'claiming' && data?['status'] != 'consumed')) {
      throw _approvalInvalid;
    }
    if (!boundRun && !workflowMayBind) throw _runUnbound;
    return {
      'projectId': data!['projectId'],
      'projectStatusFieldId': data['projectStatusFieldId'],
      'projectInProgressOptionId': data['projectInProgressOptionId'],
      'alreadyConsumed': data['status'] == 'consumed',
    };
  }

  /// Returns the frozen repository authority for an exact consumed run.
  ///
  /// Publication happens after the Fleet runtime and its credentials are
  /// gone. Re-reading the mutable profile file here would let a later commit
  /// widen an earlier approval, so this method verifies and uses the snapshot
  /// stored on the activation receipt.
  Future<AgentRepositoryPolicy> repositoryPolicyForFinalization({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
  }) async => (await profileForConsumedRun(
    principal: principal,
    workspaceId: workspaceId,
    projectItemId: projectItemId,
    claimId: claimId,
    issueNumber: issueNumber,
  )).repository;

  Future<AgentPermissionProfile> profileForConsumedRun({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
    bool allowCleanupRecovery = false,
  }) async {
    final data = (await _ref(workspaceId, projectItemId).get()).data();
    final snapshotValue = data?['permissionProfileSnapshot'];
    final snapshot = snapshotValue is Map
        ? snapshotValue.cast<String, Object?>()
        : null;
    AgentPermissionProfile? profile;
    try {
      profile = snapshot == null
          ? null
          : AgentPermissionProfile.parse(snapshot);
    } on ApiError {
      throw _approvalInvalid;
    }
    final exactRun =
        data?['workflowRunId'] == principal.runId &&
        (data?['workflowRunAttempt'] == principal.runAttempt ||
            (allowCleanupRecovery &&
                data?['workflowRunAttempt'] is int &&
                principal.runAttempt >
                    (data!['workflowRunAttempt']! as int))) &&
        data?['workflowSha'] == principal.sha;
    if (data?['status'] != 'consumed' ||
        data?['claimId'] != claimId ||
        data?['repository'] != principal.repository ||
        data?['repositoryId'] != principal.repositoryId ||
        data?['projectItemId'] != projectItemId ||
        data?['issueNumber'] != issueNumber ||
        data?['permissionProfile'] != profile?.id ||
        data?['permissionVersion'] != profile?.version ||
        data?['permissionDigest'] !=
            (profile == null ? null : agentPermissionProfileDigest(profile)) ||
        !exactRun) {
      throw _approvalInvalid;
    }
    return profile!;
  }

  Future<bool> bindWorkflowRun({
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required String repository,
    required int repositoryId,
    required int issueNumber,
    required int runId,
    required int runAttempt,
    required String workflowSha,
    required String workflowRunUrl,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    return store.firestore.runTransaction<bool>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data?['claimId'] != claimId ||
          data?['repository'] != repository ||
          data?['repositoryId'] != repositoryId ||
          data?['issueNumber'] != issueNumber ||
          data?['projectItemId'] != projectItemId ||
          data?['claimConfirmedAt'] is! Timestamp ||
          (data?['status'] != 'claiming' && data?['status'] != 'consumed')) {
        return false;
      }
      final alreadyBound = data?['workflowRunId'] != null;
      final exact =
          data?['workflowRunId'] == runId &&
          data?['workflowRunAttempt'] == runAttempt &&
          data?['workflowSha'] == workflowSha;
      if (alreadyBound || data?['status'] == 'consumed') {
        return exact;
      }
      if (data?['trustedSourceSha'] != workflowSha) return false;
      transaction.update(ref, {
        'workflowRunId': runId,
        'workflowRunAttempt': runAttempt,
        'workflowSha': workflowSha,
        'workflowRunUrl': workflowRunUrl,
        'workflowBoundAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
      return true;
    });
  }
}

/// Retained for callers reading the historical Fleet dispatch contract.
String? agentFleetDispatchStatusTransition(String current, String event) =>
    FleetAgentExecution.transition(current, event);

const _fleetStateInvalid = ApiError(
  409,
  'agent_fleet_state_invalid',
  'This Fleet lifecycle update does not match the approved workflow run.',
);
