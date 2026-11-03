import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/agent_activation_store.dart';
import 'package:ii_os_functions/src/api.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/ticket_content.dart';
import 'package:test/test.dart';

void main() {
  test('receipt reads are bounded to exact visible Project item ids', () {
    final project = _project();
    final items = (project['items'] as Map<String, Object?>)['nodes'] as List;
    items.add(_item('item-new', 'Todo'));
    items.add({'id': ''});
    items.add({'unexpected': 'shape'});

    expect(workshopProjectItemIds(project), const [
      'item-new',
      'item-stale',
      'item-stalled',
      'item-submit-failed',
      'item-active',
      'item-qa',
    ]);
  });

  test('receipt reads fail closed above the GitHub Project page bound', () {
    final project = {
      'items': {
        'nodes': [
          for (var index = 0; index <= workshopProjectItemReadLimit; index++)
            {'id': 'item-$index'},
        ],
      },
    };

    expect(
      () => workshopProjectItemIds(project),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'github_response_invalid',
        ),
      ),
    );
  });

  test('an invalid activation cannot still render as queued', () {
    final state = cohesiveAgentDispatchState(
      const {'status': 'queued'},
      const {
        'status': 'invalidated',
        'permissionProfile': 'repository-maintainer',
        'permissionVersion': '2026-08-21.1',
      },
    );

    expect(state['status'], 'approval_invalidated');
    expect(state['activationStatus'], 'invalidated');
    expect(state['permissionProfile'], 'repository-maintainer');
  });

  test('the board and activation share one deployability decision', () {
    final states = withWorkshopDeployability(_project(), const {
      'item-stale': {'status': 'approval_invalidated'},
      'item-stalled': {'status': 'workflow_stalled'},
      'item-submit-failed': {'status': 'fleet_submission_failed'},
    });

    expect(states['item-new']?['canDeploy'], isTrue);
    expect(states['item-stale']?['canDeploy'], isTrue);
    expect(states['item-stalled']?['canDeploy'], isTrue);
    expect(states['item-submit-failed']?['canDeploy'], isTrue);
    expect(states['item-active']?['canDeploy'], isFalse);
    expect(states['item-qa']?['canDeploy'], isFalse);
  });

  test('a finalized result is bound to the exact current ticket brief', () {
    const originalBody = '''<!-- ii-os-ticket:v1 -->

## Definition of Done
Ship the first reviewed behavior.

## How to Test
Run the first acceptance check.

## Permissions
```json
{"profile":"repository-maintainer","ref":"dev"}
```

## Agent Pickup
```json
{"ready":false}
```''';
    const refinedBody = '''<!-- ii-os-ticket:v1 -->

## Definition of Done
Ship the refined behavior after QA feedback.

## How to Test
Run the narrow-screen acceptance check.

## Permissions
```json
{"profile":"repository-maintainer","ref":"dev"}
```

## Agent Pickup
```json
{"ready":false}
```''';
    final approvedDigest = ticketBodyDigest(TicketContent.parse(originalBody));
    final unchanged = withWorkshopDeployability(_ticketProject(originalBody), {
      'item-ticket': {
        'status': 'worker_finalized',
        'ticketBodyDigest': approvedDigest,
      },
    });
    final refined = withWorkshopDeployability(_ticketProject(refinedBody), {
      'item-ticket': {
        'status': 'worker_finalized',
        'ticketBodyDigest': approvedDigest,
      },
    });

    expect(unchanged['item-ticket']?['resultMatchesCurrentTicket'], isTrue);
    expect(refined['item-ticket']?['resultMatchesCurrentTicket'], isFalse);
    expect(unchanged['item-ticket'], isNot(contains('ticketBodyDigest')));
  });

  test('a Todo ticket cannot advertise Deploy while its claim is live', () {
    final now = DateTime.utc(2026, 8, 23, 21, 30);
    final live = cohesiveAgentDispatchState(
      const {'status': 'queued'},
      {
        'status': 'claiming',
        'claimId': 'claim-1',
        'claimExpiresAt': Timestamp.fromDate(
          now.add(const Duration(minutes: 1)),
        ),
      },
      now: now,
    );
    final expired = cohesiveAgentDispatchState(
      const {'status': 'queued'},
      {
        'status': 'claiming',
        'claimId': 'claim-1',
        'claimExpiresAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 1)),
        ),
      },
      now: now,
    );

    expect(
      withWorkshopDeployability(_todoProject(), {
        'item-todo': live,
      })['item-todo']?['canDeploy'],
      isFalse,
    );
    expect(
      withWorkshopDeployability(_todoProject(), {
        'item-todo': expired,
      })['item-todo']?['canDeploy'],
      isTrue,
      reason:
          'a pre-dispatch crash cannot strand the ticket after claim expiry',
    );
  });

  test('a completed reset hides the superseded run and reopens Deploy', () {
    final state = cohesiveAgentDispatchState(
      const {
        'status': 'worker_finalized',
        'detail': 'Old worker result',
        'finalPullRequestUrl': 'https://github.com/acme/repo/pull/42',
      },
      const {
        'status': 'reset',
        'finalOutcome': 'success',
        'finalProjectStatus': 'needs_human_input',
        'ticketBodyDigest': 'old-digest',
      },
    );

    expect(state['status'], 'reset');
    expect(state['receiptAllowsDeploy'], isTrue);
    expect(state['receiptAllowsReset'], isTrue);
    expect(state, isNot(contains('detail')));
    expect(state, isNot(contains('finalPullRequestUrl')));
    expect(state, isNot(contains('ticketBodyDigest')));
  });

  test('an interrupted reset is retryable but cannot advertise Deploy', () {
    final state = cohesiveAgentDispatchState(
      const {'status': 'worker_finalized'},
      const {'status': 'resetting', 'resetRequestId': 'reset-1'},
    );

    expect(state['status'], 'resetting');
    expect(state['receiptAllowsDeploy'], isFalse);
    expect(state['receiptAllowsReset'], isTrue);
  });

  test('an active dispatch without its activation receipt fails closed', () {
    final state = cohesiveAgentDispatchState(const {
      'status': 'fleet_running',
    }, const {});

    expect(state['receiptAllowsDeploy'], isFalse);
    expect(state['receiptAllowsReset'], isFalse);
  });

  test('reset projection is available only for open inactive tickets', () {
    final states = withWorkshopDeployability(_project(), const {
      'item-stale': {
        'status': 'worker_finalized',
        'receiptAllowsDeploy': true,
        'receiptAllowsReset': true,
      },
      'item-active': {
        'status': 'fleet_running',
        'receiptAllowsDeploy': false,
        'receiptAllowsReset': false,
      },
    });

    expect(states['item-new']?['canReset'], isFalse);
    expect(states['item-stale']?['canReset'], isTrue);
    expect(states['item-active']?['canReset'], isFalse);
    expect(states['item-qa']?['canReset'], isTrue);
  });

  test('a bound workflow without a Fleet job becomes truthfully retryable', () {
    final now = DateTime.utc(2026, 8, 23, 21, 30);
    final state = cohesiveAgentDispatchState(
      const {'status': 'workflow_bound', 'workflowRunId': 9001},
      {
        'status': 'consumed',
        'workflowBoundAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 6)),
        ),
      },
      now: now,
    );

    expect(state['status'], 'workflow_stalled');
    expect(state['workflowRunId'], 9001);
  });

  test('an unbound dispatch cannot strand a ticket forever', () {
    final now = DateTime.utc(2026, 8, 23, 21, 30);
    final state = cohesiveAgentDispatchState(
      {
        'status': 'workflow_dispatching',
        'requestId': 'dispatch-1',
        'repository': 'acme-co/example-app',
        'issueNumber': 42,
        'trustedSourceSha': '1111111111111111111111111111111111111111',
        'trustedSourceRef':
            'ii-os-agent-v4-1111111111111111111111111111111111111111',
        'dispatchedAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 6)),
        ),
      },
      const {'status': 'claiming'},
      now: now,
    );

    expect(state['status'], 'workflow_stalled');
    expect(state['workflowRunId'], isNull);
  });

  test('a real Fleet binding never ages into a workflow-only retry', () {
    final now = DateTime.utc(2026, 8, 23, 21, 30);
    final state = cohesiveAgentDispatchState(
      const {
        'status': 'fleet_queued',
        'workflowRunId': 9001,
        'fleetJobId': 'github:123:9001:1:work-ticket',
      },
      {
        'status': 'consumed',
        'workflowBoundAt': Timestamp.fromDate(
          now.subtract(const Duration(hours: 2)),
        ),
      },
      now: now,
    );

    expect(state['status'], 'fleet_queued');
    expect(state['fleetJobId'], 'github:123:9001:1:work-ticket');
  });

  test('every abandoned Fleet phase becomes truthfully retryable', () {
    final now = DateTime.utc(2026, 8, 23, 21, 30);
    final activation = const {'status': 'consumed'};
    final cases = <String, (DateTime, String)>{
      'fleet_submitting': (
        now.subtract(agentFleetLifecycleRecoveryTimeout),
        'fleet_submission_stalled',
      ),
      'fleet_queued': (
        now.subtract(agentFleetLifecycleRecoveryTimeout),
        'fleet_lifecycle_stalled',
      ),
      'fleet_running': (
        now.subtract(agentFleetLifecycleRecoveryTimeout),
        'fleet_lifecycle_stalled',
      ),
      'fleet_cleaning': (
        now.subtract(agentFleetLifecycleRecoveryTimeout),
        'fleet_lifecycle_stalled',
      ),
      'fleet_cleaned': (
        now.subtract(agentFleetFinalizationRecoveryTimeout),
        'fleet_finalization_stalled',
      ),
    };

    for (final entry in cases.entries) {
      final state = cohesiveAgentDispatchState(
        {
          'status': entry.key,
          'workflowRunId': 9001,
          'workflowRunAttempt': 1,
          'workflowSha': '1111111111111111111111111111111111111111',
          'fleetJobId': 'github:123:9001:1:work-ticket',
          'stateUpdatedAt': entry.value.$1.toIso8601String(),
        },
        activation,
        now: now,
      );

      expect(
        state['status'],
        entry.value.$2,
        reason: '${entry.key} cannot hold a ticket forever after its deadline',
      );
    }
  });

  test('fresh Fleet lifecycle proof remains active', () {
    final now = DateTime.utc(2026, 8, 23, 21, 30);
    for (final status in const [
      'fleet_submitting',
      'fleet_queued',
      'fleet_running',
      'fleet_cleaning',
      'fleet_cleaned',
    ]) {
      final state = cohesiveAgentDispatchState(
        {
          'status': status,
          'workflowRunId': 9001,
          'fleetJobId': 'github:123:9001:1:work-ticket',
          'stateUpdatedAt': now
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
        const {'status': 'consumed'},
        now: now,
      );
      expect(state['status'], status);
    }
  });
}

Map<String, Object?> _project() => {
  'fields': {
    'nodes': [
      {
        '__typename': 'ProjectV2SingleSelectField',
        'id': 'status-field',
        'name': 'Status',
        'options': [
          {'id': 'todo', 'name': 'Todo'},
          {'id': 'progress', 'name': 'In Progress'},
        ],
      },
    ],
  },
  'items': {
    'nodes': [
      _item('item-new', ''),
      _item('item-stale', 'In Progress'),
      _item('item-stalled', 'In Progress'),
      _item('item-submit-failed', 'In Progress'),
      _item('item-active', 'In Progress'),
      _item('item-qa', 'Ready for QA'),
    ],
  },
};

Map<String, Object?> _todoProject() => {
  'fields': _project()['fields'],
  'items': {
    'nodes': [_item('item-todo', 'Todo')],
  },
};

Map<String, Object?> _ticketProject(String body) => {
  'fields': _project()['fields'],
  'items': {
    'nodes': [
      {
        ..._item('item-ticket', 'Todo'),
        'content': {'__typename': 'Issue', 'body': body},
      },
    ],
  },
};

Map<String, Object?> _item(String id, String status) => {
  'id': id,
  'isArchived': false,
  'content': {'__typename': 'Issue', 'state': 'OPEN', 'body': ''},
  'fieldValues': {
    'nodes': [
      {
        'name': status,
        'field': {'id': 'status-field'},
      },
    ],
  },
};
