/// Observations accepted by the current agent workflow, independent of its
/// execution backend. These do not authorize a launch or a retry.
enum AgentExecutionState {
  ready,
  accepted,
  waitingForCapacity,
  starting,
  finished,
  failed,
  cancelled,
  unknown,
  submitting,
  submissionFailed,
  queued,
  running,
  cleaning,
  cleaned,
}

/// Identity checked by the provider adapter against the authenticated invocation.
/// A reservation does not exist until submission has progressed far enough.
final class AgentExecutionIdentity {
  const AgentExecutionIdentity({
    required this.executionId,
    required this.reservationId,
  });

  final String executionId;
  final String? reservationId;
}

/// A provider observation, not independent evidence of authority or cleanup.
/// The application still verifies its approved invocation before persisting it.
final class AgentExecutionUpdate {
  const AgentExecutionUpdate({required this.identity, required this.state});

  final AgentExecutionIdentity identity;
  final AgentExecutionState state;
}

/// Advance a single execution without reopening a terminal observation.
/// Missing callbacks may be skipped: providers can report cleanup even when a
/// worker-start event was lost. Cleanup never implies successful agent output.
AgentExecutionState? transitionAgentExecution(
  AgentExecutionState current,
  AgentExecutionState observed,
) {
  if (current == AgentExecutionState.cleaned ||
      current == AgentExecutionState.submissionFailed) {
    return current == observed ? observed : null;
  }
  const active = {
    AgentExecutionState.accepted,
    AgentExecutionState.waitingForCapacity,
    AgentExecutionState.submitting,
    AgentExecutionState.queued,
    AgentExecutionState.starting,
    AgentExecutionState.running,
    AgentExecutionState.unknown,
  };
  final accepted = switch (observed) {
    AgentExecutionState.accepted =>
      current == AgentExecutionState.ready || current == observed,
    AgentExecutionState.waitingForCapacity => const {
      AgentExecutionState.accepted,
      AgentExecutionState.waitingForCapacity,
    }.contains(current),
    AgentExecutionState.starting =>
      active.contains(current) && current != AgentExecutionState.running,
    AgentExecutionState.finished =>
      current == AgentExecutionState.running || current == observed,
    AgentExecutionState.failed || AgentExecutionState.cancelled =>
      active.contains(current) || current == observed,
    AgentExecutionState.unknown => active.contains(current),
    AgentExecutionState.ready => false,
    AgentExecutionState.submitting => const {
      AgentExecutionState.ready,
      AgentExecutionState.submitting,
    }.contains(current),
    AgentExecutionState.submissionFailed => const {
      AgentExecutionState.submitting,
      AgentExecutionState.submissionFailed,
    }.contains(current),
    AgentExecutionState.queued => const {
      AgentExecutionState.submitting,
      AgentExecutionState.queued,
    }.contains(current),
    AgentExecutionState.running => const {
      AgentExecutionState.accepted,
      AgentExecutionState.waitingForCapacity,
      AgentExecutionState.starting,
      AgentExecutionState.unknown,
      AgentExecutionState.submitting,
      AgentExecutionState.queued,
      AgentExecutionState.running,
    }.contains(current),
    AgentExecutionState.cleaning => const {
      AgentExecutionState.accepted,
      AgentExecutionState.waitingForCapacity,
      AgentExecutionState.starting,
      AgentExecutionState.finished,
      AgentExecutionState.failed,
      AgentExecutionState.cancelled,
      AgentExecutionState.unknown,
      AgentExecutionState.submitting,
      AgentExecutionState.queued,
      AgentExecutionState.running,
      AgentExecutionState.cleaning,
    }.contains(current),
    AgentExecutionState.cleaned => const {
      AgentExecutionState.accepted,
      AgentExecutionState.waitingForCapacity,
      AgentExecutionState.starting,
      AgentExecutionState.finished,
      AgentExecutionState.failed,
      AgentExecutionState.cancelled,
      AgentExecutionState.unknown,
      AgentExecutionState.submitting,
      AgentExecutionState.queued,
      AgentExecutionState.running,
      AgentExecutionState.cleaning,
      AgentExecutionState.cleaned,
    }.contains(current),
  };
  return accepted ? observed : null;
}

/// These states retain the application claim until cleanup is confirmed.
const agentExecutionLiveStatuses = {
  'execution_accepted',
  'execution_waiting_for_capacity',
  'execution_starting',
  'execution_running',
  'execution_finished',
  'execution_failed',
  'execution_cancelled',
  'execution_unknown',
  'execution_cleaning',
  'execution_cleaned',
};
