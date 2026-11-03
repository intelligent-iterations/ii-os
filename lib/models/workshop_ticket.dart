import 'agent_permission.dart';
import 'models.dart';
import 'ticket.dart';

export 'workshop_project_item.dart';

enum WorkshopFilter {
  active('active', 'Pending'),
  todo('todo', 'Todo'),
  working('working', 'Agent working'),
  attention('attention', 'Needs attention'),
  qa('qa', 'Ready for QA'),
  done('done', 'Done'),
  all('all', 'All workshop tickets');

  const WorkshopFilter(this.value, this.label);

  final String value;
  final String label;

  static WorkshopFilter fromValue(String? value) => values.firstWhere(
    (filter) => filter.value == value,
    orElse: () => active,
  );

  bool includes(WorkshopTicket ticket) => switch (this) {
    active => !ticket.terminal,
    todo => ticket.status == 'Todo',
    working => ticket.agentWorking,
    attention =>
      ticket.needsHumanInput ||
          ticket.status == 'QA failed' ||
          ticket.status == 'QA failed refinement' ||
          ticket.retryFailed ||
          ticket.agentRunStatus == 'fleet_submission_failed' ||
          ticket.agentRecoveryNeeded ||
          ticket.agentRunStatus == 'approval_invalidated' ||
          ticket.hasCurrentAgentHandoff ||
          ticket.agentRunStatus == 'approval_required' ||
          !ticket.structured ||
          ticket.permissionProfile == 'none',
    qa => ticket.awaitingQa,
    done => ticket.terminal,
    all => true,
  };
}

final class WorkshopTicket {
  const WorkshopTicket({
    required this.itemId,
    required this.issueId,
    required this.number,
    required this.title,
    required this.repository,
    required this.issueState,
    required this.url,
    required this.status,
    required this.statusOptionId,
    required this.definitionOfDone,
    required this.howToTest,
    required this.permissionProfile,
    required this.permissionRef,
    required this.context,
    required this.structured,
    required this.agentReady,
    required this.canDeploy,
    this.canReset = false,
    this.resultMatchesCurrentTicket = false,
    this.agentRunStatus = '',
    this.agentRunDetail = '',
    this.agentRunUrl = '',
    this.fleetJobId = '',
    this.executionId = '',
    this.agentFinalStatus = '',
    this.finalPullRequestUrl = '',
    this.agentStartedAt,
  });

  factory WorkshopTicket.fromProjectItem(
    JsonMap item, {
    required String statusFieldId,
    JsonMap agentDispatch = const {},
  }) {
    final issue = asJsonMap(item['content']);
    final ticket = asJsonMap(issue['ticket']);
    final permissions = asJsonMap(ticket['permissions']);
    final repository = asJsonMap(issue['repository']);
    JsonMap status = const {};
    for (final value in workshopNodes(
      asJsonMap(item['fieldValues'])['nodes'],
    )) {
      if (asJsonMap(value['field'])['id'] == statusFieldId) {
        status = value;
        break;
      }
    }
    final agentRunStatus = agentDispatch['status'] as String? ?? '';
    return WorkshopTicket(
      itemId: item['id'] as String? ?? '',
      issueId: issue['id'] as String? ?? '',
      number: (issue['number'] as num?)?.toInt() ?? 0,
      title: issue['title'] as String? ?? '',
      repository: repository['nameWithOwner'] as String? ?? '',
      issueState: issue['state'] as String? ?? '',
      url: issue['url'] as String? ?? '',
      status: status['name'] as String? ?? '',
      statusOptionId: status['optionId'] as String?,
      definitionOfDone: ticket['definitionOfDone'] as String? ?? '',
      howToTest: ticket['howToTest'] as String? ?? '',
      permissionProfile: permissions['profile'] as String? ?? 'none',
      permissionRef: permissions['ref'] as String? ?? 'dev',
      context: ticket['context'] as String? ?? '',
      structured: ticket['structured'] == true,
      // A pre-dispatch or failed receipt has no background consumer. Only a
      // new human Deploy request may advance it.
      agentReady: false,
      canDeploy: agentDispatch['canDeploy'] == true,
      canReset: agentDispatch['canReset'] == true,
      resultMatchesCurrentTicket:
          agentDispatch['resultMatchesCurrentTicket'] == true,
      agentRunStatus: agentRunStatus,
      agentRunDetail: agentDispatch['detail'] as String? ?? '',
      agentRunUrl: agentDispatch['workflowRunUrl'] as String? ?? '',
      fleetJobId: agentDispatch['fleetJobId'] as String? ?? '',
      executionId: agentDispatch['executionId'] as String? ?? '',
      agentFinalStatus: agentDispatch['finalProjectStatus'] as String? ?? '',
      finalPullRequestUrl:
          agentDispatch['finalPullRequestUrl'] as String? ?? '',
      agentStartedAt: DateTime.tryParse(
        agentDispatch['executionRunningAt'] as String? ??
            agentDispatch['fleetRunningAt'] as String? ??
            agentDispatch['dispatchedAt'] as String? ??
            '',
      )?.toUtc(),
    );
  }

  final String itemId;
  final String issueId;
  final int number;
  final String title;
  final String repository;
  final String issueState;
  final String url;
  final String status;
  final String? statusOptionId;
  final String definitionOfDone;
  final String howToTest;
  final String permissionProfile;
  final String permissionRef;
  final String context;
  final bool structured;
  final bool agentReady;

  /// The API's live Project/dispatch verdict used by the click endpoint too.
  final bool canDeploy;
  final bool canReset;
  final bool resultMatchesCurrentTicket;
  final String agentRunStatus;
  final String agentRunDetail;
  final String agentRunUrl;
  final String fleetJobId;
  final String executionId;
  final String agentFinalStatus;
  final String finalPullRequestUrl;
  final DateTime? agentStartedAt;

  bool get issueOpen => issueState == 'OPEN';
  bool get terminal => !issueOpen || status == 'Done';
  bool get agentWorking =>
      const {'fleet_running', 'execution_running'}.contains(agentRunStatus);
  bool get agentStarting => const {
    'dispatching',
    'dispatched',
    'dispatched_unconfirmed',
    'workflow_dispatching',
    'workflow_bound',
    'workflow_unconfirmed',
    'fleet_submitting',
    'fleet_queued',
    'fleet_cleaning',
    'fleet_cleaned',
    'execution_accepted',
    'execution_waiting_for_capacity',
    'execution_starting',
    'execution_finished',
    'execution_failed',
    'execution_cancelled',
    'execution_unknown',
    'execution_cleaning',
    'execution_cleaned',
  }.contains(agentRunStatus);
  bool get agentApprovalNeedsReview => const {
    'approval_required',
    'approval_invalidated',
  }.contains(agentRunStatus);
  bool get retryFailed => agentRunStatus == 'retry_failed';
  bool get agentRecoveryNeeded => const {
    'workflow_stalled',
    'fleet_submission_stalled',
    'fleet_lifecycle_stalled',
    'fleet_finalization_stalled',
  }.contains(agentRunStatus);
  bool get agentFinalized => agentRunStatus == 'worker_finalized';
  bool get resetting => agentRunStatus == 'resetting';
  bool get qaFailed =>
      const {'QA failed', 'QA failed refinement'}.contains(status);
  bool get needsAnotherAgentPass => qaFailed || retryFailed;
  bool get awaitingQa => status == 'Ready for QA';
  bool get needsHumanInput => status == 'Needs Human Input';
  bool get hasCurrentAgentHandoff =>
      agentFinalized && resultMatchesCurrentTicket && !terminal && !awaitingQa;
  bool get canHandoffMergedPullRequest =>
      hasCurrentAgentHandoff &&
      const {'Todo', 'In Progress', 'Needs Human Input'}.contains(status);
  bool get agentRequestsHumanInput =>
      hasCurrentAgentHandoff && agentFinalStatus == 'needs_human_input';
  bool get requiresAgentResponse => needsHumanInput || agentRequestsHumanInput;
  bool get hasPullRequest => finalPullRequestUrl.isNotEmpty;
  String get displayStatus {
    if (!issueOpen) return 'Closed';
    if (status.isNotEmpty) return status;
    return 'Draft';
  }

  String get agentActivityLabel {
    if (resetting) return 'Resetting ticket';
    if (agentRunStatus == 'approval_invalidated') {
      return 'Agent approval needs review';
    }
    if (retryFailed) return 'Agent retry failed';
    if (agentWorking) return 'Agent working';
    final executionLabel = _executionActivityLabels[agentRunStatus];
    if (executionLabel != null) return executionLabel;
    if (agentRunStatus == 'fleet_queued' ||
        agentRunStatus == 'fleet_submitting') {
      return 'Waiting for a Fleet worker';
    }
    if (agentRunStatus == 'fleet_cleaning') return 'Fleet is cleaning up';
    if (agentRunStatus == 'fleet_cleaned') return 'Finalizing the result';
    if (agentStarting) return 'Workflow starting';
    if (agentRunStatus == 'workflow_stalled') {
      return 'Workflow stopped before Fleet';
    }
    if (agentRunStatus == 'fleet_submission_failed') {
      return 'Fleet submission failed';
    }
    if (agentRunStatus == 'fleet_submission_stalled') {
      return 'Fleet submission stopped';
    }
    if (agentRunStatus == 'fleet_lifecycle_stalled') {
      return 'Fleet job stopped reporting';
    }
    if (agentRunStatus == 'fleet_finalization_stalled') {
      return 'Result finalization stopped';
    }
    if (agentReady) return 'Waiting for a runner';
    if (agentRunStatus == 'approval_required') return 'Agent review required';
    if (!hasCurrentAgentHandoff) return '';
    return switch (agentFinalStatus) {
      'ready_for_qa' => 'Agent suggests Ready for QA',
      'needs_human_input' => 'Agent requests human input',
      _ => 'Agent run finished',
    };
  }

  String get nextActionLabel {
    if (terminal) return 'No action needed';
    if (resetting) return 'Resetting ticket';
    if (agentWorking) return 'Agent is working';
    if (const {
      'fleet_cleaning',
      'execution_cleaning',
      'execution_failed',
      'execution_cancelled',
    }.contains(agentRunStatus)) {
      return 'Job is cleaning up';
    }
    if (const {
      'fleet_cleaned',
      'execution_cleaned',
      'execution_finished',
    }.contains(agentRunStatus)) {
      return 'Result is finalizing';
    }
    if (agentStarting) return 'Deployment is starting';
    if (agentReady) return 'Wait for a runner';
    if (retryFailed) return 'Review the failed run';
    if (qaFailed) return 'Review and redeploy';
    if (awaitingQa) return 'Verify the fix';
    if (requiresAgentResponse) return 'Answer the agent';
    if (!structured) return 'Finish the brief';
    if (permissionProfile == 'none') return 'Choose agent access';
    if (canDeploy) return 'Deploy';
    return 'Review workflow state';
  }

  AgentPermissionModel? installedProfile(
    Iterable<AgentPermissionModel> profiles,
  ) {
    for (final profile in profiles) {
      if (profile.id == permissionProfile &&
          profile.workflowRef == permissionRef) {
        return profile;
      }
    }
    return null;
  }

  WorkshopTicketReadiness readiness({
    required Iterable<AgentPermissionModel> profiles,
    required bool permissionProfilesVerified,
    required bool projectSupportsTodo,
    required bool automationReady,
    required String automationDetail,
  }) {
    final profile = installedProfile(profiles);
    return WorkshopTicketReadiness([
      WorkshopReadinessCheck(
        label: 'Issue is open',
        detail: issueOpen
            ? 'The agent can update this GitHub issue.'
            : 'Reopen the GitHub issue before deploying it.',
        passed: issueOpen,
      ),
      WorkshopReadinessCheck(
        label: 'Work is testable',
        detail:
            structured && definitionOfDone.isNotEmpty && howToTest.isNotEmpty
            ? 'Definition of Done and verification steps are complete.'
            : 'Add a Definition of Done and a concrete verification plan.',
        passed:
            structured && definitionOfDone.isNotEmpty && howToTest.isNotEmpty,
      ),
      WorkshopReadinessCheck(
        label: 'Agent access is installed',
        detail: !permissionProfilesVerified
            ? 'Agent access could not be verified. Refresh pending tasks before deploying.'
            : profile != null
            ? '${profile.displayName} is installed on $permissionRef.'
            : permissionProfile == 'none'
            ? 'Choose an agent permission profile.'
            : '$permissionProfile is not installed on $permissionRef.',
        passed: permissionProfilesVerified && profile != null,
      ),
      WorkshopReadinessCheck(
        label: 'Project tracking is connected',
        detail: projectSupportsTodo
            ? 'The Project has its human-controlled Status field.'
            : 'Add a Status field with a Todo option for human tracking.',
        passed: projectSupportsTodo,
      ),
      WorkshopReadinessCheck(
        label: 'Ticket can be deployed',
        detail: status == 'Todo'
            ? 'The ticket is ready for a human-started deployment.'
            : canDeploy
            ? 'Deploying will move this ticket to Todo atomically.'
            : 'Finish the current workflow step before deploying another pass.',
        passed: canDeploy,
      ),
      WorkshopReadinessCheck(
        label: 'Repository is live-verified',
        detail: automationDetail,
        passed: automationReady,
      ),
    ]);
  }

  TicketModel toTicketModel() => TicketModel(
    number: number,
    title: title,
    definitionOfDone: definitionOfDone,
    howToTest: howToTest,
    permissionProfile: permissionProfile,
    permissionRef: permissionRef,
    context: context,
    state: issueOpen ? 'open' : 'closed',
    url: url,
    updatedAt: null,
    structured: structured,
    agentReady: agentReady,
  );
}

final class WorkshopTicketReadiness {
  const WorkshopTicketReadiness(this.checks);

  final List<WorkshopReadinessCheck> checks;

  bool get ready => checks.isNotEmpty && checks.every((check) => check.passed);
  int get passedCount => checks.where((check) => check.passed).length;
}

final class WorkshopReadinessCheck {
  const WorkshopReadinessCheck({
    required this.label,
    required this.detail,
    required this.passed,
  });

  final String label;
  final String detail;
  final bool passed;
}

List<JsonMap> workshopNodes(Object? value) =>
    (value as List<Object?>? ?? const []).map(asJsonMap).toList();

const _executionActivityLabels = {
  'execution_accepted': 'Deployment accepted',
  'execution_waiting_for_capacity': 'Waiting for capacity',
  'execution_starting': 'Agent starting',
  'execution_finished': 'Agent finished',
  'execution_failed': 'Agent failed; cleaning up',
  'execution_cancelled': 'Agent cancelled; cleaning up',
  'execution_unknown': 'Checking the execution',
  'execution_cleaning': 'Cleaning up the runtime',
  'execution_cleaned': 'Finalizing the result',
};
