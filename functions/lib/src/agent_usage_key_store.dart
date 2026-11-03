import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'agent_usage_key_codec.dart';
import 'api_error.dart';
import 'auth_service.dart';
import 'workspace_store.dart';

final class AgentUsageKeyPrincipal {
  const AgentUsageKeyPrincipal({
    required this.keyId,
    required this.workspaceId,
  });

  final String keyId;
  final String workspaceId;

  AuthenticatedUser get auditActor => AuthenticatedUser(
    uid: 'agent-usage-key:$keyId',
    email: '',
    emailVerified: false,
    displayName: 'Agent usage reporter',
    isOwner: false,
  );
}

final class AgentUsageKeyStore {
  AgentUsageKeyStore({
    required this.store,
    required this.codec,
    DateTime Function()? clock,
    this.rateLimitPerMinute = 600,
    this.uuid = const Uuid(),
  }) : _clock = clock ?? _utcNow;

  final WorkspaceStore store;
  final AgentUsageKeyCodec codec;
  final DateTime Function() _clock;
  final int rateLimitPerMinute;
  final Uuid uuid;

  CollectionReference<Map<String, Object?>> get _keys =>
      store.firestore.collection('agentUsageKeys');

  Future<Map<String, Object?>> issue({
    required String workspaceId,
    required String label,
    required String createdBy,
    int expiresInDays = 90,
  }) async {
    _requireConfigured();
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty || normalizedLabel.length > 100) {
      throw const ApiError(
        400,
        'invalid_agent_usage_key_label',
        'Give the reporting key a label of at most 100 characters.',
      );
    }
    if (expiresInDays < 1 || expiresInDays > 365) {
      throw const ApiError(
        400,
        'invalid_agent_usage_key_expiry',
        'Reporting key expiry must be between 1 and 365 days.',
      );
    }
    await store.getWorkspace(workspaceId);
    final issued = codec.issue(uuid.v4());
    final now = _clock();
    final data = <String, Object?>{
      'workspaceId': workspaceId,
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

  Future<List<Map<String, Object?>>> list(String workspaceId) async {
    final snapshots = await _keys
        .where('workspaceId', WhereFilter.equal, workspaceId)
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
    required String workspaceId,
    required String keyId,
    required String revokedBy,
  }) async {
    final ref = _keys.doc(keyId);
    final now = _clock();
    await store.firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          data['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'agent_usage_key_not_found',
          'Agent usage reporting key not found.',
        );
      }
      if (data['status'] == 'revoked') return;
      transaction.update(ref, {
        'status': 'revoked',
        'revokedAt': Timestamp.fromDate(now),
        'revokedBy': revokedBy,
        'updatedAt': Timestamp.fromDate(now),
      });
    });
    final snapshot = await ref.get();
    return _public(keyId, snapshot.data()!);
  }

  bool requestCarriesUsageKey(Request request) {
    final value = _bearer(request);
    return value?.startsWith('${AgentUsageKeyCodec.prefix}.') == true;
  }

  Future<AgentUsageKeyPrincipal> authenticate(Request request) async {
    final value = _bearer(request);
    if (value == null) throw _invalidKey;
    return authenticateRaw(value);
  }

  Future<AgentUsageKeyPrincipal> authenticateRaw(String value) async {
    _requireConfigured();
    final parsed = codec.parse(value);
    if (parsed == null) throw _invalidKey;
    final ref = _keys.doc(parsed.id);
    final now = _clock();
    final principal = await store.firestore
        .runTransaction<AgentUsageKeyPrincipal>((transaction) async {
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
              'agent_usage_key_rate_limited',
              'Agent usage reporting key rate limit exceeded.',
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
          return AgentUsageKeyPrincipal(
            keyId: parsed.id,
            workspaceId: data['workspaceId'] as String? ?? '',
          );
        });
    if (principal.workspaceId.isEmpty) throw _invalidKey;
    await store.getWorkspace(principal.workspaceId);
    return principal;
  }

  void _requireConfigured() {
    if (!codec.isConfigured) {
      throw const ApiError(
        503,
        'agent_usage_key_signing_not_configured',
        'Agent usage reporting keys are not configured for this environment.',
      );
    }
  }
}

const _invalidKey = ApiError(
  401,
  'invalid_agent_usage_key',
  'The agent usage reporting key is invalid or expired.',
);

String? _bearer(Request request) {
  final authorization = request.headers['authorization'] ?? '';
  if (!authorization.startsWith('Bearer ')) return null;
  final value = authorization.substring('Bearer '.length).trim();
  return value.isEmpty ? null : value;
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
  'workspaceId': data['workspaceId'],
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
