import 'package:ii_os_functions/src/agent_activation_store.dart';
import 'package:ii_os_functions/src/github_actions_oidc.dart';
import 'package:ii_os_functions/src/provider_contracts/agent_execution.dart';
import 'package:test/test.dart';

void main() {
  final principal = GitHubActionsPrincipal(
    repository: 'fixture/project',
    repositoryId: 42,
    runId: 100,
    runAttempt: 2,
    sha: 'a' * 40,
    ref: 'refs/tags/fixture',
    workflowRef: '',
    jobWorkflowRef: '',
    actor: 'fixture',
    subject: '',
    environment: 'fixture',
  );
  final activation = <String, Object?>{
    'workflowRunId': 100,
    'workflowRunAttempt': 1,
    'workflowSha': 'a' * 40,
  };
  final dispatch = <String, Object?>{
    ...activation,
    'executionId': 'github:42:100:work-ticket',
    'executionInputDigest': 'sha256:${'b' * 64}',
    'executionArtifactDigest': 'sha256:${'c' * 64}',
    'executionReservationId': '12345678-abcd-4000-8000-123456789abc',
  };
  final identity = AgentExecutionIdentity(
    executionId: dispatch['executionId']! as String,
    reservationId: dispatch['executionReservationId']! as String,
  );
  bool allowed(AgentExecutionState state, {Map<String, Object?>? receipt}) =>
      agentExecutionCleanupRecoveryAllowed(
        activation: activation,
        dispatch: receipt ?? dispatch,
        principal: principal,
        update: AgentExecutionUpdate(identity: identity, state: state),
        inputDigest: dispatch['executionInputDigest']! as String,
        artifactDigest: dispatch['executionArtifactDigest']! as String,
      );

  test(
    'a workflow retry can only reconcile cleanup of the original execution',
    () {
      for (final state in AgentExecutionState.values) {
        expect(
          allowed(state),
          const {
            AgentExecutionState.cleaning,
            AgentExecutionState.cleaned,
          }.contains(state),
          reason: state.name,
        );
      }
    },
  );

  test(
    'cleanup recovery cannot replace input, reservation, workflow identity or original attempt',
    () {
      for (final change in <Map<String, Object?>>[
        {'executionId': 'github:42:101:work-ticket'},
        {'executionInputDigest': 'sha256:${'d' * 64}'},
        {'executionArtifactDigest': 'sha256:${'d' * 64}'},
        {'executionReservationId': '22345678-abcd-4000-8000-123456789abc'},
        {'workflowRunId': 101},
        {'workflowRunAttempt': 2},
        {'workflowSha': 'd' * 40},
      ]) {
        expect(
          allowed(
            AgentExecutionState.cleaned,
            receipt: {...dispatch, ...change},
          ),
          isFalse,
        );
      }
    },
  );
}
