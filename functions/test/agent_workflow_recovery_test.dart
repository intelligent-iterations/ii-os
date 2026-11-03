import 'package:ii_os_functions/src/agent_workflow_recovery.dart';
import 'package:ii_os_functions/src/api_error.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a completed exact run produces replacement proof without cancellation',
    () async {
      var cancelCalls = 0;
      final recovery = AgentWorkflowRecovery(
        readRun: (_) async =>
            _run(status: 'completed', conclusion: 'cancelled'),
        cancelRun: (_) async => cancelCalls += 1,
        discoverRuns: (_) async => const [],
        delay: (_) async {},
      );

      final proof = await recovery.stopIfRequired(
        recoveryStatus: 'workflow_stalled',
        repository: 'acme-co/example-app',
        dispatch: _dispatch(),
      );

      expect(proof, isNotNull);
      expect(cancelCalls, 0);
      expect(proof!.matches(_dispatch(), 'workflow_stalled'), isTrue);
    },
  );

  test('an active exact run is cancelled and observed stopped', () async {
    var reads = 0;
    var cancelCalls = 0;
    final recovery = AgentWorkflowRecovery(
      readRun: (_) async => _run(
        status: reads++ == 0 ? 'in_progress' : 'completed',
        conclusion: reads > 1 ? 'cancelled' : null,
      ),
      cancelRun: (_) async => cancelCalls += 1,
      discoverRuns: (_) async => const [],
      delay: (_) async {},
    );

    final proof = await recovery.stopIfRequired(
      recoveryStatus: 'fleet_finalization_stalled',
      repository: 'acme-co/example-app',
      dispatch: _dispatch(),
    );

    expect(proof, isNotNull);
    expect(cancelCalls, 1);
    expect(reads, 2);
  });

  test('a mismatched run cannot authorize replacement', () async {
    final recovery = AgentWorkflowRecovery(
      readRun: (_) async => {
        ..._run(status: 'completed', conclusion: 'failure'),
        'head_sha': '2222222222222222222222222222222222222222',
      },
      cancelRun: (_) async {},
      discoverRuns: (_) async => const [],
      delay: (_) async {},
    );

    expect(
      () => recovery.stopIfRequired(
        recoveryStatus: 'fleet_lifecycle_stalled',
        repository: 'acme-co/example-app',
        dispatch: _dispatch(),
      ),
      throwsA(isA<ApiError>()),
    );
  });

  test('non-recovery state performs no GitHub read', () async {
    var reads = 0;
    final recovery = AgentWorkflowRecovery(
      readRun: (_) async {
        reads += 1;
        return _run(status: 'completed', conclusion: 'success');
      },
      cancelRun: (_) async {},
      discoverRuns: (_) async => const [],
      delay: (_) async {},
    );

    expect(
      await recovery.stopIfRequired(
        recoveryStatus: 'fleet_queued',
        repository: 'acme-co/example-app',
        dispatch: _dispatch(),
      ),
      isNull,
    );
    expect(reads, 0);
  });

  test(
    'an immediate submission failure still proves the run stopped',
    () async {
      var cancelCalls = 0;
      final recovery = AgentWorkflowRecovery(
        readRun: (_) async => _run(status: 'completed', conclusion: 'failure'),
        cancelRun: (_) async => cancelCalls += 1,
        discoverRuns: (_) async => const [],
        delay: (_) async {},
      );

      final proof = await recovery.stopIfRequired(
        recoveryStatus: 'fleet_submission_failed',
        repository: 'acme-co/example-app',
        dispatch: _dispatch(),
      );

      expect(proof, isNotNull);
      expect(cancelCalls, 0);
      expect(proof!.matches(_dispatch(), 'fleet_submission_failed'), isTrue);
    },
  );

  test(
    'an unbound dispatch discovers and stops its exact titled run',
    () async {
      var cancelCalls = 0;
      final unbound = _unboundDispatch();
      final recovery = AgentWorkflowRecovery(
        readRun: (_) async =>
            _run(status: 'completed', conclusion: 'cancelled'),
        cancelRun: (_) async => cancelCalls += 1,
        discoverRuns: (dispatch) async {
          expect(dispatch, same(unbound));
          return [_run(status: 'in_progress', conclusion: null)];
        },
        delay: (_) async {},
      );

      final proof = await recovery.stopIfRequired(
        recoveryStatus: 'workflow_stalled',
        repository: 'acme-co/example-app',
        dispatch: unbound,
      );

      expect(proof, isNotNull);
      expect(cancelCalls, 1);
      expect(proof!.matches(unbound, 'workflow_stalled'), isTrue);
      expect(
        proof.matches({...unbound, 'workflowRunId': 9001}, 'workflow_stalled'),
        isFalse,
        reason:
            'a self-binding callback that wins the race rejects replacement',
      );
    },
  );

  test(
    'an observed absent unbound run rotates only its exact stale claim',
    () async {
      final unbound = _unboundDispatch();
      final recovery = AgentWorkflowRecovery(
        readRun: (_) async => throw StateError('no run should be read'),
        cancelRun: (_) async => throw StateError('no run should be cancelled'),
        discoverRuns: (_) async => const [],
        delay: (_) async {},
      );

      final proof = await recovery.stopIfRequired(
        recoveryStatus: 'workflow_stalled',
        repository: 'acme-co/example-app',
        dispatch: unbound,
      );

      expect(proof, isNotNull);
      expect(proof!.matches(unbound, 'workflow_stalled'), isTrue);
      expect(proof.workflowRunObserved, isFalse);
    },
  );

  test('ambiguous unbound run discovery fails closed', () async {
    final recovery = AgentWorkflowRecovery(
      readRun: (_) async => _run(status: 'completed', conclusion: 'cancelled'),
      cancelRun: (_) async {},
      discoverRuns: (_) async => [
        _run(status: 'queued', conclusion: null),
        {..._run(status: 'queued', conclusion: null), 'id': 9002},
      ],
      delay: (_) async {},
    );

    expect(
      () => recovery.stopIfRequired(
        recoveryStatus: 'workflow_stalled',
        repository: 'acme-co/example-app',
        dispatch: _unboundDispatch(),
      ),
      throwsA(isA<ApiError>()),
    );
  });

  test(
    'a stopped newer attempt of the same unconsumed run is recoverable',
    () async {
      final recovery = AgentWorkflowRecovery(
        readRun: (_) async => {
          ..._run(status: 'completed', conclusion: 'failure'),
          'run_attempt': 2,
        },
        cancelRun: (_) async {},
        discoverRuns: (_) async => const [],
        delay: (_) async {},
      );

      final proof = await recovery.stopIfRequired(
        recoveryStatus: 'workflow_stalled',
        repository: 'acme-co/example-app',
        dispatch: _dispatch(),
        allowNewerRunAttempt: true,
      );

      expect(proof, isNotNull);
      expect(proof!.runAttempt, 2);
      expect(
        proof.matches(
          _dispatch(),
          'workflow_stalled',
          activation: const {
            'status': 'claiming',
            'claimId': 'dispatch-1',
            'workflowRunId': 9001,
            'workflowRunAttempt': 1,
            'workflowSha': '1111111111111111111111111111111111111111',
          },
        ),
        isTrue,
      );
    },
  );

  test(
    'a consumed run cannot heal through an unrecorded newer attempt',
    () async {
      final recovery = AgentWorkflowRecovery(
        readRun: (_) async => {
          ..._run(status: 'completed', conclusion: 'failure'),
          'run_attempt': 2,
        },
        cancelRun: (_) async {},
        discoverRuns: (_) async => const [],
        delay: (_) async {},
      );

      expect(
        () => recovery.stopIfRequired(
          recoveryStatus: 'fleet_lifecycle_stalled',
          repository: 'acme-co/example-app',
          dispatch: _dispatch(),
        ),
        throwsA(isA<ApiError>()),
      );
    },
  );
}

Map<String, Object?> _dispatch() => const {
  'requestId': 'dispatch-1',
  'repository': 'acme-co/example-app',
  'workflowRunId': 9001,
  'workflowRunAttempt': 1,
  'workflowSha': '1111111111111111111111111111111111111111',
};

Map<String, Object?> _unboundDispatch() => const {
  'status': 'workflow_dispatching',
  'requestId': 'dispatch-1',
  'repository': 'acme-co/example-app',
  'issueNumber': 42,
  'trustedSourceSha': '1111111111111111111111111111111111111111',
  'trustedSourceRef': 'ii-os-agent-v4-1111111111111111111111111111111111111111',
};

Map<String, Object?> _run({
  required String status,
  required String? conclusion,
}) => {
  'id': 9001,
  'run_attempt': 1,
  'event': 'workflow_dispatch',
  'status': status,
  'conclusion': conclusion,
  'head_sha': '1111111111111111111111111111111111111111',
  'repository': {'full_name': 'acme-co/example-app'},
};
