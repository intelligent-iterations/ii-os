import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'github_actions_oidc.dart';
import 'workspace_store.dart';

final class AgentFinalizationStore {
  AgentFinalizationStore(this.store, {DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  final WorkspaceStore store;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  Future<Map<String, Object?>> reserve({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
    required String resultDigest,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    return store.firestore.runTransaction<Map<String, Object?>>((
      transaction,
    ) async {
      final data = (await transaction.get(ref)).data();
      final exactRun =
          data?['workflowRunId'] == principal.runId &&
          data?['workflowRunAttempt'] == principal.runAttempt &&
          data?['workflowSha'] == principal.sha &&
          data?['repository'] == principal.repository &&
          data?['repositoryId'] == principal.repositoryId &&
          data?['projectItemId'] == projectItemId &&
          data?['issueNumber'] == issueNumber &&
          data?['claimId'] == claimId;
      if (!exactRun) throw _invalid;
      if (data?['status'] == 'finalized') {
        if (data?['finalResultDigest'] != resultDigest) throw _invalid;
        return {...data!, 'reservationState': 'finalized'};
      }
      if (data?['status'] == 'finalizing') {
        if (data?['finalResultDigest'] != resultDigest) throw _invalid;
        final startedAt = data?['finalizationStartedAt'];
        final now = _clock().toUtc();
        final started = startedAt is Timestamp
            ? startedAt.toDate().toUtc()
            : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        if (now.difference(started) < _lease) {
          throw const ApiError(
            409,
            'agent_dispatch_finalization_in_progress',
            'This exact agent result is already being finalized.',
          );
        }
        final reservationId = _uuid.v4();
        transaction.update(ref, {
          'finalizationReservationId': reservationId,
          'finalizationStartedAt': Timestamp.fromDate(now),
          'finalizationAttempt':
              ((data?['finalizationAttempt'] as num?)?.toInt() ?? 1) + 1,
          'updatedAt': Timestamp.fromDate(now),
        });
        return {
          ...data!,
          'reservationState': 'recovered',
          'finalizationReservationId': reservationId,
        };
      }
      if (data?['status'] != 'consumed') throw _invalid;
      final existingDigest = data?['finalResultDigest'];
      if (existingDigest != null && existingDigest != resultDigest) {
        throw _invalid;
      }
      final reservationId = _uuid.v4();
      final now = _clock().toUtc();
      transaction.update(ref, {
        'status': 'finalizing',
        'finalizationReservationId': reservationId,
        if (existingDigest == null) 'finalResultDigest': resultDigest,
        'finalizationStartedAt': Timestamp.fromDate(now),
        'finalizationAttempt':
            ((data?['finalizationAttempt'] as num?)?.toInt() ?? 0) + 1,
        'updatedAt': Timestamp.fromDate(now),
      });
      return {
        ...data!,
        'reservationState': 'reserved',
        'finalizationReservationId': reservationId,
      };
    });
  }

  Future<Map<String, Object?>> authorizePublication({
    required GitHubActionsPrincipal principal,
    required String workspaceId,
    required String projectItemId,
    required String claimId,
    required int issueNumber,
  }) async {
    final data = (await _ref(workspaceId, projectItemId).get()).data();
    final exactRun =
        data?['status'] == 'consumed' &&
        data?['workflowRunId'] == principal.runId &&
        data?['workflowRunAttempt'] == principal.runAttempt &&
        data?['workflowSha'] == principal.sha &&
        data?['trustedSourceSha'] == principal.sha &&
        data?['trustedSourceRef'] == principal.trustedRef &&
        data?['repository'] == principal.repository &&
        data?['repositoryId'] == principal.repositoryId &&
        data?['projectItemId'] == projectItemId &&
        data?['issueNumber'] == issueNumber &&
        data?['claimId'] == claimId;
    if (!exactRun) throw _invalid;
    return data!;
  }

  Future<void> release({
    required String workspaceId,
    required String projectItemId,
    required String reservationId,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data?['status'] == 'finalizing' &&
          data?['finalizationReservationId'] == reservationId) {
        transaction.update(ref, {
          'status': 'consumed',
          'finalizationReservationId': null,
          'updatedAt': Timestamp.now(),
        });
      }
    });
  }

  Future<void> complete({
    required String workspaceId,
    required String projectItemId,
    required String reservationId,
    required String outcome,
    required String projectStatus,
    required bool mutated,
    required String resultDigest,
    String? pullRequestUrl,
  }) async {
    final ref = _ref(workspaceId, projectItemId);
    final dispatchRef = store.firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('agentDispatches')
        .doc(projectItemId);
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data?['status'] != 'finalizing' ||
          data?['finalizationReservationId'] != reservationId ||
          data?['finalResultDigest'] != resultDigest) {
        throw _invalid;
      }
      final now = Timestamp.now();
      transaction.update(ref, {
        'status': 'finalized',
        'finalOutcome': outcome,
        'finalProjectStatus': projectStatus,
        'finalMutationApplied': mutated,
        // What the run actually produced. The broker already opened this pull
        // request; until now the URL was returned to the caller and dropped,
        // so a finished receipt could not say whether any code came out.
        'finalPullRequestUrl': pullRequestUrl,
        'finalizedAt': now,
        'finalizationReservationId': null,
        'updatedAt': now,
      });
      transaction.set(dispatchRef, {
        'status': 'worker_finalized',
        'finalOutcome': outcome,
        'finalProjectStatus': projectStatus,
        'finalEffectsPublished': mutated,
        'finalPullRequestUrl': pullRequestUrl,
        'finalizedAt': now,
        'updatedAt': now,
      }, options: const SetOptions.merge());
    });
  }

  DocumentReference<Map<String, Object?>> _ref(
    String workspaceId,
    String projectItemId,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('agentActivations')
      .doc(projectItemId);
}

const _invalid = ApiError(
  409,
  'agent_dispatch_finalization_invalid',
  'This result is not bound to the exact consumed agent dispatch.',
);

const _lease = Duration(minutes: 15);

DateTime _utcNow() => DateTime.now().toUtc();
