part of 'agent_activation_store.dart';

const _terminalResettableDispatchStatuses = {
  'approval_required',
  'approval_invalidated',
  'dispatch_failed',
  'retry_failed',
  'workflow_stalled',
  'fleet_submission_failed',
  'fleet_submission_stalled',
  'fleet_lifecycle_stalled',
  'fleet_finalization_stalled',
  'worker_finalized',
  'paused',
  'reset',
};

const _liveResetBlockedDispatchStatuses = {
  ...agentExecutionLiveStatuses,
  'queued',
  'dispatching',
  'dispatched',
  'dispatched_unconfirmed',
  'workflow_dispatching',
  'workflow_bound',
  'workflow_unconfirmed',
  'fleet_submitting',
  'fleet_queued',
  'fleet_running',
  'fleet_cleaning',
  'fleet_cleaned',
};

bool agentTicketResetAllowed(
  Map<String, Object?>? activation,
  Map<String, Object?>? dispatch,
  DateTime now,
) {
  try {
    requireAgentTicketResetAllowed(activation, dispatch, now);
    return true;
  } on ApiError {
    return false;
  }
}

void requireAgentTicketResetAllowed(
  Map<String, Object?>? activation,
  Map<String, Object?>? dispatch,
  DateTime now,
) {
  if (activation?['status'] == 'resetting' ||
      dispatch?['status'] == 'resetting') {
    return;
  }
  if (_legacyRecoveryWithRuntimeIdentity(dispatch)) throw _activeResetError;
  // Share the existing finite legacy recovery decision with the projection.
  // This permits human review; it neither proves cleanup nor replaces the
  // exact workflow-stop proof required by a new activation transaction.
  final recoveryStatus = agentDispatchRecoveryStatus(
    dispatch ?? const {},
    activation ?? const {},
    now,
  );
  if (_terminalResettableDispatchStatuses.contains(dispatch?['status']) ||
      _terminalResettableDispatchStatuses.contains(recoveryStatus)) {
    return;
  }
  final activationStatus = activation?['status'];
  final dispatchStatus = dispatch?['status'];
  if ((activation == null || activation.isEmpty) &&
      (dispatch == null || dispatch.isEmpty)) {
    return;
  }
  if (const {
        'finalized',
        'invalidated',
        'revoked',
      }.contains(activationStatus) &&
      (dispatch == null || dispatch.isEmpty)) {
    return;
  }
  final claimExpiresAt = activation?['claimExpiresAt'];
  final liveClaim =
      activation?['status'] == 'claiming' &&
      claimExpiresAt is Timestamp &&
      claimExpiresAt.toDate().toUtc().isAfter(now.toUtc());
  final boundExecution = _liveResetBlockedDispatchStatuses.contains(
    dispatch?['status'],
  );
  final abandonedPreDispatchClaim =
      activationStatus == 'claiming' &&
      claimExpiresAt is Timestamp &&
      !liveClaim &&
      dispatchStatus == 'queued';
  if (abandonedPreDispatchClaim) return;
  if (liveClaim || activationStatus == 'finalizing' || boundExecution) {
    throw _activeResetError;
  }
  // Unknown or internally inconsistent receipt shapes may represent a newer
  // execution phase. Preserve the workload and require an explicit adapter
  // change instead of treating the state as abandoned.
  throw _activeResetError;
}

const _activeResetError = ApiError(
  409,
  'agent_ticket_reset_active',
  'Wait for the active deployment to finish before resetting this ticket.',
);
