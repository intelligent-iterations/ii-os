import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'auth_service.dart';
import 'fleet_reporting_key_codec.dart';
import 'organization_store.dart';

final class FleetReportingKeyPrincipal {
  const FleetReportingKeyPrincipal({
    required this.keyId,
    required this.organizationId,
  });

  final String keyId;
  final String organizationId;

  AuthenticatedUser get auditActor => AuthenticatedUser(
    uid: 'fleet-reporting-key:$keyId',
    email: '',
    emailVerified: false,
    displayName: 'Fleet reporter',
    isOwner: false,
  );
}

/// Organization-scoped credentials that let a tenant's own fleet report in.
///
/// Scoped to the organization rather than a workspace because the fleet belongs
/// to the tenant, not to one of its projects -- the same machines serve every
/// project inside it, and a per-workspace credential would imply otherwise.
final class FleetReportingKeyStore {
  FleetReportingKeyStore({
    required this.organizations,
    required this.codec,
    DateTime Function()? clock,
    this.rateLimitPerMinute = 120,
    this.uuid = const Uuid(),
  }) : _clock = clock ?? _utcNow;

  final OrganizationStore organizations;
  final FleetReportingKeyCodec codec;
  final DateTime Function() _clock;
  final int rateLimitPerMinute;
  final Uuid uuid;

  CollectionReference<Map<String, Object?>> get _keys =>
      organizations.firestore.collection('fleetReportingKeys');

  bool requestCarriesFleetKey(Request request) => _bearer(request) != null;

  Future<Map<String, Object?>> issue({
    required String organizationId,
    required String label,
    required String createdBy,
    int expiresInDays = 365,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty || normalizedLabel.length > 100) {
      throw const ApiError(
        400,
        'invalid_fleet_key_label',
        'Give the reporting credential a name of at most 100 characters.',
      );
    }
    if (expiresInDays < 1 || expiresInDays > 365) {
      throw const ApiError(
        400,
        'invalid_fleet_key_expiry',
        'Reporting credential expiry must be between 1 and 365 days.',
      );
    }
    await organizations.getOrganization(organizationId);
    final issued = codec.issue(uuid.v4());
    final now = _clock();
    final data = <String, Object?>{
      'organizationId': organizationId,
      'label': normalizedLabel,
      'keyDigest': issued.digest,
      'status': 'active',
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(Duration(days: expiresInDays))),
      'lastUsedAt': null,
      'revokedAt': null,
      'revokedBy': null,
      'rateWindowStartedAt': null,
      'rateWindowCount': 0,
    };
    await _keys.doc(issued.id).create(data);
    return {'key': issued.value, 'credential': _public(issued.id, data)};
  }

  Future<List<Map<String, Object?>>> list(String organizationId) async {
    final snapshots = await _keys
        .where('organizationId', WhereFilter.equal, organizationId)
        .get();
    final values = snapshots.docs
        .map((snapshot) => _public(snapshot.id, snapshot.data()))
        .toList();
    values.sort(
      (left, right) =>
          '${right['createdAt']}'.compareTo('${left['createdAt']}'),
    );
    return values;
  }

  Future<Map<String, Object?>> revoke({
    required String organizationId,
    required String keyId,
    required String revokedBy,
  }) async {
    final ref = _keys.doc(keyId);
    final now = _clock();
    late Map<String, Object?> updated;
    await organizations.firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          data['organizationId'] != organizationId) {
        throw const ApiError(
          404,
          'fleet_key_not_found',
          'Fleet reporting credential not found.',
        );
      }
      transaction.update(ref, {
        'status': 'revoked',
        'revokedAt': Timestamp.fromDate(now),
        'revokedBy': revokedBy,
        'updatedAt': Timestamp.fromDate(now),
      });
      updated = {
        ...data,
        'status': 'revoked',
        'revokedAt': Timestamp.fromDate(now),
        'revokedBy': revokedBy,
      };
    });
    return _public(keyId, updated);
  }

  Future<FleetReportingKeyPrincipal> authenticate(Request request) async {
    final value = _bearer(request);
    if (value == null) throw _invalidKey;
    return authenticateRaw(value);
  }

  Future<FleetReportingKeyPrincipal> authenticateRaw(String value) async {
    final parsed = codec.parse(value);
    if (parsed == null) throw _invalidKey;
    final ref = _keys.doc(parsed.id);
    final now = _clock();
    final principal = await organizations.firestore
        .runTransaction<FleetReportingKeyPrincipal>((transaction) async {
          final snapshot = await transaction.get(ref);
          final data = snapshot.data();
          if (!snapshot.exists || data == null) throw _invalidKey;
          final digest = data['keyDigest'];
          if (digest is! String || !codec.matches(digest, parsed.value)) {
            throw _invalidKey;
          }
          _requireUsable(data, now);
          final priorStart = data['rateWindowStartedAt'];
          final windowStart = priorStart is Timestamp
              ? priorStart.toDate().toUtc()
              : null;
          final reset =
              windowStart == null ||
              now.difference(windowStart) >= const Duration(minutes: 1);
          final count = reset
              ? 1
              : ((data['rateWindowCount'] as num?)?.toInt() ?? 0) + 1;
          if (count > rateLimitPerMinute) {
            throw const ApiError(
              429,
              'fleet_key_rate_limited',
              'Fleet reporting credential rate limit exceeded.',
            );
          }
          transaction.update(ref, {
            'lastUsedAt': Timestamp.fromDate(now),
            'rateWindowStartedAt': Timestamp.fromDate(
              reset ? now : windowStart,
            ),
            'rateWindowCount': count,
            'updatedAt': Timestamp.fromDate(now),
          });
          return FleetReportingKeyPrincipal(
            keyId: parsed.id,
            organizationId: data['organizationId'] as String? ?? '',
          );
        });
    if (principal.organizationId.isEmpty) throw _invalidKey;
    await organizations.getOrganization(principal.organizationId);
    return principal;
  }
}

const _invalidKey = ApiError(
  401,
  'invalid_fleet_key',
  'The fleet reporting credential is invalid or expired.',
);

String? _bearer(Request request) {
  final authorization = request.headers['authorization'] ?? '';
  if (!authorization.startsWith('Bearer ')) return null;
  final value = authorization.substring('Bearer '.length).trim();
  if (value.isEmpty) return null;
  return value.startsWith('${FleetReportingKeyCodec.prefix}.') ? value : null;
}

void _requireUsable(Map<String, Object?> data, DateTime now) {
  final expiresAt = data['expiresAt'];
  if (data['status'] != 'active' ||
      expiresAt is! Timestamp ||
      !expiresAt.toDate().toUtc().isAfter(now)) {
    throw _invalidKey;
  }
}

Map<String, Object?> _public(String id, Map<String, Object?> data) => {
  'id': id,
  'organizationId': data['organizationId'],
  'label': data['label'],
  'status': data['status'],
  'createdBy': data['createdBy'],
  'createdAt': _jsonDate(data['createdAt']),
  'updatedAt': _jsonDate(data['updatedAt']),
  'expiresAt': _jsonDate(data['expiresAt']),
  'lastUsedAt': _jsonDate(data['lastUsedAt']),
  'revokedAt': _jsonDate(data['revokedAt']),
};

String? _jsonDate(Object? value) =>
    value is Timestamp ? value.toDate().toUtc().toIso8601String() : null;

DateTime _utcNow() => DateTime.now().toUtc();
