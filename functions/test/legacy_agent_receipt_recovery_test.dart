import 'package:ii_os_functions/src/agent_activation_store.dart';
import 'package:ii_os_functions/src/api.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/provider_contracts/agent_execution.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30, 22, 42);
  const activation = <String, Object?>{'status': 'consumed'};
  // A legacy shape: consumed activation, a Fleet job queued months before
  // `now`, an update timestamp only, and no agent-runtime execution identity.
  final legacy = <String, Object?>{
    'status': 'fleet_queued',
    'workflowRunId': 9001,
    'fleetJobId': 'github:42:9001:1:work-ticket',
    'stateUpdatedAt': '2026-08-01T00:00:00.000Z',
  };

  test(
    'recorded legacy stalled projection permits the same human review as policy',
    () {
      expect(
        agentDispatchRecoveryStatus(legacy, activation, now),
        'fleet_lifecycle_stalled',
      );
      expect(agentPickupInFlight(activation, legacy, now), false);
      final projected = cohesiveAgentDispatchState(
        legacy,
        activation,
        now: now,
      );
      expect(projected['status'], 'fleet_lifecycle_stalled');
      expect(projected['receiptAllowsDeploy'], true);
      expect(projected['receiptAllowsReset'], true);
      expect(
        () => requireAgentTicketResetAllowed(activation, legacy, now),
        returnsNormally,
      );
      expect(
        withWorkshopDeployability(_project(), {
          'item-legacy': projected,
        })['item-legacy']?['canDeploy'],
        true,
      );
      expect(
        legacy['status'],
        'fleet_queued',
        reason: 'Projection does not rewrite a receipt or claim cleanup.',
      );
    },
  );

  test(
    'legacy queued receipt remains active until its existing three-hour deadline',
    () {
      for (final difference in const [-1, 0, 1]) {
        final dispatch = {
          ...legacy,
          'stateUpdatedAt': now
              .subtract(agentFleetLifecycleRecoveryTimeout)
              .subtract(Duration(milliseconds: difference))
              .toIso8601String(),
        };
        expect(
          agentTicketResetAllowed(activation, dispatch, now),
          difference >= 0,
        );
        expect(agentPickupInFlight(activation, dispatch, now), difference < 0);
      }
      final unknown = {...legacy}..remove('stateUpdatedAt');
      expect(agentTicketResetAllowed(activation, unknown, now), false);
    },
  );

  test(
    'every unresolved runtime execution stays blocked regardless of elapsed time',
    () {
      for (final status in [
        ...agentExecutionLiveStatuses,
        'execution_future_phase',
      ]) {
        final dispatch = {
          ...legacy,
          'status': status,
          'executionId': 'github:42:9001:work-ticket',
        };
        expect(
          agentDispatchRecoveryStatus(dispatch, activation, now),
          isNull,
          reason: status,
        );
        expect(
          agentPickupInFlight(activation, dispatch, now),
          true,
          reason: status,
        );
        expect(
          agentTicketResetAllowed(activation, dispatch, now),
          false,
          reason: status,
        );
      }
    },
  );

  test(
    'runtime identity cannot borrow a legacy Fleet timeout or stalled label',
    () {
      for (final status in const [
        'workflow_stalled',
        'fleet_queued',
        'fleet_running',
        'fleet_cleaning',
        'fleet_cleaned',
        'fleet_lifecycle_stalled',
        'fleet_finalization_stalled',
      ]) {
        final dispatch = {
          ...legacy,
          'status': status,
          'executionId': 'github:42:9001:work-ticket',
        };
        expect(
          agentDispatchRecoveryStatus(dispatch, activation, now),
          isNull,
          reason: status,
        );
        expect(
          agentPickupInFlight(activation, dispatch, now),
          true,
          reason: status,
        );
        expect(
          () => requireAgentTicketResetAllowed(activation, dispatch, now),
          throwsA(
            isA<ApiError>().having(
              (error) => error.code,
              'code',
              'agent_ticket_reset_active',
            ),
          ),
          reason: status,
        );
        final projected = cohesiveAgentDispatchState(
          dispatch,
          activation,
          now: now,
        );
        expect(projected['receiptAllowsDeploy'], false, reason: status);
      }
    },
  );

  test(
    'explicit terminal runtime receipt retains its existing human review path',
    () {
      const dispatch = <String, Object?>{
        'status': 'worker_finalized',
        'executionId': 'github:42:9001:work-ticket',
      };
      expect(agentPickupInFlight(activation, dispatch, now), false);
      expect(agentTicketResetAllowed(activation, dispatch, now), true);
    },
  );
}

Map<String, Object?> _project() => {
  'fields': {
    'nodes': [
      {
        'id': 'status',
        '__typename': 'ProjectV2SingleSelectField',
        'name': 'Status',
        'options': [
          {'id': 'todo', 'name': 'Todo'},
          {'id': 'working', 'name': 'In Progress'},
        ],
      },
    ],
  },
  'items': {
    'nodes': [
      {
        'id': 'item-legacy',
        'isArchived': false,
        'content': {'state': 'OPEN', 'body': ''},
        'fieldValues': {
          'nodes': [
            {
              'name': 'Todo',
              'field': {'id': 'status'},
            },
          ],
        },
      },
    ],
  },
};
