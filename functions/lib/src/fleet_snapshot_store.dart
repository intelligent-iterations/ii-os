import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'fleet_snapshot.dart';
import 'organization_store.dart';

/// The most recent fleet report for one organization.
///
/// One document per organization, overwritten in place. A fleet report is
/// operational metadata about the tenant's own execution substrate, and the
/// control plane keeps only the current picture: history belongs to the fleet
/// that owns it, and an append-only copy here would grow without a retention
/// owner while telling nobody anything the source cannot already answer.
final class FleetSnapshotStore {
  FleetSnapshotStore({required this.organizations, DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  final OrganizationStore organizations;
  final DateTime Function() _clock;

  CollectionReference<Map<String, Object?>> get _snapshots =>
      organizations.firestore.collection('fleetSnapshots');

  Future<Map<String, Object?>> record({
    required String organizationId,
    required FleetSnapshot snapshot,
    required String reporterId,
  }) async {
    final now = _clock();
    final data = <String, Object?>{
      'organizationId': organizationId,
      'reporterId': reporterId,
      'receivedAt': Timestamp.fromDate(now),
      'observedAt': Timestamp.fromDate(snapshot.observedAt),
      'controlPlaneId': snapshot.controlPlaneId,
      'hosts': snapshot.hosts.map((host) => host.toJson()).toList(),
      'activity': snapshot.activity.map((entry) => entry.toJson()).toList(),
    };
    await _snapshots.doc(organizationId).set(data);
    return {
      'machineCount': snapshot.hosts.length,
      'activityCount': snapshot.activity.length,
      'receivedAt': now.toIso8601String(),
    };
  }

  /// Returns null when this organization has never had a fleet report, which
  /// is the ordinary state for a tenant that has not connected one.
  Future<Map<String, Object?>?> read(String organizationId) async {
    final snapshot = await _snapshots.doc(organizationId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final observedAt = _dateOf(data['observedAt']);
    final receivedAt = _dateOf(data['receivedAt']);
    final reference = observedAt ?? receivedAt;
    return {
      'observedAt': observedAt?.toIso8601String(),
      'receivedAt': receivedAt?.toIso8601String(),
      'controlPlaneId': data['controlPlaneId'],
      // Computed here rather than in the browser: a client clock that is wrong
      // would otherwise render a live fleet as dead, or a dead one as live.
      'stale':
          reference == null ||
          _clock().difference(reference) > FleetBounds.freshness,
      'hosts': data['hosts'] ?? const <Object?>[],
      'activity': data['activity'] ?? const <Object?>[],
    };
  }
}

DateTime? _dateOf(Object? value) =>
    value is Timestamp ? value.toDate().toUtc() : null;

DateTime _utcNow() => DateTime.now().toUtc();
