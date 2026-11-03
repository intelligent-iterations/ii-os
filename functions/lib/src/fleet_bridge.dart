import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'fleet_client.dart';
import 'session_relay_control.dart';

abstract interface class FleetBridgeTicker {
  Future<FleetBridgeTick> tick();
}

final class FleetBridge implements FleetBridgeTicker {
  FleetBridge({
    required this.firestore,
    required this.fleet,
    required this.workerId,
    this.relay,
    this.claimTtl = const Duration(minutes: 2),
    this.maxDispatchAttempts = 5,
  }) {
    if (maxDispatchAttempts < 1 || maxDispatchAttempts > 20) {
      throw ArgumentError.value(maxDispatchAttempts, 'maxDispatchAttempts');
    }
  }

  final Firestore firestore;
  final FleetClient fleet;
  final String workerId;
  final SessionRelayControl? relay;
  final Duration claimTtl;
  final int maxDispatchAttempts;

  CollectionReference<Map<String, Object?>> get _jobs =>
      firestore.collection('jobRuns');

  @override
  Future<FleetBridgeTick> tick() async {
    final snapshot = await _jobs
        .where('bridgeManaged', WhereFilter.equal, true)
        .limit(100)
        .get();
    var changed = await _recoverExpiredClaims(snapshot);
    final claimed = await _claimQueuedJob(snapshot);
    if (claimed != null) {
      await _submit(claimed);
      changed++;
    }
    final reconciled = await _reconcileActiveJobs(snapshot);
    changed += reconciled.changed;
    return FleetBridgeTick(changed: changed, pending: reconciled.pending);
  }

  Future<int> _recoverExpiredClaims(
    QuerySnapshot<Map<String, Object?>> snapshot,
  ) async {
    final now = DateTime.now().toUtc();
    var recovered = 0;
    for (final doc in snapshot.docs) {
      if (doc.data()['status'] != 'dispatching') continue;
      final expiresAt = doc.data()['claimExpiresAt'];
      if (expiresAt is Timestamp && expiresAt.toDate().isAfter(now)) continue;
      await doc.ref.update({
        'status': 'queued',
        'claimOwner': null,
        'claimExpiresAt': null,
        'updatedAt': Timestamp.now(),
      });
      recovered++;
    }
    return recovered;
  }

  Future<_ClaimedJob?> _claimQueuedJob(
    QuerySnapshot<Map<String, Object?>> snapshot,
  ) async {
    final now = DateTime.now().toUtc();
    final selected = snapshot.docs.where((candidate) {
      final data = candidate.data();
      final nextAttempt = data['nextAttemptAt'];
      return data['status'] == 'queued' &&
          (nextAttempt is! Timestamp || !nextAttempt.toDate().isAfter(now));
    }).firstOrNull;
    if (selected == null) return null;
    return firestore.runTransaction<_ClaimedJob?>((transaction) async {
      final current = await transaction.get(selected.ref);
      final data = current.data();
      if (!current.exists || data == null || data['status'] != 'queued') {
        return null;
      }
      final currentNextAttempt = data['nextAttemptAt'];
      if (currentNextAttempt is Timestamp &&
          currentNextAttempt.toDate().isAfter(DateTime.now().toUtc())) {
        return null;
      }
      transaction.update(current.ref, {
        'status': 'dispatching',
        'claimOwner': workerId,
        'claimExpiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().add(claimTtl),
        ),
        'updatedAt': Timestamp.now(),
      });
      return _ClaimedJob(current.ref, data);
    });
  }

  Future<void> _submit(_ClaimedJob claimed) async {
    final data = claimed.data;
    final rawRequest = data['fleetRequest'];
    if (rawRequest is! Map) {
      await _failDispatch(
        claimed,
        'Queued job has no Fleet request.',
        retry: false,
      );
      return;
    }
    final request = rawRequest.cast<String, Object?>();
    try {
      final result = await fleet.submitRequest(
        request,
        requestId: _requestIdFrom(request),
      );
      await claimed.ref.update({
        'status': result['status'] ?? 'requested',
        'fleetStatus': result['status'] ?? 'requested',
        'leaseId': result['leaseId'],
        'claimOwner': null,
        'claimExpiresAt': null,
        'bridgeError': null,
        'bridgeAttempts': ((data['bridgeAttempts'] as num?)?.toInt() ?? 0) + 1,
        'updatedAt': Timestamp.now(),
      });
    } on Object catch (error) {
      await _failDispatch(claimed, _safeError(error), retry: true);
    }
  }

  Future<void> _failDispatch(
    _ClaimedJob claimed,
    String detail, {
    required bool retry,
  }) async {
    final attempts =
        ((claimed.data['bridgeAttempts'] as num?)?.toInt() ?? 0) + 1;
    final willRetry = retry && attempts < maxDispatchAttempts;
    final retryDelay = Duration(seconds: (attempts * 10).clamp(10, 300));
    await claimed.ref.update({
      'status': willRetry ? 'queued' : 'failed',
      'claimOwner': null,
      'claimExpiresAt': null,
      'bridgeAttempts': attempts,
      'bridgeError': detail,
      'nextAttemptAt': willRetry
          ? Timestamp.fromDate(DateTime.now().toUtc().add(retryDelay))
          : null,
      if (!willRetry) 'bridgeManaged': false,
      if (!willRetry) 'completedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
    if (!willRetry) await _failInteractiveSession(claimed.data);
  }

  Future<void> _failInteractiveSession(Map<String, Object?> job) async {
    final sessionId = job['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return;
    final relayControl = relay;
    if (relayControl == null) {
      throw StateError('Interactive Fleet dispatch requires relay control.');
    }
    await firestore.collection('interactiveSessions').doc(sessionId).update({
      'lifecycle': 'failed',
      'updatedAt': Timestamp.now(),
    });
    await relayControl.end(sessionId);
    await _releaseInteractiveSlot(job, sessionId);
  }

  Future<FleetBridgeTick> _reconcileActiveJobs(
    QuerySnapshot<Map<String, Object?>> snapshot,
  ) async {
    var updated = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      if (_localTerminalStates.contains(status) ||
          status == 'queued' ||
          status == 'dispatching') {
        continue;
      }
      final workspaceId = data['workspaceId'] as String? ?? '';
      final jobId = data['jobId'] as String? ?? doc.id;
      try {
        if (data['cancelRequestedAt'] != null &&
            data['cancelDispatchedAt'] == null) {
          final cancelled = await fleet.cancelPending(jobId);
          await doc.ref.update({
            'cancelDispatchedAt': Timestamp.now(),
            'cancelledPendingLeases': cancelled,
            'updatedAt': Timestamp.now(),
          });
        }
        final detail = await fleet.jobDetail(workspaceId, jobId);
        final update = _fleetUpdate(detail);
        await _syncInteractiveSession(data, detail, update);
        await doc.ref.update(update);
        updated++;
      } on ApiError catch (error) {
        if (error.code == 'fleet_job_not_found') continue;
        await doc.ref.update({
          'bridgeError': _safeError(error),
          'updatedAt': Timestamp.now(),
        });
      }
    }
    return FleetBridgeTick(changed: updated, pending: snapshot.docs.isNotEmpty);
  }

  Future<void> _syncInteractiveSession(
    Map<String, Object?> job,
    Map<String, Object?> detail,
    Map<String, Object?> update,
  ) async {
    final sessionId = job['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return;
    final status = update['status']?.toString() ?? '';
    final lifecycle = switch (status) {
      'requested' || 'assigned' || 'accepted' => 'placing',
      'booting' || 'runtime_ready' || 'runner_online' => 'starting',
      'running' => 'active',
      'succeeded' => 'cleaned',
      'failed' || 'cancelled' => 'failed',
      _ => null,
    };
    if (lifecycle == null) return;
    final terminal = _localTerminalStates.contains(status);
    final relayControl = relay;
    if (terminal && relayControl == null) {
      throw StateError(
        'Interactive Fleet reconciliation requires relay control.',
      );
    }
    await firestore.collection('interactiveSessions').doc(sessionId).update({
      'lifecycle': lifecycle,
      if (detail['leaseId'] is String) 'leaseId': detail['leaseId'],
      if (detail['runtimeName'] is String)
        'runtimeIdentity': detail['runtimeName'],
      'updatedAt': Timestamp.now(),
    });
    if (terminal) {
      await relayControl!.end(sessionId);
      await _releaseInteractiveSlot(job, sessionId);
    }
  }

  Future<void> _releaseInteractiveSlot(
    Map<String, Object?> job,
    String sessionId,
  ) async {
    final counterId = job['sessionCounterId'];
    if (counterId is! String || counterId.isEmpty) return;
    final ref = firestore
        .collection('interactiveSessionCounters')
        .doc(counterId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return;
      final raw = data['active'];
      final active = raw is List<Object?>
          ? raw
                .whereType<Map<Object?, Object?>>()
                .map((item) => item.cast<String, Object?>())
                .where((item) => item['sessionId'] != sessionId)
                .toList()
          : <Map<String, Object?>>[];
      transaction.update(ref, {'active': active, 'updatedAt': Timestamp.now()});
    });
  }
}

final class FleetBridgeTick {
  const FleetBridgeTick({required this.changed, required this.pending});

  final int changed;
  final bool pending;
}

final class _ClaimedJob {
  const _ClaimedJob(this.ref, this.data);

  final DocumentReference<Map<String, Object?>> ref;
  final Map<String, Object?> data;
}

Map<String, Object?> _fleetUpdate(Map<String, Object?> detail) {
  final fleetStatus = detail['status'] as String? ?? 'requested';
  final events = detail['events'] is List<Object?>
      ? (detail['events']! as List<Object?>)
            .whereType<Map<String, Object?>>()
            .toList()
      : <Map<String, Object?>>[];
  final artifacts = <Map<String, Object?>>[];
  var workloadFailed = false;
  for (final event in events) {
    if (event['kind'] == 'finished' && event['jobFailed'] == true) {
      workloadFailed = true;
    }
    final rawArtifacts = event['artifacts'];
    if (rawArtifacts is List<Object?>) {
      artifacts.addAll(rawArtifacts.whereType<Map<String, Object?>>());
    }
  }
  final status = switch (fleetStatus) {
    'cleaned' when workloadFailed => 'failed',
    'cleaned' => 'succeeded',
    'failed' ||
    'cleanup_failed' ||
    'quarantined' ||
    'host_lost' ||
    'lease_expired' ||
    'rejected' => 'failed',
    _ => fleetStatus,
  };
  return {
    'status': status,
    'fleetStatus': fleetStatus,
    'leaseId': detail['leaseId'],
    'hostId': detail['hostId'],
    'runtimeName': detail['runtimeName'],
    'failReason': detail['failReason'],
    'failDetail': detail['failDetail'],
    'events': events.take(100).toList(),
    'artifacts': artifacts,
    'bridgeError': null,
    'updatedAt': Timestamp.now(),
    if (_localTerminalStates.contains(status)) 'completedAt': Timestamp.now(),
    if (_localTerminalStates.contains(status)) 'bridgeManaged': false,
  };
}

String _requestIdFrom(Map<String, Object?> request) {
  final tags = request['tags'];
  if (tags is Map && tags['request_id'] is String) {
    return tags['request_id'] as String;
  }
  return 'bridge-${DateTime.now().microsecondsSinceEpoch}';
}

String _safeError(Object error) {
  final value = error is ApiError
      ? error.message
      : error.runtimeType.toString();
  return value.substring(0, value.length.clamp(0, 300));
}

const _localTerminalStates = {'succeeded', 'failed', 'cancelled'};
