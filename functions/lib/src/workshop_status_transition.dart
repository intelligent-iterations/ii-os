import 'api_error.dart';

/// Human-controlled transitions for the Software Workshop status field.
///
/// Agent-owned states are never selected directly. Deployment and
/// finalization own those transitions so the Project field cannot drift away
/// from the immutable dispatch receipt.
void requireHumanWorkshopStatusTransition({
  required String current,
  required String target,
  required String dispatchStatus,
  bool deployedAgentPullRequest = false,
  bool resultMatchesCurrentTicket = false,
}) {
  if (current == target) return;
  if (const {
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
  }.contains(dispatchStatus)) {
    throw const ApiError(
      409,
      'workshop_status_agent_active',
      'Cancel the deployment or wait for the current pass before changing its outcome.',
    );
  }
  final requestsQaHandoff =
      const {'Todo', 'In Progress', 'Needs Human Input'}.contains(current) &&
      target == 'Ready for QA';
  if (requestsQaHandoff &&
      dispatchStatus == 'worker_finalized' &&
      deployedAgentPullRequest &&
      !resultMatchesCurrentTicket) {
    throw const ApiError(
      409,
      'workshop_agent_result_stale',
      'The ticket brief changed after this agent pass. Review and deploy the next pass instead.',
    );
  }
  final allowed = switch (current) {
    '' || 'Draft' || 'Backlog' => target == 'Todo',
    'QA failed' || 'QA failed refinement' => target == 'Todo',
    'Todo' || 'In Progress' || 'Needs Human Input' =>
      target == 'Ready for QA' &&
          dispatchStatus == 'worker_finalized' &&
          deployedAgentPullRequest &&
          resultMatchesCurrentTicket,
    'Ready for QA' => const {'Done', 'QA failed'}.contains(target),
    _ => false,
  };
  if (!allowed) {
    throw const ApiError(
      409,
      'workshop_status_transition_invalid',
      'Use the ticket\u2019s next action instead of changing its workflow status directly.',
    );
  }
}

bool workshopStatusCanDeploy(String status, {String dispatchStatus = ''}) =>
    const {
      '',
      'Draft',
      'Backlog',
      'Todo',
      'Needs Human Input',
      'QA failed',
      'QA failed refinement',
    }.contains(status) ||
    (status == 'In Progress' &&
        const {
          'approval_required',
          'approval_invalidated',
          'workflow_stalled',
          'fleet_submission_failed',
          'fleet_submission_stalled',
          'fleet_lifecycle_stalled',
          'fleet_finalization_stalled',
        }.contains(dispatchStatus));
