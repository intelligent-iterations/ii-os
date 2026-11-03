import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'auth_service.dart';
import 'domain.dart';
import 'workspace_store.dart';

/// Identity colours a production line may carry.
///
/// The stored value is a token key, never a hex string. A hex in the database
/// freezes a design decision into user data: a rebrand or a dark-mode pass
/// would need a migration, and an arbitrary hex cannot be contrast-verified.
/// The key resolves to a swatch in `ii_os_design_system`, where
/// `contrast_test.dart` proves it clears its WCAG duty.
const productionLineColorTokens = <String>{
  'violet',
  'plum',
  'indigo',
  'cyan',
  'slate',
  'moss',
};

/// Identity glyphs a production line may carry.
///
/// Closed set for the same reason as the colours, plus one of its own: a free
/// text field for an icon name renders a missing glyph the moment the icon
/// package changes. The client maps these keys to Lucide icons.
const productionLineIconTokens = <String>{
  'factory',
  'rocket',
  'beaker',
  'wrench',
  'boxes',
  'shield',
  'smartphone',
  'globe',
  'database',
  'creditCard',
  'sparkles',
  'terminal',
};

/// The most lines one workspace may hold.
///
/// Lines are read in full on every session, sorted in memory, and rendered as
/// sidebar entries. All three stop being reasonable well before this bound.
const productionLineLimit = 50;

const _maxNameLength = 80;

/// A durable binding of one repository, one GitHub Project board, and one
/// agent permission scope, carrying its own team-wide identity.
final class ProductionLine {
  const ProductionLine({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.repository,
    required this.projectId,
    required this.permissionProfileId,
    required this.permissionRef,
    required this.colorToken,
    required this.iconToken,
  });

  factory ProductionLine.fromData(String id, Map<String, Object?> data) =>
      ProductionLine(
        id: id,
        workspaceId: data['workspaceId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        repository: data['repository'] as String? ?? '',
        projectId: data['projectId'] as String? ?? '',
        permissionProfileId: data['permissionProfileId'] as String? ?? '',
        permissionRef: data['permissionRef'] as String? ?? 'dev',
        colorToken: data['colorToken'] as String? ?? 'slate',
        iconToken: data['iconToken'] as String? ?? 'factory',
      );

  final String id;
  final String workspaceId;
  final String name;
  final String repository;
  final String projectId;
  final String permissionProfileId;
  final String permissionRef;
  final String colorToken;
  final String iconToken;

  Map<String, Object?> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'name': name,
    'repository': repository,
    'projectId': projectId,
    'permissionProfileId': permissionProfileId,
    'permissionRef': permissionRef,
    'colorToken': colorToken,
    'iconToken': iconToken,
  };
}

/// Owns `workspaces/{id}/productionLines` and its membership mirror.
///
/// Membership lives in a sibling workspace subcollection keyed
/// `{lineId}_{uid}` rather than nested under each line, so "which lines can
/// this user see" is one single-field equality query instead of a fan-out or a
/// collection-group index.
final class ProductionLineStore {
  ProductionLineStore(this.store);

  final WorkspaceStore store;
  final Uuid _uuid = const Uuid();

  /// Lines this membership may see.
  ///
  /// Owner and Admin see every line. Hiding a line from them would be theater:
  /// they hold `agent.permissions.manage` and can grant themselves access in
  /// two clicks, so the honest control is the audit trail on the grant, not a
  /// filter they can lift. Everyone else sees only lines they belong to.
  Future<List<ProductionLine>> listVisible(
    Membership membership,
    String workspaceId,
  ) async {
    final lines = await _linesRef(workspaceId).get();
    final all = lines.docs
        .map((doc) => ProductionLine.fromData(doc.id, doc.data()))
        .toList();
    if (!_seesEveryLine(membership)) {
      final visible = await _memberLineIds(workspaceId, membership.uid);
      all.removeWhere((line) => !visible.contains(line.id));
    }
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  /// One line, after proving this membership may see it.
  ///
  /// Fails closed with the same 404 a nonexistent line returns, so an
  /// unauthorized caller cannot probe for which line ids exist.
  Future<ProductionLine> requireVisible(
    Membership membership,
    String workspaceId,
    String lineId,
  ) async {
    final snapshot = await _lineRef(workspaceId, lineId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) throw _notFound;
    if (!_seesEveryLine(membership)) {
      final member = await _memberRef(
        workspaceId,
        lineId,
        membership.uid,
      ).get();
      if (!member.exists) throw _notFound;
    }
    return ProductionLine.fromData(lineId, data);
  }

  Future<ProductionLine> create(
    AuthenticatedUser actor,
    String workspaceId,
    Map<String, Object?> body,
  ) async {
    final workspace = await store.getWorkspace(workspaceId);
    final existing = await _linesRef(workspaceId).get();
    if (existing.size >= productionLineLimit) {
      throw const ApiError(
        409,
        'production_line_limit_reached',
        'This workspace already holds the maximum number of production lines.',
      );
    }
    final fields = validatedProductionLineFields(
      body,
      workspace,
      requireAll: true,
    );
    final id = _uuid.v4();
    final now = Timestamp.now();
    await _lineRef(workspaceId, id).set({
      ...fields,
      'id': id,
      'workspaceId': workspaceId,
      'createdAt': now,
      'createdBy': actor.uid,
      'updatedAt': now,
    });
    return ProductionLine.fromData(id, {...fields, 'workspaceId': workspaceId});
  }

  Future<ProductionLine> update(
    String workspaceId,
    String lineId,
    Map<String, Object?> body,
  ) async {
    final workspace = await store.getWorkspace(workspaceId);
    final snapshot = await _lineRef(workspaceId, lineId).get();
    if (!snapshot.exists) throw _notFound;
    final fields = validatedProductionLineFields(
      body,
      workspace,
      requireAll: false,
    );
    if (fields.isEmpty) {
      throw const ApiError(
        400,
        'production_line_update_empty',
        'Provide at least one production line field to change.',
      );
    }
    await _lineRef(
      workspaceId,
      lineId,
    ).update({...fields, 'updatedAt': Timestamp.now()});
    final updated = await _lineRef(workspaceId, lineId).get();
    return ProductionLine.fromData(lineId, updated.data() ?? const {});
  }

  /// Removes the ii-os binding and its memberships. Nothing else.
  ///
  /// Tickets, activations, dispatch receipts, and every GitHub object survive:
  /// a line is a lens over work that exists independently of it.
  Future<void> delete(String workspaceId, String lineId) async {
    final snapshot = await _lineRef(workspaceId, lineId).get();
    if (!snapshot.exists) throw _notFound;
    final members = await _membershipsRef(
      workspaceId,
    ).where('lineId', WhereFilter.equal, lineId).get();
    final batch = store.firestore.batch();
    for (final doc in members.docs) {
      batch.delete(doc.ref);
    }
    batch.delete(_lineRef(workspaceId, lineId));
    await batch.commit();
  }

  Future<List<Map<String, Object?>>> listMembers(
    String workspaceId,
    String lineId,
  ) async {
    final snapshot = await _lineRef(workspaceId, lineId).get();
    if (!snapshot.exists) throw _notFound;
    final members = await _membershipsRef(
      workspaceId,
    ).where('lineId', WhereFilter.equal, lineId).get();
    final result = members.docs.map((doc) {
      final data = doc.data();
      return <String, Object?>{
        'lineId': data['lineId'],
        'uid': data['uid'],
        'grantedBy': data['grantedBy'],
        'grantedAt': (data['grantedAt'] as Timestamp?)
            ?.toDate()
            .toUtc()
            .toIso8601String(),
      };
    }).toList();
    result.sort((a, b) => (a['uid']! as String).compareTo(b['uid']! as String));
    return result;
  }

  /// Grants [uid] access to [lineId].
  ///
  /// The target must already be a member of the workspace; a production line
  /// cannot be a side door into a workspace someone was never invited to.
  Future<void> grantMember(
    AuthenticatedUser actor,
    String workspaceId,
    String lineId,
    String uid,
  ) async {
    final snapshot = await _lineRef(workspaceId, lineId).get();
    if (!snapshot.exists) throw _notFound;
    final target = await store.getMembership(workspaceId, uid);
    if (target == null) {
      throw const ApiError(
        409,
        'production_line_member_not_in_workspace',
        'Add this person to the workspace before granting line access.',
      );
    }
    await _memberRef(workspaceId, lineId, uid).set({
      'lineId': lineId,
      'uid': uid,
      'grantedBy': actor.uid,
      'grantedAt': Timestamp.now(),
    });
  }

  Future<void> revokeMember(
    String workspaceId,
    String lineId,
    String uid,
  ) async {
    final member = await _memberRef(workspaceId, lineId, uid).get();
    if (!member.exists) {
      throw const ApiError(
        404,
        'production_line_member_not_found',
        'That person does not have access to this production line.',
      );
    }
    await _memberRef(workspaceId, lineId, uid).delete();
  }

  bool _seesEveryLine(Membership membership) =>
      membership.role == WorkspaceRole.owner ||
      membership.role == WorkspaceRole.admin;

  Future<Set<String>> _memberLineIds(String workspaceId, String uid) async {
    final memberships = await _membershipsRef(
      workspaceId,
    ).where('uid', WhereFilter.equal, uid).get();
    return memberships.docs
        .map((doc) => doc.data()['lineId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  CollectionReference<Map<String, Object?>> _linesRef(String workspaceId) =>
      store.firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('productionLines');

  DocumentReference<Map<String, Object?>> _lineRef(
    String workspaceId,
    String lineId,
  ) => _linesRef(workspaceId).doc(lineId);

  CollectionReference<Map<String, Object?>> _membershipsRef(
    String workspaceId,
  ) => store.firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('productionLineMemberships');

  DocumentReference<Map<String, Object?>> _memberRef(
    String workspaceId,
    String lineId,
    String uid,
  ) => _membershipsRef(workspaceId).doc('${lineId}_$uid');
}

/// Validates the client-writable fields and nothing else.
///
/// Mirrors `updateWorkspace`'s allowlist: an unknown key is rejected rather
/// than ignored, so a typo fails loudly instead of silently doing nothing.
/// Public so it can be unit-tested without Firestore, the way
/// `AgentDispatchResult.parse` is.
Map<String, Object?> validatedProductionLineFields(
  Map<String, Object?> body,
  Workspace workspace, {
  required bool requireAll,
}) {
  const allowed = {
    'name',
    'repository',
    'projectId',
    'permissionProfileId',
    'permissionRef',
    'colorToken',
    'iconToken',
  };
  final unknown = body.keys.where((key) => !allowed.contains(key));
  if (unknown.isNotEmpty) {
    throw const ApiError(
      400,
      'production_line_invalid_field',
      'That production line field cannot be set.',
    );
  }
  if (requireAll) {
    final missing = allowed.where((key) => !body.containsKey(key));
    if (missing.isNotEmpty) {
      throw const ApiError(
        400,
        'production_line_incomplete',
        'A production line needs a name, repository, board, permission '
            'scope, colour, and icon.',
      );
    }
  }
  final fields = <String, Object?>{};
  for (final key in allowed) {
    if (!body.containsKey(key)) continue;
    fields[key] = switch (key) {
      'name' => _validatedName(body[key]),
      'repository' => _validatedRepository(body[key], workspace),
      'projectId' => _validatedProjectId(body[key], workspace),
      'permissionProfileId' => _validatedToken(
        body[key],
        'permissionProfileId',
      ),
      'permissionRef' => _validatedToken(body[key], 'permissionRef'),
      'colorToken' => _validatedMember(
        body[key],
        productionLineColorTokens,
        'colorToken',
      ),
      _ => _validatedMember(body[key], productionLineIconTokens, 'iconToken'),
    };
  }
  return fields;
}

String _validatedName(Object? value) {
  final name = value is String ? value.trim() : '';
  if (name.isEmpty || name.length > _maxNameLength) {
    throw const ApiError(
      400,
      'production_line_invalid_name',
      'Give the production line a name of 80 characters or fewer.',
    );
  }
  return name;
}

String _validatedRepository(Object? value, Workspace workspace) {
  final repository = value is String ? value.trim() : '';
  if (!workspace.repositories.contains(repository)) {
    throw const ApiError(
      422,
      'production_line_repository_unknown',
      'Select a repository this workspace has installed.',
    );
  }
  return repository;
}

String _validatedProjectId(Object? value, Workspace workspace) {
  final projectId = value is String ? value.trim() : '';
  if (!workspace.projects.any((project) => project.id == projectId)) {
    throw const ApiError(
      422,
      'production_line_project_unknown',
      'Select a GitHub Project this workspace has connected.',
    );
  }
  return projectId;
}

String _validatedToken(Object? value, String field) {
  final token = value is String ? value.trim() : '';
  if (token.isEmpty || token.length > 200) {
    throw ApiError(
      400,
      'production_line_invalid_$field',
      '$field must be a bounded identifier.',
    );
  }
  return token;
}

String _validatedMember(Object? value, Set<String> allowed, String field) {
  final token = value is String ? value.trim() : '';
  if (!allowed.contains(token)) {
    throw ApiError(
      400,
      'production_line_invalid_$field',
      '$field must be one of the supported identity tokens.',
    );
  }
  return token;
}

const _notFound = ApiError(
  404,
  'production_line_not_found',
  'Production line not found.',
);
