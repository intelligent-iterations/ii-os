import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_os_functions/src/agent_activation_store.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 26, 3, 0);

  test(
    'finished and failed receipts can be reset without deleting history',
    () {
      for (final state in const [
        ({'status': 'finalized'}, {'status': 'worker_finalized'}),
        ({'status': 'invalidated'}, {'status': 'approval_invalidated'}),
        ({'status': 'consumed'}, {'status': 'fleet_submission_failed'}),
        (<String, Object?>{}, <String, Object?>{}),
      ]) {
        expect(
          () => requireAgentTicketResetAllowed(state.$1, state.$2, now),
          returnsNormally,
        );
      }
    },
  );

  test('every live execution phase blocks reset', () {
    for (final state in const [
      ({'status': 'active'}, {'status': 'queued'}),
      ({'status': 'claiming'}, {'status': 'workflow_dispatching'}),
      ({'status': 'consumed'}, {'status': 'workflow_bound'}),
      ({'status': 'consumed'}, {'status': 'fleet_submitting'}),
      ({'status': 'consumed'}, {'status': 'fleet_queued'}),
      ({'status': 'consumed'}, {'status': 'fleet_running'}),
      (<String, Object?>{}, {'status': 'fleet_running'}),
      ({'status': 'consumed'}, {'status': 'fleet_cleaning'}),
      ({'status': 'consumed'}, {'status': 'fleet_cleaned'}),
      ({'status': 'finalizing'}, {'status': 'fleet_cleaned'}),
    ]) {
      expect(
        () => requireAgentTicketResetAllowed(state.$1, state.$2, now),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'agent_ticket_reset_active',
          ),
        ),
      );
    }
  });

  test('unknown receipt shapes fail closed instead of losing a workload', () {
    for (final state in const [
      ({'status': 'active'}, <String, Object?>{}),
      ({'status': 'consumed'}, <String, Object?>{}),
      (<String, Object?>{}, {'status': 'future_execution_phase'}),
    ]) {
      expect(
        () => requireAgentTicketResetAllowed(state.$1, state.$2, now),
        throwsA(
          isA<ApiError>().having(
            (error) => error.code,
            'code',
            'agent_ticket_reset_active',
          ),
        ),
      );
    }
  });

  test('expired claims and an interrupted reset remain recoverable', () {
    expect(
      () => requireAgentTicketResetAllowed(
        {
          'status': 'claiming',
          'claimExpiresAt': Timestamp.fromDate(
            now.subtract(const Duration(seconds: 1)),
          ),
        },
        const {'status': 'workflow_stalled'},
        now,
      ),
      returnsNormally,
    );
    expect(
      () => requireAgentTicketResetAllowed(
        const {'status': 'resetting'},
        const {'status': 'resetting'},
        now,
      ),
      returnsNormally,
    );
  });

  test('the reset marker blocks a concurrent deployment transaction', () {
    expect(
      agentPickupInFlight(
        const {'status': 'resetting'},
        const {'status': 'resetting'},
        now,
      ),
      isTrue,
    );
  });
}
