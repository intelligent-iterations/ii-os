import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:ii_interactive_sessions/ii_interactive_sessions.dart';

import '../../api_error.dart';
import '../../interactive_session.dart';

final class FirestoreInteractiveSessionRepository
    implements InteractiveSessionRepository {
  FirestoreInteractiveSessionRepository(this.firestore);

  final Firestore firestore;

  CollectionReference<Map<String, Object?>> get _sessions =>
      firestore.collection(interactiveSessionCollection);

  @override
  Future<void> create({
    required InteractiveSessionRecord session,
    required Map<String, Object?> fleetRequest,
    required int maxConcurrent,
  }) async {
    if (maxConcurrent < 1 || maxConcurrent > 20) {
      throw const ApiError(
        409,
        'interactive_session_limit_invalid',
        'The workspace runner grant has an invalid concurrency limit.',
      );
    }
    final descriptor = session.descriptor;
    final sessionRef = _sessions.doc(descriptor.id);
    final jobRef = firestore.collection('jobRuns').doc(descriptor.jobId);
    final counterRef = firestore
        .collection(interactiveSessionCounterCollection)
        .doc(_counterId(descriptor.workspaceId, descriptor.runnerResourceId));
    await firestore.runTransaction<void>((transaction) async {
      final counter = await transaction.get(counterRef);
      final active = _activeSlots(counter.data(), descriptor.createdAt);
      if (active.length >= maxConcurrent) {
        throw const ApiError(
          409,
          'interactive_session_concurrency_reached',
          'This workspace runner grant has no free interactive session slot.',
        );
      }
      active.add({
        'sessionId': descriptor.id,
        'expiresAt': Timestamp.fromDate(descriptor.expiresAt),
      });
      transaction.create(sessionRef, _toData(session));
      transaction.create(jobRef, _queuedJob(session, fleetRequest));
      transaction.set(counterRef, {
        'workspaceId': descriptor.workspaceId,
        'runnerResourceId': descriptor.runnerResourceId,
        'active': active,
        'updatedAt': Timestamp.fromDate(descriptor.createdAt),
      });
    });
  }

  @override
  Future<InteractiveSessionRecord> get(
    String workspaceId,
    String sessionId,
  ) async {
    final snapshot = await _sessions.doc(sessionId).get();
    return _record(snapshot, workspaceId);
  }

  @override
  Future<List<InteractiveSessionRecord>> list(String workspaceId) async {
    final snapshot = await _sessions
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .orderBy('createdAt', descending: true)
        .limit(interactiveSessionListLimit)
        .get();
    return snapshot.docs
        .map((item) => _fromData(item.id, item.data()))
        .toList();
  }

  @override
  Future<InteractiveSessionRecord> putParticipant({
    required String workspaceId,
    required String sessionId,
    required InteractiveSessionParticipant participant,
  }) => _mutateParticipant(
    workspaceId: workspaceId,
    sessionId: sessionId,
    mutate: (record) {
      final existing = record.participant(participant.subject);
      final next = InteractiveSessionParticipant(
        subject: participant.subject,
        role: participant.role,
        generation: existing == null
            ? participant.generation
            : existing.generation + 1,
      );
      final participants = [
        ...record.participants.where(
          (item) => item.subject != participant.subject,
        ),
        next,
      ];
      if (participants.where((item) => !item.revoked).length > 8) {
        throw const ApiError(
          409,
          'interactive_participant_limit',
          'An interactive session supports at most eight participants.',
        );
      }
      if (participants.length > 32) {
        throw const ApiError(
          409,
          'interactive_participant_history_limit',
          'This session has reached its participant identity limit.',
        );
      }
      return _withParticipants(record, participants);
    },
  );

  @override
  Future<InteractiveSessionRecord> revokeParticipant({
    required String workspaceId,
    required String sessionId,
    required String subject,
  }) => _mutateParticipant(
    workspaceId: workspaceId,
    sessionId: sessionId,
    mutate: (record) {
      if (subject == record.descriptor.ownerSubject) {
        throw const ApiError(
          409,
          'interactive_owner_immutable',
          'The session owner cannot be revoked.',
        );
      }
      final existing = record.participant(subject);
      if (existing == null) _notFound();
      return _withParticipants(record, [
        for (final item in record.participants)
          if (item.subject == subject)
            InteractiveSessionParticipant(
              subject: item.subject,
              role: item.role,
              generation: item.generation + 1,
              revoked: true,
            )
          else
            item,
      ]);
    },
  );

  Future<InteractiveSessionRecord> _mutateParticipant({
    required String workspaceId,
    required String sessionId,
    required InteractiveSessionRecord Function(InteractiveSessionRecord) mutate,
  }) async {
    final ref = _sessions.doc(sessionId);
    return firestore.runTransaction<InteractiveSessionRecord>((
      transaction,
    ) async {
      final snapshot = await transaction.get(ref);
      final current = _record(snapshot, workspaceId);
      if (_terminal(current.descriptor.lifecycle)) {
        throw const ApiError(
          409,
          'interactive_session_terminal',
          'This interactive session has already ended.',
        );
      }
      final updated = mutate(current);
      transaction.update(ref, _toData(updated));
      return updated;
    });
  }

  @override
  Future<InteractiveSessionRecord> stop({
    required String workspaceId,
    required String sessionId,
    required DateTime now,
  }) async {
    final sessionRef = _sessions.doc(sessionId);
    return firestore.runTransaction<InteractiveSessionRecord>((
      transaction,
    ) async {
      final snapshot = await transaction.get(sessionRef);
      final current = _record(snapshot, workspaceId);
      if (_terminal(current.descriptor.lifecycle) ||
          current.descriptor.lifecycle == SessionLifecycle.ending) {
        return current;
      }
      final jobRef = firestore
          .collection('jobRuns')
          .doc(current.descriptor.jobId);
      final job = await transaction.get(jobRef);
      final jobData = job.data();
      final neverDispatched = job.exists && jobData?['status'] == 'queued';
      DocumentReference<Map<String, Object?>>? counterRef;
      List<Map<String, Object?>>? active;
      if (neverDispatched) {
        counterRef = firestore
            .collection(interactiveSessionCounterCollection)
            .doc(_counterId(workspaceId, current.descriptor.runnerResourceId));
        final counter = await transaction.get(counterRef);
        active = _activeSlots(counter.data(), now)
          ..removeWhere((item) => item['sessionId'] == sessionId);
      }
      final updated = InteractiveSessionRecord(
        descriptor: _copyDescriptor(
          current.descriptor,
          lifecycle: SessionLifecycle.ending,
          policyRevision: current.descriptor.policyRevision + 1,
        ),
        relayUri: current.relayUri,
        participants: current.participants,
        stoppedAt: now,
      );
      transaction.update(sessionRef, _toData(updated));
      if (counterRef != null && active != null) {
        transaction.set(counterRef, {
          'workspaceId': workspaceId,
          'runnerResourceId': current.descriptor.runnerResourceId,
          'active': active,
          'updatedAt': Timestamp.fromDate(now),
        });
      }
      if (neverDispatched) {
        transaction.update(jobRef, {
          'status': 'cancelled',
          'bridgeManaged': false,
          'cancelRequestedAt': Timestamp.fromDate(now),
          'completedAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
      } else if (job.exists) {
        transaction.update(jobRef, {
          'cancelRequestedAt': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
        });
      }
      return updated;
    });
  }
}

InteractiveSessionRecord _record(
  DocumentSnapshot<Map<String, Object?>> snapshot,
  String workspaceId,
) {
  final data = snapshot.data();
  if (!snapshot.exists || data == null || data['workspaceId'] != workspaceId) {
    _notFound();
  }
  return _fromData(snapshot.id, data);
}

InteractiveSessionRecord _fromData(String id, Map<String, Object?> data) {
  DateTime requiredTime(String key) {
    final value = data[key];
    if (value is! Timestamp) throw FormatException('$key is required.');
    return value.toDate().toUtc();
  }

  final descriptor = InteractiveSessionDescriptor(
    id: id,
    organizationId: data['organizationId']?.toString() ?? '',
    workspaceId: data['workspaceId']?.toString() ?? '',
    ownerSubject: data['ownerSubject']?.toString() ?? '',
    runnerResourceId: data['runnerResourceId']?.toString() ?? '',
    poolId: data['poolId']?.toString() ?? '',
    jobId: data['jobId']?.toString() ?? '',
    image: data['image']?.toString() ?? '',
    lifecycle: SessionLifecycle.values.byName(
      data['lifecycle']?.toString() ?? '',
    ),
    policyRevision: (data['policyRevision'] as num?)?.toInt() ?? 0,
    createdAt: requiredTime('createdAt'),
    expiresAt: requiredTime('expiresAt'),
    leaseId: data['leaseId']?.toString() ?? '',
    runtimeIdentity: data['runtimeIdentity']?.toString() ?? '',
  );
  final rawParticipants = data['participants'];
  final participants = rawParticipants is List<Object?>
      ? rawParticipants
            .whereType<Map<Object?, Object?>>()
            .map(
              (item) => InteractiveSessionParticipant.fromJson(
                item.cast<String, Object?>(),
              ),
            )
            .toList()
      : <InteractiveSessionParticipant>[];
  final relayUri = Uri.tryParse(data['relayUri']?.toString() ?? '');
  if (relayUri == null || descriptor.policyRevision < 1) {
    throw const FormatException('Invalid interactive session record.');
  }
  final stopped = data['stoppedAt'];
  return InteractiveSessionRecord(
    descriptor: descriptor,
    relayUri: relayUri,
    participants: participants,
    stoppedAt: stopped is Timestamp ? stopped.toDate().toUtc() : null,
  );
}

Map<String, Object?> _toData(InteractiveSessionRecord value) => {
  'organizationId': value.descriptor.organizationId,
  'workspaceId': value.descriptor.workspaceId,
  'ownerSubject': value.descriptor.ownerSubject,
  'runnerResourceId': value.descriptor.runnerResourceId,
  'poolId': value.descriptor.poolId,
  'jobId': value.descriptor.jobId,
  'image': value.descriptor.image,
  'lifecycle': value.descriptor.lifecycle.name,
  'policyRevision': value.descriptor.policyRevision,
  'createdAt': Timestamp.fromDate(value.descriptor.createdAt),
  'expiresAt': Timestamp.fromDate(value.descriptor.expiresAt),
  'relayUri': value.relayUri.toString(),
  'participants': value.participants.map((item) => item.toJson()).toList(),
  if (value.descriptor.leaseId.isNotEmpty) 'leaseId': value.descriptor.leaseId,
  if (value.descriptor.runtimeIdentity.isNotEmpty)
    'runtimeIdentity': value.descriptor.runtimeIdentity,
  if (value.stoppedAt != null)
    'stoppedAt': Timestamp.fromDate(value.stoppedAt!),
};

Never _notFound() => throw const ApiError(
  404,
  'interactive_session_not_found',
  'Interactive session not found.',
);

List<Map<String, Object?>> _activeSlots(
  Map<String, Object?>? data,
  DateTime now,
) {
  final raw = data?['active'];
  if (raw is! List<Object?>) return <Map<String, Object?>>[];
  return raw
      .whereType<Map<Object?, Object?>>()
      .map((item) => item.cast<String, Object?>())
      .where((item) {
        final expiry = item['expiresAt'];
        return expiry is Timestamp && expiry.toDate().isAfter(now);
      })
      .toList();
}

Map<String, Object?> _queuedJob(
  InteractiveSessionRecord session,
  Map<String, Object?> fleetRequest,
) {
  final value = session.descriptor;
  final now = Timestamp.fromDate(value.createdAt);
  return {
    'workspaceId': value.workspaceId,
    'jobId': value.jobId,
    'sessionId': value.id,
    'runnerResourceId': value.runnerResourceId,
    'sessionCounterId': _counterId(value.workspaceId, value.runnerResourceId),
    'kind': 'interactive-session',
    'status': 'queued',
    'fleetStatus': null,
    'fleetRequest': fleetRequest,
    'events': <Map<String, Object?>>[],
    'artifacts': <Map<String, Object?>>[],
    'createdBy': value.ownerSubject,
    'createdAt': now,
    'updatedAt': now,
    'expiresAt': Timestamp.fromDate(
      value.expiresAt.add(const Duration(days: 1)),
    ),
    'bridgeAttempts': 0,
    'bridgeManaged': true,
  };
}

InteractiveSessionRecord _withParticipants(
  InteractiveSessionRecord value,
  List<InteractiveSessionParticipant> participants,
) => InteractiveSessionRecord(
  descriptor: _copyDescriptor(
    value.descriptor,
    policyRevision: value.descriptor.policyRevision + 1,
  ),
  relayUri: value.relayUri,
  participants: participants,
  stoppedAt: value.stoppedAt,
);

InteractiveSessionDescriptor _copyDescriptor(
  InteractiveSessionDescriptor value, {
  SessionLifecycle? lifecycle,
  int? policyRevision,
}) => InteractiveSessionDescriptor(
  id: value.id,
  organizationId: value.organizationId,
  workspaceId: value.workspaceId,
  ownerSubject: value.ownerSubject,
  runnerResourceId: value.runnerResourceId,
  poolId: value.poolId,
  jobId: value.jobId,
  image: value.image,
  lifecycle: lifecycle ?? value.lifecycle,
  policyRevision: policyRevision ?? value.policyRevision,
  createdAt: value.createdAt,
  expiresAt: value.expiresAt,
  leaseId: value.leaseId,
  runtimeIdentity: value.runtimeIdentity,
);

String _counterId(String workspaceId, String runnerResourceId) => sha256
    .convert(utf8.encode('$workspaceId\u0000$runnerResourceId'))
    .toString();

bool _terminal(SessionLifecycle value) => const {
  SessionLifecycle.ending,
  SessionLifecycle.cleaning,
  SessionLifecycle.cleaned,
  SessionLifecycle.failed,
}.contains(value);
