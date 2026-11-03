import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/agent_permission.dart';
import 'package:ii_os/models/workshop_ticket.dart';

void main() {
  test(
    'runtime startup and cleanup stay distinct from observed workload execution',
    () {
      for (final status in [
        'execution_accepted',
        'execution_waiting_for_capacity',
        'execution_starting',
        'execution_running',
        'execution_cleaning',
        'execution_cleaned',
      ]) {
        final ticket = WorkshopTicket.fromProjectItem(
          _projectItem(),
          statusFieldId: 'STATUS',
          agentDispatch: {
            'status': status,
            'executionId': 'github:1:2:work-ticket',
          },
        );
        expect(ticket.executionId, 'github:1:2:work-ticket');
        expect(ticket.agentWorking, status == 'execution_running');
        expect(
          WorkshopFilter.working.includes(ticket),
          status == 'execution_running',
        );
        expect(ticket.agentStarting, status != 'execution_running');
        expect(ticket.agentActivityLabel.contains('Fleet'), isFalse);
      }
    },
  );

  test('stale Project refresh retains a newly created ticket', () {
    final created = workshopProjectItemFromCreatedIssue({
      'projectItemId': 'ITEM_new',
      'id': 'ISSUE_new',
      'number': 77,
      'title': 'Example ticket appears after creation',
      'state': 'OPEN',
      'url': 'https://github.com/org/repo/issues/77',
      'definitionOfDone': 'The ticket appears without refresh.',
      'howToTest': 'Create a ticket.',
      'permissions': {'profile': 'repository-maintainer', 'ref': 'dev'},
      'context': '',
      'structured': true,
    }, repository: 'org/repo');

    final merged = workshopProjectItemsWithCreatedCache(
      [_projectItem()],
      {'ITEM_new': created},
    );

    expect(merged.map((item) => item['id']), ['project-item-42', 'ITEM_new']);
  });

  test('created issue becomes an immediate Workshop project item', () {
    final item = workshopProjectItemFromCreatedIssue(
      {
        'projectItemId': 'ITEM_new',
        'id': 'ISSUE_new',
        'number': 77,
        'title': 'Example ticket appears after creation',
        'state': 'OPEN',
        'url': 'https://github.com/org/repo/issues/77',
        'definitionOfDone': 'The ticket appears without refresh.',
        'howToTest': 'Create a ticket.',
        'permissions': {'profile': 'repository-maintainer', 'ref': 'dev'},
        'context': '',
        'structured': true,
      },
      repository: 'org/repo',
      statusFieldId: 'STATUS',
      statusOptionId: 'TODO',
      statusName: 'Todo',
    );

    final ticket = WorkshopTicket.fromProjectItem(
      item,
      statusFieldId: 'STATUS',
    );
    expect(ticket.itemId, 'ITEM_new');
    expect(ticket.number, 77);
    expect(ticket.repository, 'org/repo');
    expect(ticket.definitionOfDone, 'The ticket appears without refresh.');
    expect(ticket.status, 'Todo');
    expect(WorkshopFilter.active.includes(ticket), isTrue);
  });

  test('working ticket retains its dispatch start time', () {
    final ticket = WorkshopTicket.fromProjectItem(
      _projectItem(),
      statusFieldId: 'status-field',
      agentDispatch: const {
        'status': 'fleet_running',
        'fleetJobId': 'github:123:9001:1:work-ticket',
        'fleetRunningAt': '2026-08-22T10:15:00.000Z',
        'dispatchedAt': '2026-08-22T10:15:00.000Z',
      },
    );

    expect(ticket.agentStartedAt, DateTime.utc(2026, 8, 22, 10, 15));
  });
  group('WorkshopTicket', () {
    test('reads the Project item as the canonical ticket record', () {
      final ticket = WorkshopTicket.fromProjectItem(
        _projectItem(),
        statusFieldId: 'status-field',
        agentDispatch: const {'canDeploy': true},
      );

      expect(ticket.itemId, 'project-item-42');
      expect(ticket.repository, 'acme-co/example-app');
      expect(ticket.number, 42);
      expect(ticket.status, 'Todo');
      expect(ticket.definitionOfDone, contains('Workshop renders'));
      expect(ticket.howToTest, contains('flutter test'));
      expect(ticket.permissionProfile, 'repository-maintainer');
      expect(ticket.agentReady, isFalse);
      expect(ticket.toTicketModel().state, 'open');
    });

    test('requires the brief, installed access, Project, and repository', () {
      final ticket = WorkshopTicket.fromProjectItem(
        _projectItem(),
        statusFieldId: 'status-field',
        agentDispatch: const {'canDeploy': true},
      );
      final ready = ticket.readiness(
        profiles: [AgentPermissionModel.fromJson(_permissionProfile())],
        permissionProfilesVerified: true,
        projectSupportsTodo: true,
        automationReady: true,
        automationDetail: 'Repository checks passed.',
      );
      final blocked = ticket.readiness(
        profiles: const [],
        permissionProfilesVerified: true,
        projectSupportsTodo: false,
        automationReady: false,
        automationDetail: 'Repository setup is incomplete.',
      );

      expect(ready.ready, isTrue);
      expect(ready.passedCount, ready.checks.length);
      expect(blocked.ready, isFalse);
      expect(
        blocked.checks
            .where((check) => !check.passed)
            .map((check) => check.label),
        containsAll([
          'Agent access is installed',
          'Project tracking is connected',
          'Repository is live-verified',
        ]),
      );
    });

    test(
      'reports unavailable permission verification without claiming absence',
      () {
        final ticket = WorkshopTicket.fromProjectItem(
          _projectItem(),
          statusFieldId: 'status-field',
        );

        final readiness = ticket.readiness(
          profiles: [AgentPermissionModel.fromJson(_permissionProfile())],
          permissionProfilesVerified: false,
          projectSupportsTodo: true,
          automationReady: true,
          automationDetail: 'Repository checks passed.',
        );
        final access = readiness.checks.singleWhere(
          (check) => check.label == 'Agent access is installed',
        );

        expect(access.passed, isFalse);
        expect(access.detail, contains('could not be verified'));
        expect(access.detail, isNot(contains('not installed')));
      },
    );

    test('workshop filters mirror the human delivery stages', () {
      final todo = WorkshopTicket.fromProjectItem(
        _projectItem(),
        statusFieldId: 'status-field',
      );
      final qa = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Ready for QA'),
        statusFieldId: 'status-field',
      );

      expect(WorkshopFilter.todo.includes(todo), isTrue);
      expect(WorkshopFilter.working.includes(todo), isFalse);
      expect(WorkshopFilter.qa.includes(qa), isTrue);
      expect(WorkshopFilter.active.includes(qa), isTrue);
      expect(WorkshopFilter.fromValue('unknown'), WorkshopFilter.active);
    });

    test('done and closed tickets are terminal with no next action', () {
      final done = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Done'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'needs_human_input',
        },
      );
      final closed = WorkshopTicket.fromProjectItem(
        _projectItem(issueState: 'CLOSED'),
        statusFieldId: 'status-field',
      );

      for (final ticket in [done, closed]) {
        expect(ticket.terminal, isTrue);
        expect(ticket.nextActionLabel, 'No action needed');
        expect(ticket.hasCurrentAgentHandoff, isFalse);
        expect(WorkshopFilter.active.includes(ticket), isFalse);
        expect(WorkshopFilter.done.includes(ticket), isTrue);
      }
    });

    test('agent working and retry failed require dispatch evidence', () {
      final unverified = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'In Progress'),
        statusFieldId: 'status-field',
      );
      final working = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'In Progress'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'fleet_running',
          'fleetJobId': 'github:123:9001:1:work-ticket',
        },
      );
      final retryFailed = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'In Progress'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'retry_failed',
          'detail': 'The worker image is mutable.',
        },
      );

      expect(unverified.agentWorking, isFalse);
      expect(working.agentWorking, isTrue);
      expect(working.displayStatus, 'In Progress');
      expect(working.agentActivityLabel, 'Agent working');
      expect(retryFailed.retryFailed, isTrue);
      expect(retryFailed.displayStatus, 'In Progress');
      expect(retryFailed.agentActivityLabel, 'Agent retry failed');
      expect(WorkshopFilter.attention.includes(retryFailed), isTrue);
    });

    test('reset capability and progress come only from the API verdict', () {
      final resettable = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'In Progress'),
        statusFieldId: 'status-field',
        agentDispatch: const {'canReset': true},
      );
      final resetting = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'In Progress'),
        statusFieldId: 'status-field',
        agentDispatch: const {'canReset': true, 'status': 'resetting'},
      );

      expect(resettable.canReset, isTrue);
      expect(resettable.resetting, isFalse);
      expect(resetting.resetting, isTrue);
      expect(resetting.nextActionLabel, 'Resetting ticket');
    });

    test(
      'workflow and Fleet queue phases never claim the agent is working',
      () {
        for (final dispatch in const [
          {'status': 'workflow_bound', 'workflowRunId': 9001},
          {
            'status': 'fleet_queued',
            'workflowRunId': 9001,
            'fleetJobId': 'github:123:9001:1:work-ticket',
          },
        ]) {
          final ticket = WorkshopTicket.fromProjectItem(
            _projectItem(status: 'In Progress'),
            statusFieldId: 'status-field',
            agentDispatch: dispatch,
          );

          expect(ticket.agentWorking, isFalse, reason: '${dispatch['status']}');
          expect(ticket.agentStarting, isTrue, reason: '${dispatch['status']}');
          expect(
            ticket.agentActivityLabel,
            dispatch['status'] == 'fleet_queued'
                ? 'Waiting for a Fleet worker'
                : 'Workflow starting',
          );
        }
      },
    );

    test('dispatch receipt requires a human trigger or shows final state', () {
      final queued = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Needs Human Input'),
        statusFieldId: 'status-field',
        agentDispatch: const {'status': 'queued'},
      );
      final qa = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Todo'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'ready_for_qa',
          'resultMatchesCurrentTicket': true,
        },
      );
      final needsHuman = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Todo'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'needs_human_input',
          'resultMatchesCurrentTicket': true,
        },
      );
      final pausedNeedsHuman = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Todo'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'paused',
          'finalProjectStatus': 'needs_human_input',
        },
      );
      final qaAfterQuestion = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Ready for QA'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'needs_human_input',
        },
      );
      final invalidated = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Todo'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'approval_invalidated',
          'canDeploy': true,
        },
      );

      expect(queued.agentReady, isFalse);
      expect(queued.displayStatus, 'Needs Human Input');
      expect(queued.agentActivityLabel, isEmpty);
      expect(queued.nextActionLabel, 'Answer the agent');
      expect(qa.awaitingQa, isFalse);
      expect(qa.displayStatus, 'Todo');
      expect(qa.agentActivityLabel, 'Agent suggests Ready for QA');
      expect(WorkshopFilter.qa.includes(qa), isFalse);
      expect(needsHuman.needsHumanInput, isFalse);
      expect(needsHuman.agentRequestsHumanInput, isTrue);
      expect(needsHuman.requiresAgentResponse, isTrue);
      expect(needsHuman.displayStatus, 'Todo');
      expect(needsHuman.agentActivityLabel, 'Agent requests human input');
      expect(WorkshopFilter.attention.includes(needsHuman), isTrue);
      expect(pausedNeedsHuman.requiresAgentResponse, isFalse);
      expect(pausedNeedsHuman.agentActivityLabel, isEmpty);
      expect(qaAfterQuestion.awaitingQa, isTrue);
      expect(qaAfterQuestion.hasCurrentAgentHandoff, isFalse);
      expect(qaAfterQuestion.requiresAgentResponse, isFalse);
      expect(qaAfterQuestion.agentActivityLabel, isEmpty);
      expect(qaAfterQuestion.nextActionLabel, 'Verify the fix');
      expect(WorkshopFilter.attention.includes(qaAfterQuestion), isFalse);
      expect(invalidated.agentReady, isFalse);
      expect(invalidated.agentActivityLabel, 'Agent approval needs review');
      expect(invalidated.nextActionLabel, 'Deploy');
      expect(WorkshopFilter.attention.includes(invalidated), isTrue);
    });

    test('surfaces the exact pull request recorded by finalization', () {
      final ticket = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Ready for QA'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'ready_for_qa',
          'finalPullRequestUrl':
              'https://github.com/acme-co/example-app/pull/1036',
        },
      );

      expect(ticket.hasPullRequest, isTrue);
      expect(ticket.finalPullRequestUrl, endsWith('/pull/1036'));
    });

    test('a finalized result is current only for its approved brief', () {
      final current = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Todo'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'ready_for_qa',
          'resultMatchesCurrentTicket': true,
          'canDeploy': true,
        },
      );
      final stale = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Todo'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'ready_for_qa',
          'resultMatchesCurrentTicket': false,
          'canDeploy': true,
        },
      );

      expect(current.hasCurrentAgentHandoff, isTrue);
      expect(current.canHandoffMergedPullRequest, isTrue);
      expect(stale.hasCurrentAgentHandoff, isFalse);
      expect(stale.canHandoffMergedPullRequest, isFalse);
      expect(stale.nextActionLabel, 'Deploy');
    });

    test('a finalized current result can hand off from stale In Progress', () {
      final ticket = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'In Progress'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'worker_finalized',
          'finalProjectStatus': 'needs_human_input',
          'resultMatchesCurrentTicket': true,
          'canDeploy': false,
        },
      );

      expect(ticket.canHandoffMergedPullRequest, isTrue);
    });

    test('recoverable states always expose a human deploy path', () {
      for (final status in const [
        '',
        'Draft',
        'Backlog',
        'Todo',
        'Needs Human Input',
        'QA failed',
        'QA failed refinement',
      ]) {
        final ticket = WorkshopTicket.fromProjectItem(
          _projectItem(status: status),
          statusFieldId: 'status-field',
          agentDispatch: const {'canDeploy': true},
        );
        expect(ticket.canDeploy, isTrue, reason: status);
        expect(ticket.nextActionLabel, isNot('Review workflow state'));
      }
    });

    test('deployability comes from the same server decision as activation', () {
      final serverBlocked = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'Todo'),
        statusFieldId: 'status-field',
        agentDispatch: const {'canDeploy': false},
      );
      final serverReady = WorkshopTicket.fromProjectItem(
        _projectItem(status: 'In Progress'),
        statusFieldId: 'status-field',
        agentDispatch: const {
          'status': 'approval_invalidated',
          'canDeploy': true,
        },
      );

      expect(serverBlocked.canDeploy, isFalse);
      expect(serverBlocked.nextActionLabel, 'Review workflow state');
      expect(serverReady.canDeploy, isTrue);
      expect(serverReady.nextActionLabel, 'Deploy');
    });

    test('reconciled dispatch overrides a stale In Progress status', () {
      for (final dispatchStatus in const [
        'approval_required',
        'approval_invalidated',
        'workflow_stalled',
        'fleet_submission_failed',
        'fleet_submission_stalled',
        'fleet_lifecycle_stalled',
        'fleet_finalization_stalled',
      ]) {
        final ticket = WorkshopTicket.fromProjectItem(
          _projectItem(status: 'In Progress'),
          statusFieldId: 'status-field',
          agentDispatch: {'status': dispatchStatus, 'canDeploy': true},
        );

        expect(ticket.agentWorking, isFalse, reason: dispatchStatus);
        expect(ticket.canDeploy, isTrue, reason: dispatchStatus);
        expect(ticket.nextActionLabel, 'Deploy');
        expect(WorkshopFilter.attention.includes(ticket), isTrue);
      }
    });

    test('stalled Fleet phases never render as active work', () {
      const labels = {
        'fleet_submission_stalled': 'Fleet submission stopped',
        'fleet_lifecycle_stalled': 'Fleet job stopped reporting',
        'fleet_finalization_stalled': 'Result finalization stopped',
      };
      for (final entry in labels.entries) {
        final ticket = WorkshopTicket.fromProjectItem(
          _projectItem(status: 'In Progress'),
          statusFieldId: 'status-field',
          agentDispatch: {
            'status': entry.key,
            'fleetJobId': 'github:123:9001:1:work-ticket',
            'canDeploy': true,
          },
        );

        expect(ticket.agentWorking, isFalse, reason: entry.key);
        expect(ticket.agentStarting, isFalse, reason: entry.key);
        expect(ticket.agentActivityLabel, entry.value);
        expect(ticket.nextActionLabel, 'Deploy');
      }
    });
  });
}

Map<String, Object?> _projectItem({
  String status = 'Todo',
  String issueState = 'OPEN',
}) => {
  'id': 'project-item-42',
  'content': {
    '__typename': 'Issue',
    'id': 'issue-node-42',
    'number': 42,
    'title': 'Build a clear software workshop',
    'state': issueState,
    'url': 'https://github.com/acme-co/example-app/issues/42',
    'repository': {'nameWithOwner': 'acme-co/example-app'},
    'ticket': {
      'structured': true,
      'definitionOfDone': 'Workshop renders the full handoff.',
      'howToTest': 'Run flutter test and live QA.',
      'permissions': {'profile': 'repository-maintainer', 'ref': 'dev'},
      'context': 'Keep the workflow explicit.',
      'agent': {'ready': false},
    },
  },
  'fieldValues': {
    'nodes': [
      {
        'optionId': 'todo-option',
        'name': status,
        'field': {'id': 'status-field'},
      },
    ],
  },
};

Map<String, Object?> _permissionProfile() => {
  'id': 'repository-maintainer',
  'version': '2026-07-19.1',
  'display_name': 'Repository maintainer',
  'description': 'May edit code and run repository tests.',
  'allowed_actions': ['Edit code', 'Run tests'],
  'denied_actions': ['Mark a ticket Done'],
  'fleet': {
    'runtime_kind': 'docker',
    'capabilities': ['auto-agent'],
  },
  'secret_injection': {'environment': 'ii-os-agent', 'bindings': []},
  'workflow': {'file': 'ii-os-agent-task.yml', 'ref': 'dev'},
};
