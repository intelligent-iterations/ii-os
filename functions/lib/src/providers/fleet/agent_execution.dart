import '../../provider_contracts/agent_execution.dart';

/// The deployed Fleet callback and stored-field vocabulary stays at this edge.
/// Another backend must validate its own identities; it must not fabricate a
/// Fleet job/lease or reinterpret a historical record as a new execution.
abstract final class FleetAgentExecution {
  static AgentExecutionUpdate? parseCallback({
    required int repositoryId,
    required int runId,
    required int runAttempt,
    required String jobId,
    required String leaseId,
    required String state,
  }) {
    final observed = _observation(state);
    final expected = 'github:$repositoryId:$runId:$runAttempt:work-ticket';
    if (observed == null ||
        jobId != expected ||
        !RegExp(r'^[A-Za-z0-9:_-]{1,200}$').hasMatch(jobId)) {
      return null;
    }
    final beforeReservation = const {
      AgentExecutionState.submitting,
      AgentExecutionState.submissionFailed,
    }.contains(observed);
    if (beforeReservation
        ? leaseId.isNotEmpty
        : !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(leaseId)) {
      return null;
    }
    return AgentExecutionUpdate(
      identity: AgentExecutionIdentity(
        executionId: jobId,
        reservationId: beforeReservation ? null : leaseId,
      ),
      state: observed,
    );
  }

  /// Compatibility projection for existing persisted dispatch records.
  static String? transition(String current, String event) {
    final previous = switch (current) {
      'workflow_bound' ||
      'dispatched' ||
      'workflow_unconfirmed' => AgentExecutionState.ready,
      'fleet_submitting' => AgentExecutionState.submitting,
      'fleet_submission_failed' => AgentExecutionState.submissionFailed,
      'fleet_queued' => AgentExecutionState.queued,
      'fleet_running' => AgentExecutionState.running,
      'fleet_cleaning' => AgentExecutionState.cleaning,
      'fleet_cleaned' => AgentExecutionState.cleaned,
      _ => null,
    };
    final observed = _observation(event);
    if (previous == null || observed == null) return null;
    if (transitionAgentExecution(previous, observed) == null) return null;
    return 'fleet_$event';
  }

  static AgentExecutionState? _observation(String state) => switch (state) {
    'submitting' => AgentExecutionState.submitting,
    'submission_failed' => AgentExecutionState.submissionFailed,
    'queued' => AgentExecutionState.queued,
    'running' => AgentExecutionState.running,
    'cleaning' => AgentExecutionState.cleaning,
    'cleaned' => AgentExecutionState.cleaned,
    _ => null,
  };
}
