import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'agent_permission_profile.dart';
import 'api_error.dart';
import 'github_actions_oidc.dart';
import 'providers/firebase/codex_credential_store.dart';
import 'workspace_store.dart';

part 'codex_auth_policy.dart';

const codexAuthFailureMarker = '<!-- ii-os:codex-auth-failed -->';

final class CodexAuthStore {
  CodexAuthStore({
    required this.store,
    DateTime Function()? clock,
    this._uuid = const Uuid(),
  }) : _clock = clock ?? _utcNow;

  final WorkspaceStore store;
  final DateTime Function() _clock;
  final Uuid _uuid;

  CollectionReference<Map<String, Object?>> get _sessions =>
      store.firestore.collection('codexAuthSessions');

  Future<Map<String, Object?>> createSession({
    required String workspaceId,
    required String repository,
    required int repositoryId,
    required String requestedBy,
    required String trustedSourceSha,
    required String trustedSourceRef,
    bool reauthenticate = false,
  }) async {
    _validateRepository(repository, repositoryId);
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(trustedSourceSha) ||
        trustedSourceRef != 'ii-os-agent-v4-$trustedSourceSha') {
      throw _transitionInvalid;
    }
    final now = _clock();
    final newId = _uuid.v4();
    final stateRef = _stateRef(workspaceId, repository);
    late String id;
    late Map<String, Object?> data;
    var created = false;
    await store.firestore.runTransaction<void>((transaction) async {
      final current = (await transaction.get(stateRef)).data();
      var previous = current?['status'] ?? 'unknown';
      if (current?['status'] == 'revocation_required') {
        final blockedId = current?['sessionId'];
        final blocked = blockedId is String
            ? (await transaction.get(_sessions.doc(blockedId))).data()
            : null;
        if (blocked != null && _writerTokenOutstanding(blocked, now)) {
          throw const ApiError(
            409,
            'codex_auth_writer_revocation_pending',
            'A temporary GitHub token must expire before Codex can be reconnected.',
          );
        }
        previous = 'stored';
      }
      if (current?['status'] == 'refreshing') {
        final activeId = current?['sessionId'];
        if (activeId is String && activeId.isNotEmpty) {
          final activeRef = _sessions.doc(activeId);
          final active = (await transaction.get(activeRef)).data();
          if (active != null) {
            previous = active['previousAuthStatus'] ?? 'unknown';
            if (_isActive(active['status']) &&
                !_isExpired(active) &&
                active['trustedSourceSha'] == trustedSourceSha &&
                active['trustedSourceRef'] == trustedSourceRef) {
              if ((active['reauthenticate'] ?? false) != reauthenticate) {
                throw const ApiError(
                  409,
                  'codex_auth_session_active',
                  'Finish the current Codex verification before starting a new sign-in.',
                );
              }
              id = activeId;
              data = active;
              return;
            }
            if (_writerTokenOutstanding(active, now)) {
              throw const ApiError(
                409,
                'codex_auth_writer_revocation_pending',
                'A temporary GitHub token must expire before Codex can be reconnected.',
              );
            }
            if (_isActive(active['status'])) {
              transaction.update(activeRef, {
                'status': 'expired',
                'errorCode': 'codex_auth_session_expired',
                'detail': 'The OpenAI sign-in window expired.',
                'updatedAt': Timestamp.fromDate(now),
              });
            }
          }
        }
      }
      id = newId;
      created = true;
      data = {
        'workspaceId': workspaceId,
        'repository': repository,
        'repositoryId': repositoryId,
        'status': 'dispatching',
        'previousAuthStatus': previous,
        'requestedBy': requestedBy,
        'trustedSourceSha': trustedSourceSha,
        'trustedSourceRef': trustedSourceRef,
        'reauthenticate': reauthenticate,
        'dispatchNonce': _uuid.v4(),
        'verificationNonce': _uuid.v4(),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(minutes: 45))),
        'verificationUrl': null,
        'userCode': null,
        'runId': null,
        'runAttempt': null,
        'runUrl': null,
        'workflowSha': null,
        'verificationRunId': null,
        'verificationRunAttempt': null,
        'verificationWorkflowSha': null,
        'verificationDispatchStatus': 'none',
        'errorCode': null,
        'detail': null,
        'writerTokenIssueCount': 0,
        'writerTokenStatus': 'none',
      };
      transaction.create(_sessions.doc(id), data);
      transaction.set(stateRef, {
        'repository': repository,
        'status': 'refreshing',
        'sessionId': id,
        'updatedAt': Timestamp.fromDate(now),
      }, options: const SetOptions.merge());
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
    return {..._publicSession(id, data), 'created': created};
  }

  Future<Map<String, Object?>> getSession({
    required String workspaceId,
    required String sessionId,
  }) async {
    final data = await _sessionData(sessionId);
    if (data == null || data['workspaceId'] != workspaceId) {
      throw _sessionNotFound;
    }
    if (_isActive(data['status']) && _isExpired(data)) {
      await failSession(
        workspaceId: workspaceId,
        sessionId: sessionId,
        errorCode: 'codex_auth_session_expired',
        detail: 'The OpenAI sign-in window expired. Start a new verification.',
        status: 'expired',
      );
      return getSession(workspaceId: workspaceId, sessionId: sessionId);
    }
    return _publicSession(sessionId, data);
  }

  Future<Map<String, Object?>> workflowSession(String sessionId) async {
    final data = await _sessionData(sessionId);
    if (data == null) throw _sessionNotFound;
    return data;
  }

  Future<Map<String, Object?>> recordWorkflowEvent({
    required GitHubActionsPrincipal principal,
    required String sessionId,
    required Map<String, Object?> event,
  }) async {
    final status = event['status'];
    if (status is! String || !_workflowStatuses.contains(status)) {
      throw const ApiError(
        400,
        'codex_auth_status_invalid',
        'The Codex verification status is invalid.',
      );
    }
    _requireWorkflowRole(principal, status);
    final now = _clock();
    final ref = _sessions.doc(sessionId);
    late Map<String, Object?> updated;
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      _requireWorkflowSession(data, principal);
      if (_isExpired(data!)) throw _sessionExpired;
      final current = data['status'] as String? ?? 'dispatching';
      if (!codexAuthTransitionAllowed(current, status)) {
        throw _transitionInvalid;
      }
      if (current == status) {
        if (!_sameRetry(data, event, status)) throw _transitionInvalid;
        updated = data;
        return;
      }
      if (status == 'awaiting_cleanup') {
        _requireSecretStored(data, event);
      }
      if (status == 'succeeded') _requireFinalizationReady(data, event);
      final bindingRef = CodexCredentialStore(
        store,
      ).bindingRef(principal.repositoryId);
      final binding = status == 'succeeded'
          ? (await transaction.get(bindingRef)).data()
          : null;
      if (binding != null &&
          (binding['secretDigest'] != event['secretDigest'] ||
              binding['lease'] != null)) {
        throw _transitionInvalid;
      }
      final verification = principal.jobUses(iiOsCodexAuthFinalizeWorkflow);
      final values = <String, Object?>{
        'status': status,
        if (verification)
          'verificationRunId': principal.runId
        else
          'runId': principal.runId,
        if (verification)
          'verificationRunAttempt': principal.runAttempt
        else
          'runAttempt': principal.runAttempt,
        if (verification)
          'verificationWorkflowSha': principal.sha
        else
          'workflowSha': principal.sha,
        'updatedAt': Timestamp.fromDate(now),
        ..._workflowMetadata(event, status, now),
      };
      transaction.update(ref, values);
      updated = {...data, ...values};
      if (status == 'succeeded') {
        transaction.set(
          _stateRef(
            data['workspaceId'] as String,
            data['repository'] as String,
          ),
          {
            'repository': data['repository'],
            'repositoryId': principal.repositoryId,
            'status': 'valid',
            'sessionId': sessionId,
            'workflowRunId': principal.runId,
            'workflowSha': principal.sha,
            'secretUpdatedAt': data['secretUpdatedAt'],
            'secretDigest': data['secretDigest'],
            'validatedAt': Timestamp.fromDate(now),
            'updatedAt': Timestamp.fromDate(now),
            'failureCode': null,
            'detail': null,
          },
          options: const SetOptions.merge(),
        );
        if (binding != null) {
          transaction.update(bindingRef, {
            'status': 'valid',
            'validatedAt': Timestamp.fromDate(now),
            'workflowRunId': principal.runId,
            'workflowSha': principal.sha,
            'updatedAt': Timestamp.fromDate(now),
          });
        }
      } else if (_terminalStatuses.contains(status)) {
        _restoreState(transaction, sessionId, updated, now);
      }
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
    return _publicSession(sessionId, updated);
  }

  Future<String> reserveSecretWriter({
    required GitHubActionsPrincipal principal,
    required String sessionId,
  }) async {
    if (!principal.jobUses(iiOsCodexAuthWorkflow)) throw _sessionNotFound;
    final reservationId = _uuid.v4();
    final ref = _sessions.doc(sessionId);
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      _requireWorkflowSession(data, principal);
      if (_isExpired(data!)) throw _sessionExpired;
      if (data['status'] != 'writing_secret' ||
          data['writerTokenStatus'] != 'none' ||
          data['writerTokenIssueCount'] != 0) {
        throw const ApiError(
          429,
          'codex_auth_writer_limit',
          'The temporary secret-writer token was already reserved.',
        );
      }
      transaction.update(ref, {
        'writerTokenStatus': 'reserved',
        'writerTokenReservationId': reservationId,
        'writerTokenReservedAt': Timestamp.fromDate(_clock()),
        'writerTokenExpiresAt': Timestamp.fromDate(
          _clock().add(const Duration(hours: 1)),
        ),
      });
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
    return reservationId;
  }

  Future<void> recordSecretWriterIssued({
    required String sessionId,
    required String reservationId,
    required DateTime expiresAt,
  }) async {
    final now = _clock();
    if (!expiresAt.isAfter(now) ||
        expiresAt.isAfter(now.add(const Duration(hours: 1, minutes: 5)))) {
      throw _transitionInvalid;
    }
    final ref = _sessions.doc(sessionId);
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data?['status'] != 'writing_secret' ||
          data?['writerTokenStatus'] != 'reserved' ||
          data?['writerTokenReservationId'] != reservationId) {
        throw _transitionInvalid;
      }
      transaction.update(ref, {
        'writerTokenStatus': 'issued',
        'writerTokenIssueCount': 1,
        'writerTokenIssuedAt': Timestamp.fromDate(now),
        'writerTokenExpiresAt': Timestamp.fromDate(expiresAt),
      });
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  Future<void> releaseSecretWriterReservation({
    required String sessionId,
    required String reservationId,
  }) async {
    final ref = _sessions.doc(sessionId);
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data?['writerTokenStatus'] == 'reserved' &&
          data?['writerTokenReservationId'] == reservationId) {
        transaction.update(ref, {
          'writerTokenStatus': 'none',
          'writerTokenReservationId': null,
          'writerTokenReservedAt': null,
        });
      }
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  Future<void> failSession({
    required String workspaceId,
    required String sessionId,
    required String errorCode,
    required String detail,
    String status = 'failed',
  }) async {
    final now = _clock();
    final ref = _sessions.doc(sessionId);
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data == null ||
          data['workspaceId'] != workspaceId ||
          _terminalStatuses.contains(data['status'])) {
        return;
      }
      final updated = {
        ...data,
        'status': status,
        'errorCode': _bounded(errorCode, 100),
        'detail': _bounded(detail, 500),
        'updatedAt': Timestamp.fromDate(now),
      };
      transaction.update(ref, updated);
      _restoreState(transaction, sessionId, updated, now);
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  Future<void> attachWorkflowRun({
    required String workspaceId,
    required String sessionId,
    required int runId,
    required int runAttempt,
    required String runUrl,
    required String workflowSha,
    bool verification = false,
  }) async {
    if (runId <= 0 ||
        runAttempt <= 0 ||
        !_isGitHubRunUrl(runUrl) ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(workflowSha)) {
      throw _transitionInvalid;
    }
    final ref = _sessions.doc(sessionId);
    await store.firestore.runTransaction<void>((transaction) async {
      final data = (await transaction.get(ref)).data();
      final requiredStatus = verification ? 'awaiting_cleanup' : 'dispatching';
      if (data == null ||
          data['workspaceId'] != workspaceId ||
          data['status'] != requiredStatus) {
        throw _sessionNotFound;
      }
      if (data['trustedSourceSha'] != workflowSha) throw _transitionInvalid;
      final runKey = verification ? 'verificationRunId' : 'runId';
      final attemptKey = verification ? 'verificationRunAttempt' : 'runAttempt';
      final shaKey = verification ? 'verificationWorkflowSha' : 'workflowSha';
      final existing = (data[runKey] as num?)?.toInt();
      if (existing != null &&
          (existing != runId ||
              data[attemptKey] != runAttempt ||
              data[shaKey] != workflowSha)) {
        throw _transitionInvalid;
      }
      transaction.update(ref, {
        runKey: runId,
        attemptKey: runAttempt,
        if (verification) 'verificationRunUrl': runUrl else 'runUrl': runUrl,
        shaKey: workflowSha,
        if (verification) 'verificationDispatchStatus': 'bound',
        'updatedAt': Timestamp.fromDate(_clock()),
      });
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  Future<bool> reserveVerificationDispatch({
    required String sessionId,
    required GitHubActionsPrincipal principal,
  }) async {
    final ref = _sessions.doc(sessionId);
    return store.firestore.runTransaction<bool>((transaction) async {
      final data = (await transaction.get(ref)).data();
      _requireWorkflowSession(data, principal);
      if (data?['status'] != 'awaiting_cleanup') throw _transitionInvalid;
      if (data?['verificationDispatchStatus'] != 'none') return false;
      transaction.update(ref, {
        'verificationDispatchStatus': 'dispatching',
        'updatedAt': Timestamp.fromDate(_clock()),
      });
      return true;
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  Future<Map<String, Object?>?> repositoryState(
    String workspaceId,
    String repository, {
    int? repositoryId,
  }) async {
    final credentials = CodexCredentialStore(store);
    if (repositoryId != null) {
      final current = await credentials.current(repositoryId);
      if (current != null) return _publicState(current);
    }
    final data = (await _stateRef(workspaceId, repository).get()).data();
    final id = repositoryId ?? data?['repositoryId'];
    if (id is int && id > 0) {
      final current = repositoryId == null
          ? await credentials.current(id)
          : null;
      if (current != null) return _publicState(current);
    }
    return data == null ? null : _publicState(data);
  }

  Future<void> markInvalid({
    required String workspaceId,
    required String repository,
    required String failureCode,
    required String detail,
    int? workflowRunId,
  }) async {
    final now = _clock();
    await _stateRef(workspaceId, repository).set({
      'repository': repository,
      'status': 'invalid',
      'failureCode': _bounded(failureCode, 100),
      'detail': _bounded(detail, 500),
      'workflowRunId': workflowRunId,
      'failedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    }, options: const SetOptions.merge());
  }

  Future<Map<String, Object?>?> _sessionData(String id) async =>
      (await _sessions.doc(id).get()).data();

  DocumentReference<Map<String, Object?>> _stateRef(
    String workspaceId,
    String repository,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('codexAuth')
      .doc(repository.replaceAll('/', '~'));

  bool _isExpired(Map<String, Object?> data) {
    final expiresAt = data['expiresAt'];
    return expiresAt is! Timestamp ||
        expiresAt.toDate().toUtc().isBefore(_clock());
  }

  void _restoreState(
    Transaction transaction,
    String sessionId,
    Map<String, Object?> data,
    DateTime now,
  ) {
    final secretChanged = data['secretUpdatedAt'] is Timestamp;
    final tokenOutstanding = _writerTokenOutstanding(data, now);
    const restorable = {'valid', 'invalid', 'unknown', 'stored'};
    final previous = restorable.contains(data['previousAuthStatus'])
        ? data['previousAuthStatus'] as String
        : 'unknown';
    transaction.set(
      _stateRef(data['workspaceId'] as String, data['repository'] as String),
      {
        'repository': data['repository'],
        'status': tokenOutstanding
            ? 'revocation_required'
            : secretChanged
            ? 'stored'
            : previous,
        'sessionId': sessionId,
        if (secretChanged) 'secretUpdatedAt': data['secretUpdatedAt'],
        'updatedAt': Timestamp.fromDate(now),
      },
      options: const SetOptions.merge(),
    );
  }
}
