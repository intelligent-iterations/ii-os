import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'auth_service.dart';
import 'workflow_token_codec.dart';
import 'workspace_store.dart';

final class WorkflowTokenScope {
  const WorkflowTokenScope({
    required this.workspaceId,
    this.organizationId = '',
    required this.installationId,
    required this.repository,
    required this.repositoryId,
    required this.environment,
  });

  final String workspaceId;
  final String organizationId;
  final int installationId;
  final String repository;
  final int repositoryId;
  final String environment;
}

final class WorkflowTokenPrincipal {
  const WorkflowTokenPrincipal({required this.tokenId, required this.scope});

  final String tokenId;
  final WorkflowTokenScope scope;

  AuthenticatedUser get auditActor => AuthenticatedUser(
    uid: 'workflow-token:$tokenId',
    email: '',
    emailVerified: false,
    displayName: 'Workflow credential',
    isOwner: false,
  );
}

final class WorkflowTokenService {
  WorkflowTokenService({
    required this.store,
    required this.codec,
    DateTime Function()? clock,
    this._uuid = const Uuid(),
    this.rotationOverlap = const Duration(hours: 24),
    this.rateLimitPerMinute = 120,
  }) : _clock = clock ?? _utcNow;

  final WorkspaceStore store;
  final WorkflowTokenCodec codec;
  final DateTime Function() _clock;
  final Uuid _uuid;
  final Duration rotationOverlap;
  final int rateLimitPerMinute;

  CollectionReference<Map<String, Object?>> get _tokens =>
      store.firestore.collection('workflowTokens');

  Future<Map<String, Object?>> issue({
    required WorkflowTokenScope scope,
    required String createdBy,
    int expiresInDays = 90,
  }) async {
    _requireConfigured();
    _validateScope(scope);
    _validateExpiry(expiresInDays);
    final issued = codec.issue(_uuid.v4());
    final now = _clock();
    final data = _tokenData(
      issued: issued,
      scope: scope,
      createdBy: createdBy,
      now: now,
      expiresAt: now.add(Duration(days: expiresInDays)),
    );
    await _tokens.doc(issued.id).create(data);
    return {'token': issued.value, 'credential': _public(issued.id, data)};
  }

  Future<List<Map<String, Object?>>> list(String workspaceId) async {
    final snapshots = await _tokens
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .get();
    final result = snapshots.docs
        .map((snapshot) => _public(snapshot.id, snapshot.data()))
        .toList();
    result.sort(
      (left, right) =>
          '${right['createdAt']}'.compareTo('${left['createdAt']}'),
    );
    return result;
  }

  Future<Map<String, Object?>> rotate({
    required String workspaceId,
    required String tokenId,
    required String createdBy,
    int expiresInDays = 90,
  }) async {
    _requireConfigured();
    _validateExpiry(expiresInDays);
    final replacement = codec.issue(_uuid.v4());
    final now = _clock();
    final oldRef = _tokens.doc(tokenId);
    final newRef = _tokens.doc(replacement.id);
    late Map<String, Object?> replacementData;
    await store.firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(oldRef);
      final old = snapshot.data();
      if (!snapshot.exists ||
          old == null ||
          old['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'workflow_token_not_found',
          'Workflow credential not found.',
        );
      }
      if (old['status'] != 'active') {
        throw const ApiError(
          409,
          'workflow_token_not_active',
          'Only an active workflow credential can be rotated.',
        );
      }
      final scope = _scopeFromData(old);
      replacementData = _tokenData(
        issued: replacement,
        scope: scope,
        createdBy: createdBy,
        now: now,
        expiresAt: now.add(Duration(days: expiresInDays)),
        replacesTokenId: tokenId,
      );
      final oldExpiry = _date(old['expiresAt']);
      final overlapEnd = now.add(rotationOverlap);
      final validUntil = oldExpiry.isBefore(overlapEnd)
          ? oldExpiry
          : overlapEnd;
      transaction.set(newRef, replacementData);
      transaction.update(oldRef, {
        'status': 'overlap',
        'validUntil': Timestamp.fromDate(validUntil),
        'replacedByTokenId': replacement.id,
        'updatedAt': Timestamp.fromDate(now),
      });
    });
    return {
      'token': replacement.value,
      'credential': _public(replacement.id, replacementData),
    };
  }

  Future<Map<String, Object?>> revoke({
    required String workspaceId,
    required String tokenId,
    required String revokedBy,
  }) async {
    final ref = _tokens.doc(tokenId);
    final now = _clock();
    await store.firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          data['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'workflow_token_not_found',
          'Workflow credential not found.',
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
    return _public(tokenId, snapshot.data()!);
  }

  Future<WorkflowTokenPrincipal> authenticate(Request request) async {
    final authorization = request.headers['authorization'] ?? '';
    if (!authorization.startsWith('Bearer ')) throw _invalidToken;
    return authenticateRaw(authorization.substring('Bearer '.length).trim());
  }

  Future<WorkflowTokenPrincipal> authenticateRaw(
    String value, {
    int maxAttempts = 5,
  }) async {
    _requireConfigured();
    final parsed = codec.parse(value);
    if (parsed == null) throw _invalidToken;
    final ref = _tokens.doc(parsed.id);
    final now = _clock();
    final principal = await store.firestore
        .runTransaction<WorkflowTokenPrincipal>(
          (transaction) async {
            final snapshot = await transaction.get(ref);
            final data = snapshot.data();
            if (!snapshot.exists || data == null) throw _invalidToken;
            final expected = data['tokenDigest'];
            if (expected is! String || !codec.matches(expected, parsed.value)) {
              throw _invalidToken;
            }
            _requireUsable(data, now);
            final windowStartedAt = data['rateWindowStartedAt'];
            final windowStart = windowStartedAt is Timestamp
                ? windowStartedAt.toDate().toUtc()
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
                'workflow_token_rate_limited',
                'Workflow credential rate limit exceeded.',
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
            return WorkflowTokenPrincipal(
              tokenId: parsed.id,
              scope: _scopeFromData(data),
            );
          },
          transactionOptions: ReadWriteTransactionOptions(
            maxAttempts: maxAttempts,
          ),
        );
    final workspace = await store.getWorkspace(principal.scope.workspaceId);
    final recordedOrganizationId = principal.scope.organizationId;
    if ((recordedOrganizationId.isNotEmpty &&
            recordedOrganizationId != workspace.organizationId) ||
        workspace.githubInstallationId != principal.scope.installationId ||
        workspace.environment != principal.scope.environment ||
        !workspace.containsRepository(principal.scope.repository)) {
      throw _invalidToken;
    }
    return WorkflowTokenPrincipal(
      tokenId: principal.tokenId,
      scope: WorkflowTokenScope(
        workspaceId: principal.scope.workspaceId,
        organizationId: recordedOrganizationId.isEmpty
            ? workspace.organizationId
            : recordedOrganizationId,
        installationId: principal.scope.installationId,
        repository: principal.scope.repository,
        repositoryId: principal.scope.repositoryId,
        environment: principal.scope.environment,
      ),
    );
  }

  Map<String, Object?> _tokenData({
    required IssuedWorkflowToken issued,
    required WorkflowTokenScope scope,
    required String createdBy,
    required DateTime now,
    required DateTime expiresAt,
    String? replacesTokenId,
  }) => {
    'workspaceId': scope.workspaceId,
    if (scope.organizationId.isNotEmpty) 'organizationId': scope.organizationId,
    'installationId': scope.installationId,
    'repository': scope.repository,
    'repositoryId': scope.repositoryId,
    'environment': scope.environment,
    'tokenDigest': issued.digest,
    'status': 'active',
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(now),
    'updatedAt': Timestamp.fromDate(now),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'lastUsedAt': null,
    'validUntil': null,
    'revokedAt': null,
    'rateWindowStartedAt': null,
    'rateWindowCount': 0,
    'replacesTokenId': ?replacesTokenId,
  };

  void _requireConfigured() {
    if (!codec.isConfigured) {
      throw const ApiError(
        503,
        'workflow_token_signing_not_configured',
        'Workflow credentials are not configured for this environment.',
      );
    }
  }
}

const _invalidToken = ApiError(
  401,
  'invalid_workflow_token',
  'The workflow credential is invalid or expired.',
);

void _validateScope(WorkflowTokenScope scope) {
  if (scope.workspaceId.isEmpty ||
      (scope.organizationId.isNotEmpty &&
          !RegExp(
            r'^[A-Za-z0-9_.:-]{1,200}$',
          ).hasMatch(scope.organizationId)) ||
      scope.installationId <= 0 ||
      scope.repositoryId <= 0 ||
      !RegExp(
        r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
      ).hasMatch(scope.repository) ||
      (scope.environment != 'dev' && scope.environment != 'prod')) {
    throw const ApiError(
      400,
      'invalid_workflow_token_scope',
      'Workflow credential scope is invalid.',
    );
  }
}

void _validateExpiry(int days) {
  if (days < 1 || days > 365) {
    throw const ApiError(
      400,
      'invalid_workflow_token_expiry',
      'Workflow credential expiry must be between 1 and 365 days.',
    );
  }
}

void _requireUsable(Map<String, Object?> data, DateTime now) {
  final expiresAt = data['expiresAt'];
  if (expiresAt is! Timestamp || !expiresAt.toDate().toUtc().isAfter(now)) {
    throw _invalidToken;
  }
  switch (data['status']) {
    case 'active':
      return;
    case 'overlap':
      final validUntil = data['validUntil'];
      if (validUntil is Timestamp && validUntil.toDate().toUtc().isAfter(now)) {
        return;
      }
  }
  throw _invalidToken;
}

WorkflowTokenScope _scopeFromData(Map<String, Object?> data) {
  final scope = WorkflowTokenScope(
    workspaceId: data['workspaceId'] as String? ?? '',
    organizationId: data['organizationId'] as String? ?? '',
    installationId: (data['installationId'] as num?)?.toInt() ?? 0,
    repository: data['repository'] as String? ?? '',
    repositoryId: (data['repositoryId'] as num?)?.toInt() ?? 0,
    environment: data['environment'] as String? ?? '',
  );
  _validateScope(scope);
  return scope;
}

Map<String, Object?> _public(String id, Map<String, Object?> data) => {
  'id': id,
  'workspaceId': data['workspaceId'],
  if (data['organizationId'] != null) 'organizationId': data['organizationId'],
  'installationId': data['installationId'],
  'repository': data['repository'],
  'repositoryId': data['repositoryId'],
  'environment': data['environment'],
  'status': data['status'],
  'createdBy': data['createdBy'],
  'createdAt': _jsonDate(data['createdAt']),
  'updatedAt': _jsonDate(data['updatedAt']),
  'expiresAt': _jsonDate(data['expiresAt']),
  'lastUsedAt': _jsonDate(data['lastUsedAt']),
  'validUntil': _jsonDate(data['validUntil']),
  'revokedAt': _jsonDate(data['revokedAt']),
  if (data['replacesTokenId'] != null)
    'replacesTokenId': data['replacesTokenId'],
  if (data['replacedByTokenId'] != null)
    'replacedByTokenId': data['replacedByTokenId'],
};

DateTime _date(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  throw const ApiError(
    500,
    'workflow_token_record_invalid',
    'Workflow credential record is invalid.',
  );
}

String? _jsonDate(Object? value) =>
    value is Timestamp ? value.toDate().toUtc().toIso8601String() : null;

DateTime _utcNow() => DateTime.now().toUtc();
