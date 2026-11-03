import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../api_error.dart';
import '../../codex_credential_policy.dart';
import '../../workspace_store.dart';

/// One global metadata fence per provider repository secret, across workspaces.
final class CodexCredentialStore {
  const CodexCredentialStore(this.store);
  final WorkspaceStore store;

  DocumentReference<Map<String, Object?>> bindingRef(int repositoryId) => store
      .firestore
      .collection('codexCredentialBindings')
      .doc(codexCredentialBindingId(repositoryId));

  DocumentReference<Map<String, Object?>> stateRef(
    CodexCredentialOwner owner,
  ) => store.firestore
      .collection('workspaces')
      .doc(owner.workspaceId)
      .collection('codexAuth')
      .doc(owner.principal.repository.replaceAll('/', '~'));

  Future<Map<String, Object?>?> current(int repositoryId) async =>
      (await bindingRef(repositoryId).get()).data();

  DocumentReference<Map<String, Object?>> contextRef(
    CodexCredentialOwner owner,
  ) {
    return owner.ticket
        ? store.firestore
              .collection('workspaces')
              .doc(owner.workspaceId)
              .collection('agentActivations')
              .doc(owner.projectItemId!)
        : store.firestore.collection('codexAuthSessions').doc(owner.subjectId);
  }

  Future<Map<String, Object?>> acquire(
    CodexCredentialOwner owner,
    Map<String, Object?> body, {
    Map<String, Object?>? providerMetadata,
  }) async {
    final original = body['originalDigest'];
    final operation = body['operationId'];
    if ((owner.principal.runAttempt != 1 && body['cleanupOnly'] != true) ||
        !credentialDigestValid(original, allowEmpty: owner.initialAuth) ||
        operation is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$').hasMatch(operation)) {
      throw credentialConflict;
    }
    final ref = bindingRef(owner.principal.repositoryId);
    final reservation = const Uuid().v4();
    return store.firestore.runTransaction<Map<String, Object?>>((tx) async {
      final binding = (await tx.get(ref)).data();
      final previous = (await tx.get(stateRef(owner))).data();
      final cleanupOnly = body['cleanupOnly'] == true;
      final existingContext = (await tx.get(contextRef(owner))).data();
      final context = _leaseContext(owner, existingContext, cleanupOnly);
      if (!cleanupOnly) owner.requireContext(context);
      final priorReceipt = context?[owner.receiptField];
      if (priorReceipt is Map &&
          owner.matchesCleanup(priorReceipt['owner'], body)) {
        if (cleanupOnly && priorReceipt['operationId'] == operation) {
          return {
            ..._reservation(priorReceipt.cast<String, Object?>()),
            ..._committed(priorReceipt.cast<String, Object?>()),
          };
        }
        throw credentialConflict;
      }
      final existing = binding?['lease'];
      if (existing is Map) {
        if (owner.matchesCleanup(existing['owner'], body) &&
            existing['operationId'] == operation &&
            existing['originalDigest'] == original) {
          return _reservation(existing.cast<String, Object?>());
        }
        throw const ApiError(
          409,
          'credential_in_use',
          'Another execution still owns this repository credential.',
        );
      }
      if (cleanupOnly) throw credentialConflict;
      final completed = binding?['completed'];
      if (completed is Map &&
          owner.matchesCleanup(completed['owner'], body) &&
          completed['operationId'] == operation) {
        throw credentialConflict;
      }
      final known = binding?['secretDigest'] ?? previous?['secretDigest'] ?? '';
      final previousVersion =
          binding?['secretUpdatedAt'] ?? previous?['secretUpdatedAt'];
      final attested = owner.initialAuth && providerMetadata != null;
      final exists = providerMetadata?['exists'];
      final rawVersion = providerMetadata?['secretUpdatedAt'];
      final providerVersion = rawVersion is DateTime
          ? Timestamp.fromDate(rawVersion)
          : rawVersion;
      if (attested &&
          (exists is! bool ||
              (exists && providerVersion is! Timestamp) ||
              (exists && original == '') ||
              (!exists && original != ''))) {
        throw credentialConflict;
      }
      final sameVersion =
          !attested ||
          (providerVersion is Timestamp && previousVersion is Timestamp
              ? providerVersion.toDate().isAtSameMomentAs(
                  previousVersion.toDate(),
                )
              : providerVersion == previousVersion);
      final repair = known != original || !sameVersion;
      final freshLogin =
          attested &&
          (context?['reauthenticate'] == true ||
              (original == '' && exists == false));
      final initialVerification =
          attested &&
          binding == null &&
          known == '' &&
          previous?['secretDigest'] == null;
      if (repair && !freshLogin && !initialVerification) {
        throw const ApiError(
          409,
          'credential_snapshot_stale',
          'The credential changed after this workflow was queued.',
        );
      }
      final status = repair
          ? 'stored'
          : binding?['status'] ?? previous?['status'];
      if (owner.usesVerifiedCredential && status != 'valid') {
        throw credentialConflict;
      }
      final generation =
          (binding?['generation'] as int? ?? 0) + (repair ? 1 : 0);
      final sourceVersion = attested ? providerVersion : previousVersion;
      final lease = <String, Object?>{
        'owner': owner.toJson(),
        'operationId': operation,
        'reservationId': reservation,
        'fence': (binding?['fence'] as int? ?? 0) + 1,
        'generation': generation,
        'originalDigest': original,
        'writerStatus': 'none',
        'previousStatus': status ?? 'stored',
        'originalUpdatedAt': sourceVersion,
        'createdAt': Timestamp.now(),
      };
      tx.set(ref, {
        'provider': 'github-actions',
        'authority': 'github.com',
        'repositoryId': owner.principal.repositoryId,
        'repository': owner.principal.repository,
        'secretName': 'CODEX_AUTH_JSON',
        'secretDigest': original,
        'generation': generation,
        'fence': lease['fence'],
        'status': status ?? 'stored',
        'secretUpdatedAt': sourceVersion,
        'lease': lease,
        'completed': completed,
      });
      return _reservation(lease);
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  /// Reserve before provider mint. Uncertain mint never releases the fence.
  Future<void> reserveWriter(
    CodexCredentialOwner owner,
    Map<String, Object?> body,
  ) async {
    requireCredentialCleanup(body);
    if (!credentialDigestValid(body['candidateDigest']) ||
        body['candidateDigest'] == body['originalDigest']) {
      throw credentialConflict;
    }
    final ref = bindingRef(owner.principal.repositoryId);
    await store.firestore.runTransaction<void>((tx) async {
      final data = (await tx.get(ref)).data();
      final lease = requireCredentialLease(data, owner, body);
      if (lease['writerStatus'] != 'none') throw credentialConflict;
      tx.update(ref, {
        'lease': {
          ...lease,
          'writerStatus': 'reserved',
          'candidateDigest': body['candidateDigest'],
          'workerCleanupDigest': body['workerCleanupDigest'],
        },
      });
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  Future<void> recordWriterIssued(
    CodexCredentialOwner owner,
    Map<String, Object?> body,
    DateTime expiresAt,
  ) async {
    final ref = bindingRef(owner.principal.repositoryId);
    await store.firestore.runTransaction<void>((tx) async {
      final data = (await tx.get(ref)).data();
      final lease = requireCredentialLease(data, owner, body);
      if (lease['writerStatus'] != 'reserved') throw credentialConflict;
      tx.update(ref, {
        'lease': {
          ...lease,
          'writerStatus': 'issued',
          'writerExpiresAt': Timestamp.fromDate(expiresAt),
        },
      });
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }

  Future<Map<String, Object?>> commit(
    CodexCredentialOwner owner,
    Map<String, Object?> body,
  ) async {
    requireCredentialCleanup(body);
    if (!credentialDigestValid(
      body['candidateDigest'],
      allowEmpty: owner.initialAuth && body['originalDigest'] == '',
    )) {
      throw credentialConflict;
    }
    final ref = bindingRef(owner.principal.repositoryId);
    return store.firestore.runTransaction<Map<String, Object?>>((tx) async {
      final data = (await tx.get(ref)).data();
      final context = (await tx.get(contextRef(owner))).data();
      final completed = context?[owner.receiptField];
      if (completed is Map &&
          owner.matchesCleanup(completed['owner'], body) &&
          completed['reservationId'] == body['reservationId'] &&
          completed['fence'] == body['fence'] &&
          completed['originalDigest'] == body['originalDigest'] &&
          completed['candidateDigest'] == body['candidateDigest'] &&
          completed['workerCleanupDigest'] == body['workerCleanupDigest']) {
        return _committed(completed.cast<String, Object?>());
      }
      final lease = requireCredentialLease(data, owner, body);
      final changed = body['candidateDigest'] != body['originalDigest'];
      final updatedAt = changed
          ? DateTime.tryParse(body['secretUpdatedAt'] as String? ?? '')
          : null;
      if (changed &&
          (lease['writerStatus'] != 'issued' ||
              lease['candidateDigest'] != body['candidateDigest'] ||
              lease['workerCleanupDigest'] != body['workerCleanupDigest'] ||
              body['writerTokenRevoked'] != true ||
              updatedAt?.isUtc != true)) {
        throw credentialConflict;
      }
      if (!changed && lease['writerStatus'] != 'none') throw credentialConflict;
      final generation = (data!['generation'] as int) + (changed ? 1 : 0);
      final timestamp = changed
          ? Timestamp.fromDate(updatedAt!)
          : data['secretUpdatedAt'];
      final receipt = <String, Object?>{
        ...lease,
        'candidateDigest': body['candidateDigest'],
        'workerCleanupDigest': body['workerCleanupDigest'],
        'generation': generation,
        'changed': changed,
        'secretUpdatedAt': timestamp,
      }..remove('writerExpiresAt');
      tx.update(ref, {
        'lease': null,
        'completed': receipt,
        'secretDigest': body['candidateDigest'],
        'secretUpdatedAt': timestamp,
        'generation': generation,
        'status':
            owner.usesVerifiedCredential ||
                (!changed && lease['previousStatus'] == 'valid')
            ? 'valid'
            : 'stored',
        'updatedAt': Timestamp.now(),
      });
      tx.set(contextRef(owner), {
        owner.receiptField: receipt,
        if (!owner.usesVerifiedCredential && body['candidateDigest'] != '') ...{
          'secretDigest': body['candidateDigest'],
          'secretUpdatedAt': timestamp,
          'credentialCommitCompleted': true,
          'writerTokenStatus': 'revoked',
          'writerTokenRevokedAt': Timestamp.now(),
        },
      }, options: const SetOptions.merge());
      if (body['candidateDigest'] != '') {
        tx.set(stateRef(owner), {
          'repository': owner.principal.repository,
          'repositoryId': owner.principal.repositoryId,
          'secretDigest': body['candidateDigest'],
          'secretUpdatedAt': timestamp,
          if (owner.usesVerifiedCredential) 'status': 'valid',
          'updatedAt': Timestamp.now(),
        }, options: const SetOptions.merge());
      }
      return _committed(receipt);
    }, transactionOptions: ReadWriteTransactionOptions(maxAttempts: 1));
  }
}

/// The execution record a lease is checked against.
Map<String, Object?>? _leaseContext(
  CodexCredentialOwner owner,
  Map<String, Object?>? existing,
  bool cleanupOnly,
) {
  return existing;
}

Map<String, Object?> _reservation(Map<String, Object?> lease) => {
  for (final key in ['reservationId', 'fence', 'originalDigest', 'generation'])
    key: lease[key],
  'secretUpdatedAt': _githubVersionWire(lease['originalUpdatedAt']),
};

Map<String, Object?> _committed(Map<String, Object?> receipt) => {
  'committed': true,
  'changed': receipt['changed'],
  'secretDigest': receipt['candidateDigest'],
  'generation': receipt['generation'],
  'secretUpdatedAt': _githubVersionWire(receipt['secretUpdatedAt']),
};

String? _githubVersionWire(Object? value) => value is Timestamp
    ? value.toDate().toUtc().toIso8601String().replaceFirst(
        RegExp(r'\.0+Z$'),
        'Z',
      )
    : null;
