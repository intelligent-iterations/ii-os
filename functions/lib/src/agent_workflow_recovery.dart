import 'api_error.dart';

typedef AgentWorkflowRunReader =
    Future<Map<String, Object?>> Function(int runId);
typedef AgentWorkflowRunCanceller = Future<void> Function(int runId);
typedef AgentWorkflowRunDiscovery =
    Future<List<Map<String, Object?>>> Function(Map<String, Object?> dispatch);

const agentWorkflowStopProofStatuses = {
  'workflow_stalled',
  'fleet_submission_failed',
  'fleet_submission_stalled',
  'fleet_lifecycle_stalled',
  'fleet_finalization_stalled',
};

final class AgentWorkflowRecoveryProof {
  const AgentWorkflowRecoveryProof({
    required this.recoveryStatus,
    required this.requestId,
    required this.repository,
    required this.runId,
    required this.runAttempt,
    required this.workflowSha,
    required this.conclusion,
    required this.workflowWasBound,
    this.allowsNewerRunAttempt = false,
  });

  final String recoveryStatus;
  final String requestId;
  final String repository;
  final int? runId;
  final int? runAttempt;
  final String workflowSha;
  final String conclusion;
  final bool workflowWasBound;
  final bool allowsNewerRunAttempt;

  bool get workflowRunObserved => runId != null;

  bool matches(
    Map<String, Object?> dispatch,
    String currentRecoveryStatus, {
    Map<String, Object?> activation = const {},
  }) {
    if (recoveryStatus != currentRecoveryStatus ||
        dispatch['requestId'] != requestId ||
        dispatch['repository'] != repository) {
      return false;
    }
    if (workflowWasBound) {
      final storedAttempt = dispatch['workflowRunAttempt'];
      final exactIdentity =
          dispatch['workflowRunId'] == runId &&
          dispatch['workflowSha'] == workflowSha &&
          storedAttempt is int &&
          runAttempt is int;
      if (!exactIdentity) return false;
      if (!allowsNewerRunAttempt) return storedAttempt == runAttempt;
      return activation['status'] == 'claiming' &&
          activation['claimId'] == requestId &&
          activation['workflowRunId'] == runId &&
          activation['workflowSha'] == workflowSha &&
          activation['workflowRunAttempt'] == storedAttempt &&
          runAttempt! >= storedAttempt;
    }
    return dispatch['workflowRunId'] == null &&
        dispatch['workflowRunAttempt'] == null &&
        dispatch['workflowSha'] == null &&
        dispatch['trustedSourceSha'] == workflowSha;
  }
}

/// Stops an exact abandoned GitHub workflow before its ticket can be replaced.
///
/// The Firestore transaction independently compares the returned proof with
/// the still-current receipt. A callback that wins this race changes that
/// receipt and prevents replacement; a callback that loses it no longer
/// matches the claim.
final class AgentWorkflowRecovery {
  AgentWorkflowRecovery({
    required this.readRun,
    required this.cancelRun,
    required this.discoverRuns,
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;

  final AgentWorkflowRunReader readRun;
  final AgentWorkflowRunCanceller cancelRun;
  final AgentWorkflowRunDiscovery discoverRuns;
  final Future<void> Function(Duration) delay;

  Future<AgentWorkflowRecoveryProof?> stopIfRequired({
    required String recoveryStatus,
    required String repository,
    required Map<String, Object?> dispatch,
    bool allowNewerRunAttempt = false,
  }) async {
    if (!agentWorkflowStopProofStatuses.contains(recoveryStatus)) return null;
    final runId = dispatch['workflowRunId'];
    final runAttempt = dispatch['workflowRunAttempt'];
    final requestId = dispatch['requestId'];
    if (dispatch['repository'] != repository ||
        requestId is! String ||
        requestId.isEmpty) {
      throw _identityInvalid;
    }

    final workflowWasBound = runId != null;
    late final String workflowSha;
    late Map<String, Object?> run;
    if (workflowWasBound) {
      workflowSha = dispatch['workflowSha'] as String? ?? '';
      if (runId is! int ||
          runId <= 0 ||
          runAttempt is! int ||
          runAttempt <= 0 ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(workflowSha)) {
        throw _identityInvalid;
      }
      run = await readRun(runId);
      final observedAttempt = run['run_attempt'];
      final mayAdvanceAttempt =
          allowNewerRunAttempt && recoveryStatus == 'workflow_stalled';
      if (observedAttempt is! int ||
          (mayAdvanceAttempt
              ? observedAttempt < runAttempt
              : observedAttempt != runAttempt)) {
        throw _identityInvalid;
      }
      _requireExactRun(run, repository, runId, observedAttempt, workflowSha);
    } else {
      if (recoveryStatus != 'workflow_stalled' ||
          runAttempt != null ||
          dispatch['workflowSha'] != null ||
          dispatch['issueNumber'] is! int ||
          (dispatch['issueNumber'] as int) <= 0 ||
          dispatch['trustedSourceRef'] !=
              'ii-os-agent-v4-${dispatch['trustedSourceSha']}') {
        throw _identityInvalid;
      }
      workflowSha = dispatch['trustedSourceSha'] as String? ?? '';
      if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(workflowSha)) {
        throw _identityInvalid;
      }
      final candidates = await discoverRuns(dispatch);
      if (candidates.length > 1) throw _identityInvalid;
      if (candidates.isEmpty) {
        return AgentWorkflowRecoveryProof(
          recoveryStatus: recoveryStatus,
          requestId: requestId,
          repository: repository,
          runId: null,
          runAttempt: null,
          workflowSha: workflowSha,
          conclusion: 'not_created',
          workflowWasBound: false,
        );
      }
      run = candidates.single;
      final discoveredRunId = run['id'];
      final discoveredAttempt = run['run_attempt'];
      if (discoveredRunId is! int || discoveredAttempt is! int) {
        throw _identityInvalid;
      }
      _requireExactRun(
        run,
        repository,
        discoveredRunId,
        discoveredAttempt,
        workflowSha,
      );
    }

    final exactRunId = run['id'] as int;
    final exactRunAttempt = run['run_attempt'] as int;
    if (run['status'] != 'completed') {
      await cancelRun(exactRunId);
      for (var attempt = 0; attempt < 40; attempt++) {
        await delay(const Duration(milliseconds: 250));
        run = await readRun(exactRunId);
        _requireExactRun(
          run,
          repository,
          exactRunId,
          exactRunAttempt,
          workflowSha,
        );
        if (run['status'] == 'completed') break;
      }
    }
    if (run['status'] != 'completed') throw _stopPending;
    final conclusion = run['conclusion'];
    if (conclusion is! String || conclusion.isEmpty) throw _identityInvalid;
    return AgentWorkflowRecoveryProof(
      recoveryStatus: recoveryStatus,
      requestId: requestId,
      repository: repository,
      runId: exactRunId,
      runAttempt: exactRunAttempt,
      workflowSha: workflowSha,
      conclusion: conclusion,
      workflowWasBound: workflowWasBound,
      allowsNewerRunAttempt:
          workflowWasBound &&
          allowNewerRunAttempt &&
          exactRunAttempt > (runAttempt as int? ?? exactRunAttempt),
    );
  }
}

void _requireExactRun(
  Map<String, Object?> run,
  String repository,
  int runId,
  int runAttempt,
  String workflowSha,
) {
  final runRepository = run['repository'];
  if (run['id'] != runId ||
      run['run_attempt'] != runAttempt ||
      run['event'] != 'workflow_dispatch' ||
      run['head_sha'] != workflowSha ||
      runRepository is! Map<String, Object?> ||
      runRepository['full_name'] != repository ||
      !const {
        'queued',
        'in_progress',
        'pending',
        'requested',
        'waiting',
        'completed',
      }.contains(run['status'])) {
    throw _identityInvalid;
  }
}

const _identityInvalid = ApiError(
  409,
  'agent_recovery_workflow_invalid',
  'The stopped workflow no longer matches this ticket. Refresh before deploying it again.',
);

const _stopPending = ApiError(
  409,
  'agent_recovery_stop_pending',
  'The previous workflow is still stopping. Wait a moment, then press Deploy again.',
);
