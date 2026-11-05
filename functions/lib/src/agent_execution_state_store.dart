part of 'agent_activation_store.dart';

extension AgentExecutionStateStore on AgentActivationStore {
  Future<Map<String, Object?>> recordExecutionState({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
    required String backendId,
    required AgentExecutionUpdate update,
    required String inputDigest,
    required String artifactDigest,
  }) async {
    final activationRef = _ref(workspaceId, projectItemId);
    final dispatchRef = _dispatchRef(workspaceId, projectItemId);
    return store.firestore.runTransaction<Map<String, Object?>>((
      transaction,
    ) async {
      final activation = (await transaction.get(activationRef)).data();
      final dispatch = (await transaction.get(dispatchRef)).data();
      AgentPermissionProfile? profile;
      try {
        profile = AgentPermissionProfile.parse(
          activation?['permissionProfileSnapshot'],
          engines: engines,
        );
      } on ApiError {
        throw _executionStateInvalid;
      }
      final cleanupRecovery = agentExecutionCleanupRecoveryAllowed(
        activation: activation ?? const {},
        dispatch: dispatch ?? const {},
        principal: principal,
        update: update,
        inputDigest: inputDigest,
        artifactDigest: artifactDigest,
      );
      if (profile.runtime == null ||
          activation?['permissionDigest'] !=
              agentPermissionProfileDigest(profile) ||
          activation?['permissionProfile'] != profile.id ||
          activation?['permissionVersion'] != profile.version ||
          activation?['status'] != 'consumed' ||
          activation?['claimId'] != claimId ||
          activation?['repository'] != principal.repository ||
          activation?['repositoryId'] != principal.repositoryId ||
          activation?['projectItemId'] != projectItemId ||
          activation?['issueNumber'] != issueNumber ||
          !agentActivationWorkflowRunMatches(
            activation,
            principal,
            allowNewerAttempt: cleanupRecovery,
          ) ||
          dispatch?['workflowRunId'] != principal.runId ||
          (dispatch?['workflowRunAttempt'] != principal.runAttempt &&
              !cleanupRecovery) ||
          dispatch?['workflowSha'] != principal.sha ||
          !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(inputDigest) ||
          !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(artifactDigest)) {
        throw _executionStateInvalid;
      }
      final identity = update.identity;
      for (final entry in {
        'executionBackend': backendId,
        'executionId': identity.executionId,
        'executionInputDigest': inputDigest,
        'executionArtifactDigest': artifactDigest,
        if (identity.reservationId != null)
          'executionReservationId': identity.reservationId,
      }.entries) {
        if (dispatch?[entry.key] != null &&
            dispatch?[entry.key] != entry.value) {
          throw _executionStateInvalid;
        }
      }
      final previousName = dispatch?['executionState'];
      final previous =
          previousName == null &&
              const {
                'workflow_bound',
                'dispatched',
                'workflow_unconfirmed',
              }.contains(dispatch?['status'])
          ? AgentExecutionState.ready
          : AgentExecutionState.values
                .where((state) => state.name == previousName)
                .firstOrNull;
      if (previous == null ||
          transitionAgentExecution(previous, update.state) == null) {
        throw _executionStateInvalid;
      }
      final timestamp = Timestamp.now(), stateName = update.state.name;
      final status =
          'execution_${stateName.replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match[0]!.toLowerCase()}')}';
      if (cleanupRecovery && update.state == AgentExecutionState.cleaned) {
        // Rebind only delivery authority after the original execution is
        // terminal. Its execution attempt and immutable inputs remain intact.
        transaction.update(activationRef, {
          'workflowRunAttempt': principal.runAttempt,
          'updatedAt': timestamp,
        });
      }
      transaction.set(dispatchRef, {
        'status': status,
        'executionBackend': backendId,
        'executionState': stateName,
        'executionId': identity.executionId,
        'executionAttemptId':
            dispatch?['executionAttemptId'] ??
            activation?['workflowRunAttempt'],
        if (cleanupRecovery && update.state == AgentExecutionState.cleaned)
          'workflowRunAttempt': principal.runAttempt,
        if (identity.reservationId != null)
          'executionReservationId': identity.reservationId,
        'executionInputDigest': inputDigest,
        'executionArtifactDigest': artifactDigest,
        'execution${stateName[0].toUpperCase()}${stateName.substring(1)}At':
            timestamp,
        'updatedAt': timestamp,
      }, options: const SetOptions.merge());
      return {
        'recorded': true,
        'status': status,
        'executionId': identity.executionId,
        'projectId': activation!['projectId'],
        'projectStatusFieldId': activation['projectStatusFieldId'],
        'projectInProgressOptionId': activation['projectInProgressOptionId'],
      };
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 2));
  }
}

const _executionStateInvalid = ApiError(
  409,
  'agent_execution_state_invalid',
  'This execution update does not match the approved workflow and inputs.',
);

/// A newer attempt may only finish cleanup for the original bound execution.
/// It cannot use the older approval to start or resume model work.
bool agentExecutionCleanupRecoveryAllowed({
  required Map<String, Object?> activation,
  required Map<String, Object?> dispatch,
  required GitHubActionsPrincipal principal,
  required AgentExecutionUpdate update,
  required String inputDigest,
  required String artifactDigest,
}) {
  final originalAttempt = activation['workflowRunAttempt'];
  return originalAttempt is int &&
      originalAttempt > 0 &&
      principal.runAttempt > originalAttempt &&
      const {
        AgentExecutionState.cleaning,
        AgentExecutionState.cleaned,
      }.contains(update.state) &&
      activation['workflowRunId'] == principal.runId &&
      activation['workflowSha'] == principal.sha &&
      dispatch['workflowRunId'] == principal.runId &&
      dispatch['workflowSha'] == principal.sha &&
      dispatch['workflowRunAttempt'] == originalAttempt &&
      dispatch['executionId'] == update.identity.executionId &&
      dispatch['executionInputDigest'] == inputDigest &&
      dispatch['executionArtifactDigest'] == artifactDigest &&
      (dispatch['executionReservationId'] == null ||
          dispatch['executionReservationId'] == update.identity.reservationId);
}
