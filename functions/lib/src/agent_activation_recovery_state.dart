part of 'agent_activation_store.dart';

bool agentPickupInFlight(
  Map<String, Object?>? activation,
  Map<String, Object?>? dispatch,
  DateTime now,
) {
  if (activation?['status'] == 'resetting' ||
      dispatch?['status'] == 'resetting') {
    return true;
  }
  if (_legacyRecoveryWithRuntimeIdentity(dispatch)) return true;
  // Failure reconciliation is authoritative. Older records may still retain
  // a live-looking activation claim if reconciliation completed before claim
  // cleanup became atomic. Let a human pause and re-review those terminal
  // failures, while preserving the lock for every active dispatch state.
  if (const {
    'approval_required',
    'retry_failed',
    'workflow_stalled',
    'fleet_submission_failed',
    'fleet_submission_stalled',
    'fleet_lifecycle_stalled',
    'fleet_finalization_stalled',
  }.contains(dispatch?['status'])) {
    return false;
  }
  if (agentDispatchRecoveryStatus(
        dispatch ?? const {},
        activation ?? const {},
        now,
      ) !=
      null) {
    return false;
  }
  if (_claimInFlight(activation, now) ||
      activation?['status'] == 'finalizing') {
    return true;
  }
  if (activation?['status'] != 'consumed') return false;
  if (_runtimeExecutionRecorded(dispatch) &&
      dispatch?['status'] != 'worker_finalized') {
    return true;
  }
  return const {
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
    ...agentExecutionLiveStatuses,
  }.contains(dispatch?['status']);
}

const agentWorkflowBindingTimeout = Duration(minutes: 5);
const agentFleetLifecycleRecoveryTimeout = Duration(hours: 3);
const agentFleetFinalizationRecoveryTimeout = Duration(minutes: 30);

/// Projects a crashed workflow into a bounded, human-recoverable state.
///
/// The three-hour lifecycle deadline exceeds the permission-profile maximum
/// runtime (two hours), its ten-minute Fleet observation allowance, and the
/// configured coordinator job timeout, which a deployment must keep below that
/// deadline. A replacement cannot therefore overlap an authorized runtime.
/// Once Fleet has proved `cleaned`, only the broker
/// finalizer remains and its retry loop is bounded well below thirty minutes.
String? agentDispatchRecoveryStatus(
  Map<String, Object?> dispatch,
  Map<String, Object?> activation,
  DateTime now,
) {
  // A legacy time bound cannot establish cleanup for an agent-runtime run.
  if (_runtimeExecutionRecorded(dispatch)) return null;
  if (agentDispatchWorkflowStalled(dispatch, activation, now)) {
    return 'workflow_stalled';
  }
  if (activation['status'] != 'consumed') return null;
  final status = dispatch['status'];
  final changedAt = _agentDispatchTimestamp(switch (status) {
    'fleet_submitting' =>
      dispatch['fleetSubmissionAuthorizedAt'] ??
          dispatch['stateUpdatedAt'] ??
          dispatch['updatedAt'],
    'fleet_queued' =>
      dispatch['fleetQueuedAt'] ??
          dispatch['stateUpdatedAt'] ??
          dispatch['updatedAt'],
    'fleet_running' =>
      dispatch['fleetRunningAt'] ??
          dispatch['stateUpdatedAt'] ??
          dispatch['updatedAt'],
    'fleet_cleaning' =>
      dispatch['fleetCleaningAt'] ??
          dispatch['stateUpdatedAt'] ??
          dispatch['updatedAt'],
    'fleet_cleaned' =>
      dispatch['fleetCleanedAt'] ??
          dispatch['stateUpdatedAt'] ??
          dispatch['updatedAt'],
    _ => null,
  });
  if (changedAt == null) return null;
  final timeout = status == 'fleet_cleaned'
      ? agentFleetFinalizationRecoveryTimeout
      : agentFleetLifecycleRecoveryTimeout;
  if (changedAt.add(timeout).isAfter(now.toUtc())) return null;
  return switch (status) {
    'fleet_submitting' => 'fleet_submission_stalled',
    'fleet_queued' ||
    'fleet_running' ||
    'fleet_cleaning' => 'fleet_lifecycle_stalled',
    'fleet_cleaned' => 'fleet_finalization_stalled',
    _ => null,
  };
}

bool _runtimeExecutionRecorded(Map<String, Object?>? dispatch) =>
    dispatch?['executionId'] is String &&
    (dispatch!['executionId']! as String).isNotEmpty;

bool _legacyRecoveryWithRuntimeIdentity(Map<String, Object?>? dispatch) {
  final status = dispatch?['status'];
  return _runtimeExecutionRecorded(dispatch) &&
      status is String &&
      (status.startsWith('fleet_') || status == 'workflow_stalled');
}

DateTime? _agentDispatchTimestamp(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}

/// A workflow-only receipt may be retried once it has had ample time to bind
/// a Fleet JobRequest. A recorded Fleet job always wins, so a slow workload
/// can never be mistaken for an abandoned GitHub dispatch.
bool agentDispatchWorkflowStalled(
  Map<String, Object?> dispatch,
  Map<String, Object?> activation,
  DateTime now,
) {
  final workflowRunId = dispatch['workflowRunId'];
  final workflowBound = workflowRunId != null;
  if (workflowBound && (workflowRunId is! int || workflowRunId <= 0)) {
    return false;
  }
  if (dispatch['executionId'] is String &&
      (dispatch['executionId'] as String).isNotEmpty) {
    return false;
  }
  if (dispatch['fleetJobId'] is String &&
      (dispatch['fleetJobId'] as String).isNotEmpty) {
    return false;
  }
  if (!const {
    'dispatching',
    'dispatched',
    'dispatched_unconfirmed',
    'workflow_dispatching',
    'workflow_bound',
    'workflow_unconfirmed',
  }.contains(dispatch['status'])) {
    return false;
  }
  if (!workflowBound &&
      (dispatch['requestId'] is! String ||
          (dispatch['requestId'] as String).isEmpty ||
          dispatch['repository'] is! String ||
          dispatch['issueNumber'] is! int ||
          dispatch['trustedSourceSha'] is! String ||
          !RegExp(
            r'^[0-9a-f]{40}$',
          ).hasMatch(dispatch['trustedSourceSha'] as String) ||
          dispatch['trustedSourceRef'] !=
              'ii-os-agent-v4-${dispatch['trustedSourceSha']}')) {
    return false;
  }
  if (!const {'claiming', 'consumed'}.contains(activation['status'])) {
    return false;
  }
  final boundAt = workflowBound
      ? activation['workflowBoundAt'] ??
            dispatch['workflowBoundAt'] ??
            dispatch['dispatchedAt']
      : dispatch['dispatchedAt'];
  return boundAt is Timestamp &&
      !boundAt
          .toDate()
          .toUtc()
          .add(agentWorkflowBindingTimeout)
          .isAfter(now.toUtc());
}
