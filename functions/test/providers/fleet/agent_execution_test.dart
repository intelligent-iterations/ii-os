import 'package:ii_os_functions/src/provider_contracts/agent_execution.dart';
import 'package:ii_os_functions/src/providers/fleet/agent_execution.dart';
import 'package:test/test.dart';

void main() {
  test('Fleet callbacks preserve exact workflow and reservation identity', () {
    AgentExecutionUpdate? parse({
      String job = 'github:10:20:1:work-ticket',
      String lease = 'lease-1',
      String state = 'running',
    }) => FleetAgentExecution.parseCallback(
      repositoryId: 10,
      runId: 20,
      runAttempt: 1,
      jobId: job,
      leaseId: lease,
      state: state,
    );
    final update = parse()!;
    expect(update.identity.executionId, 'github:10:20:1:work-ticket');
    expect(update.identity.reservationId, 'lease-1');
    expect(update.state, AgentExecutionState.running);
    expect(parse(job: 'github:10:20:2:work-ticket'), isNull);
    expect(parse(job: 'github:10:21:1:work-ticket'), isNull);
    expect(parse(job: 'github:11:20:1:work-ticket'), isNull);
    expect(parse(lease: ''), isNull);
    expect(parse(lease: '../lease'), isNull);
    expect(parse(lease: 'x' * 129), isNull);
    expect(parse(state: 'unexpected'), isNull);
    expect(parse(state: 'submitting'), isNull);
    expect(parse(state: 'submission_failed'), isNull);
    expect(
      parse(state: 'submitting', lease: '')!.identity.reservationId,
      isNull,
    );
    expect(
      parse(state: 'submission_failed', lease: '')!.state,
      AgentExecutionState.submissionFailed,
    );
  });

  test('Fleet translation preserves the entire deployed transition table', () {
    const accepted = <String, Set<String>>{
      'submitting': {
        'workflow_bound',
        'dispatched',
        'workflow_unconfirmed',
        'fleet_submitting',
      },
      'queued': {'fleet_submitting', 'fleet_queued'},
      'submission_failed': {'fleet_submitting', 'fleet_submission_failed'},
      'running': {'fleet_submitting', 'fleet_queued', 'fleet_running'},
      'cleaning': {
        'fleet_submitting',
        'fleet_queued',
        'fleet_running',
        'fleet_cleaning',
      },
      'cleaned': {
        'fleet_submitting',
        'fleet_queued',
        'fleet_running',
        'fleet_cleaning',
        'fleet_cleaned',
      },
    };
    final states = {
      ...accepted.values.expand((value) => value),
      '',
      'dispatching',
      'dispatched_unconfirmed',
      'finalized',
      'unknown',
      'runtime_running',
    };
    for (final current in states) {
      for (final event in [...accepted.keys, '', 'failed', 'unknown']) {
        expect(
          FleetAgentExecution.transition(current, event),
          accepted[event]?.contains(current) == true ? 'fleet_$event' : null,
          reason: '$current -> $event',
        );
      }
    }
  });

  test(
    'neutral transitions never reopen a cleaned execution or a failed submission',
    () {
      for (final next in AgentExecutionState.values) {
        expect(
          transitionAgentExecution(AgentExecutionState.cleaned, next),
          next == AgentExecutionState.cleaned ? next : null,
        );
        expect(
          transitionAgentExecution(AgentExecutionState.submissionFailed, next),
          next == AgentExecutionState.submissionFailed ? next : null,
        );
      }
      expect(
        transitionAgentExecution(
          AgentExecutionState.ready,
          AgentExecutionState.running,
        ),
        isNull,
      );
    },
  );
}
