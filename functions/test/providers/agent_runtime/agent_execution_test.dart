import 'package:ii_os_functions/src/provider_contracts/agent_execution.dart';
import 'package:ii_os_functions/src/providers/agent_runtime/agent_execution.dart';

import 'package:test/test.dart';

void main() {
  AgentExecutionUpdate? parse({
    String execution = 'github:42:100:work-ticket',
    String reservation = '12345678-abcd-4000-8000-123456789abc',
    String state = 'running',
    String digest = '',
  }) => RuntimeAgentExecution.parseCallback(
    repositoryId: 42,
    runId: 100,
    executionId: execution,
    reservationId: reservation,
    state: state,
    inputDigest: digest.isEmpty ? 'sha256:${'a' * 64}' : digest,
    artifactDigest: 'sha256:${'b' * 64}',
  );

  test(
    'runtime identity is stable across attempts and requires bound hashes and reservation',
    () {
      expect(parse()!.state, AgentExecutionState.running);
      expect(parse(execution: 'github:42:101:work-ticket'), isNull);
      expect(parse(reservation: ''), isNull);
      expect(parse(digest: 'unbound'), isNull);
      expect(
        parse(state: 'waiting-for-capacity', reservation: '')!.state,
        AgentExecutionState.waitingForCapacity,
      );
    },
  );

  test(
    'acceptance and capacity wait are distinct from starting and workload execution',
    () {
      var state = AgentExecutionState.ready;
      for (final event in [
        AgentExecutionState.accepted,
        AgentExecutionState.waitingForCapacity,
        AgentExecutionState.starting,
        AgentExecutionState.running,
        AgentExecutionState.finished,
        AgentExecutionState.cleaning,
        AgentExecutionState.cleaned,
      ]) {
        state = transitionAgentExecution(state, event)!;
      }
      expect(state, AgentExecutionState.cleaned);
      expect(
        transitionAgentExecution(state, AgentExecutionState.running),
        isNull,
      );
      expect(
        transitionAgentExecution(
          AgentExecutionState.finished,
          AgentExecutionState.running,
        ),
        isNull,
      );
    },
  );

  test(
    'failure, cancellation and unknown observations can still lead to verified cleanup',
    () {
      for (final state in [
        AgentExecutionState.failed,
        AgentExecutionState.cancelled,
        AgentExecutionState.unknown,
      ]) {
        expect(
          transitionAgentExecution(AgentExecutionState.starting, state),
          state,
        );
        expect(
          transitionAgentExecution(state, AgentExecutionState.cleaning),
          AgentExecutionState.cleaning,
        );
        expect(
          transitionAgentExecution(state, AgentExecutionState.cleaned),
          AgentExecutionState.cleaned,
        );
      }
    },
  );
}
