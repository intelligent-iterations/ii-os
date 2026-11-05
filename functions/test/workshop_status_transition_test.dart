import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/workshop_status_transition.dart';
import 'package:test/test.dart';

void main() {
  group('human Workshop status transitions', () {
    test('allows only explicit progress and QA outcome transitions', () {
      for (final transition in const [
        ('', 'Todo'),
        ('Draft', 'Todo'),
        ('Backlog', 'Todo'),
        ('QA failed', 'Todo'),
        ('QA failed refinement', 'Todo'),
        ('Ready for QA', 'Done'),
        ('Ready for QA', 'QA failed'),
      ]) {
        expect(
          () => requireHumanWorkshopStatusTransition(
            current: transition.$1,
            target: transition.$2,
            dispatchStatus: 'worker_finalized',
          ),
          returnsNormally,
          reason: '${transition.$1} -> ${transition.$2}',
        );
      }
    });

    test('rejects direct writes into automation-owned states', () {
      for (final transition in const [
        ('Todo', 'In Progress'),
        ('Todo', 'Ready for QA'),
        ('Needs Human Input', 'Todo'),
        ('Needs Human Input', 'Ready for QA'),
        ('Ready for QA', 'Todo'),
        ('Done', 'Todo'),
      ]) {
        expect(
          () => requireHumanWorkshopStatusTransition(
            current: transition.$1,
            target: transition.$2,
            dispatchStatus: 'worker_finalized',
          ),
          _apiError('workshop_status_transition_invalid'),
          reason: '${transition.$1} -> ${transition.$2}',
        );
      }
    });

    test('a deployed agent pull request unlocks the human QA handoff', () {
      for (final current in const [
        'Todo',
        'In Progress',
        'Needs Human Input',
      ]) {
        expect(
          () => requireHumanWorkshopStatusTransition(
            current: current,
            target: 'Ready for QA',
            dispatchStatus: 'worker_finalized',
            deployedAgentPullRequest: true,
            resultMatchesCurrentTicket: true,
          ),
          returnsNormally,
          reason: current,
        );
      }
    });

    test('a deployed result cannot hand off QA after the brief changes', () {
      expect(
        () => requireHumanWorkshopStatusTransition(
          current: 'Todo',
          target: 'Ready for QA',
          dispatchStatus: 'worker_finalized',
          deployedAgentPullRequest: true,
          resultMatchesCurrentTicket: false,
        ),
        _apiError('workshop_agent_result_stale'),
      );
    });

    test('rejects status changes while a pass is active', () {
      for (final status in const [
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
      ]) {
        expect(
          () => requireHumanWorkshopStatusTransition(
            current: 'Ready for QA',
            target: 'Done',
            dispatchStatus: status,
          ),
          _apiError('workshop_status_agent_active'),
          reason: status,
        );
      }
    });
  });

  test('deploy recovery states stay cohesive with the activation action', () {
    for (final status in const [
      '',
      'Draft',
      'Backlog',
      'Todo',
      'Needs Human Input',
      'QA failed',
      'QA failed refinement',
    ]) {
      expect(workshopStatusCanDeploy(status), isTrue, reason: status);
    }
    for (final status in const ['In Progress', 'Ready for QA', 'Done']) {
      expect(workshopStatusCanDeploy(status), isFalse, reason: status);
    }
    expect(
      workshopStatusCanDeploy(
        'In Progress',
        dispatchStatus: 'workflow_stalled',
      ),
      isTrue,
    );
    expect(
      workshopStatusCanDeploy(
        'In Progress',
        dispatchStatus: 'fleet_submission_failed',
      ),
      isTrue,
    );
    for (final status in const [
      'fleet_submission_stalled',
      'fleet_lifecycle_stalled',
      'fleet_finalization_stalled',
    ]) {
      expect(
        workshopStatusCanDeploy('In Progress', dispatchStatus: status),
        isTrue,
        reason: status,
      );
    }
  });
}

Matcher _apiError(String code) =>
    throwsA(isA<ApiError>().having((error) => error.code, 'code', code));
