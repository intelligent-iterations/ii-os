import '../../provider_contracts/agent_execution.dart';

/// Validates runtime observations against the authenticated workflow invocation.
abstract final class RuntimeAgentExecution {
  static AgentExecutionUpdate? parseCallback({
    required int repositoryId,
    required int runId,
    required String executionId,
    required String reservationId,
    required String state,
    required String inputDigest,
    required String artifactDigest,
  }) {
    final observed = observation(state);
    if (repositoryId <= 0 ||
        runId <= 0 ||
        observed == null ||
        executionId != 'github:$repositoryId:$runId:work-ticket' ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(inputDigest) ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(artifactDigest)) {
      return null;
    }
    final beforeReservation = const {
      AgentExecutionState.accepted,
      AgentExecutionState.waitingForCapacity,
    }.contains(observed);
    if (reservationId.isEmpty
        ? !beforeReservation
        : !RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ).hasMatch(reservationId)) {
      return null;
    }
    return AgentExecutionUpdate(
      identity: AgentExecutionIdentity(
        executionId: executionId,
        reservationId: reservationId.isEmpty ? null : reservationId,
      ),
      state: observed,
    );
  }

  static AgentExecutionState? observation(String state) => switch (state) {
    'accepted' => AgentExecutionState.accepted,
    'waiting-for-capacity' => AgentExecutionState.waitingForCapacity,
    'starting' => AgentExecutionState.starting,
    'running' => AgentExecutionState.running,
    'finished' => AgentExecutionState.finished,
    'failed' => AgentExecutionState.failed,
    'cancelled' => AgentExecutionState.cancelled,
    'unknown' => AgentExecutionState.unknown,
    'cleaning' => AgentExecutionState.cleaning,
    'cleaned' => AgentExecutionState.cleaned,
    _ => null,
  };
}
