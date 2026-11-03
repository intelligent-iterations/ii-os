import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'prompt_guide_catalog.dart';

/// Which tier owns an edited guide.
///
/// Two layers, because a studio that rewrote the narration guide once should
/// not have to paste it into every project, while a single project trying
/// something new should not have to change it for everyone.
enum PromptGuideScope {
  organization('organization'),
  workspace('workspace');

  const PromptGuideScope(this.value);

  final String value;

  static PromptGuideScope? tryParse(String value) {
    for (final scope in PromptGuideScope.values) {
      if (scope.value == value) return scope;
    }
    return null;
  }
}

/// What happened to a guide, as the history reads it back.
enum PromptGuideChange {
  edited('edited'),
  reset('reset'),
  restored('restored');

  const PromptGuideChange(this.value);

  final String value;
}

/// One guide's stored state at a tier.
final class PromptGuideOverride {
  const PromptGuideOverride({
    required this.guideId,
    required this.body,
    required this.version,
    required this.updatedBy,
    required this.updatedAt,
  });

  final String guideId;
  final String body;

  /// Increments on every edit, so a client can tell a stale cache from a
  /// current one without comparing several thousand characters of prose.
  final int version;
  final String updatedBy;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'guideId': guideId,
    'body': body,
    'version': version,
    'updatedBy': updatedBy,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// One entry in a guide's history.
final class PromptGuideRevision {
  const PromptGuideRevision({
    required this.id,
    required this.guideId,
    required this.body,
    required this.version,
    required this.change,
    required this.createdBy,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final String guideId;

  /// The text as of this revision. A reset records the default that took over,
  /// so restoring any point in the history is a single write of one field
  /// rather than a decision about what "before" meant.
  final String body;
  final int version;
  final PromptGuideChange change;
  final String createdBy;
  final DateTime createdAt;
  final String note;

  Map<String, Object?> toJson() => {
    'id': id,
    'guideId': guideId,
    'body': body,
    'version': version,
    'change': change.value,
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'note': note,
  };
}

/// Guides an administrator has edited, and every version they have been.
///
/// One document per scope holding every override, rather than a document per
/// guide: enhancement resolves a whole library at once, so the shape that
/// matters is the one that answers "what has this tenant changed" in a single
/// read. History lives in a subcollection, which only the settings screen ever
/// touches.
final class PromptGuideStore {
  PromptGuideStore({
    required this.firestore,
    DateTime Function()? clock,
    this._uuid = const Uuid(),
  }) : _clock = clock ?? _utcNow;

  static const collection = 'promptGuides';
  static const _revisions = 'revisions';

  /// Bounds one guide's history so a document that is edited every day does
  /// not grow without limit. Older entries stay readable by page.
  static const historyPageLimit = 50;

  final Firestore firestore;
  final DateTime Function() _clock;
  final Uuid _uuid;

  DocumentReference<Map<String, Object?>> _doc(
    PromptGuideScope scope,
    String scopeId,
  ) => firestore.collection(collection).doc(documentId(scope, scopeId));

  /// The document id for a scope, namespaced so an organization id and a
  /// workspace id can never collide.
  static String documentId(PromptGuideScope scope, String scopeId) =>
      '${scope.value}_$scopeId';

  /// Every override stored at one tier.
  Future<Map<String, PromptGuideOverride>> read(
    PromptGuideScope scope,
    String scopeId,
  ) async {
    if (scopeId.isEmpty) return const {};
    final data = (await _doc(scope, scopeId).get()).data();
    return _parse(data?['guides']);
  }

  /// The guide text in force for a workspace, organization defaults first and
  /// the workspace's own edits on top.
  ///
  /// Up to two reads, made only after a person explicitly presses Enhance.
  /// Generation dispatch never loads or applies a prompt guide.
  Future<PromptGuideLibrary> library({
    required String workspaceId,
    String organizationId = '',
  }) async {
    final organization = organizationId.isEmpty
        ? const <String, PromptGuideOverride>{}
        : await read(PromptGuideScope.organization, organizationId);
    final workspace = await read(PromptGuideScope.workspace, workspaceId);
    return PromptGuideLibrary({
      for (final entry in organization.entries) entry.key: entry.value.body,
      for (final entry in workspace.entries) entry.key: entry.value.body,
    });
  }

  /// Replaces one guide's text and records the change.
  Future<PromptGuideOverride> save({
    required PromptGuideScope scope,
    required String scopeId,
    required String guideId,
    required String body,
    required String actorUid,
    String note = '',
  }) => _write(
    scope: scope,
    scopeId: scopeId,
    guideId: guideId,
    body: validatedPromptGuideBody(body),
    actorUid: actorUid,
    change: PromptGuideChange.edited,
    note: note,
  );

  /// Removes the override so the shipped default applies again.
  ///
  /// The revision records the default text rather than an empty body, so the
  /// history reads as a sequence of what the guide *was* at each point instead
  /// of a gap someone has to reconstruct.
  Future<void> reset({
    required PromptGuideScope scope,
    required String scopeId,
    required String guideId,
    required String actorUid,
  }) async {
    final definition = _definition(guideId);
    final ref = _doc(scope, scopeId);
    final current = _parse((await ref.get()).data()?['guides']);
    if (!current.containsKey(guideId)) return;
    final now = _clock();
    final version = current[guideId]!.version + 1;
    final remaining = {...current}..remove(guideId);
    await ref.set({
      'scope': scope.value,
      'scopeId': scopeId,
      'guides': {
        for (final entry in remaining.entries)
          entry.key: _guideData(entry.value),
      },
      'updatedAt': Timestamp.fromDate(now),
    });
    await _recordRevision(
      ref: ref,
      guideId: guideId,
      body: definition.body,
      version: version,
      change: PromptGuideChange.reset,
      actorUid: actorUid,
      now: now,
      note: '',
    );
  }

  /// Puts a past revision's text back, as a new revision of its own.
  Future<PromptGuideOverride> restore({
    required PromptGuideScope scope,
    required String scopeId,
    required String guideId,
    required String revisionId,
    required String actorUid,
  }) async {
    final snapshot = await _doc(
      scope,
      scopeId,
    ).collection(_revisions).doc(revisionId).get();
    final data = snapshot.data();
    if (data == null || data['guideId'] != guideId) {
      throw const ApiError(
        404,
        'prompt_guide_revision_not_found',
        'That version of the guide no longer exists.',
      );
    }
    return _write(
      scope: scope,
      scopeId: scopeId,
      guideId: guideId,
      body: validatedPromptGuideBody(data['body'] as String? ?? ''),
      actorUid: actorUid,
      change: PromptGuideChange.restored,
      note: 'Restored version ${data['version'] ?? '?'}',
    );
  }

  /// One guide's history, newest first.
  Future<List<PromptGuideRevision>> history({
    required PromptGuideScope scope,
    required String scopeId,
    required String guideId,
    int limit = historyPageLimit,
  }) async {
    final bounded = limit.clamp(1, historyPageLimit);
    final snapshot = await _doc(scope, scopeId)
        .collection(_revisions)
        .where('guideId', WhereFilter.equal, guideId)
        .orderBy('version', descending: true)
        .limit(bounded)
        .get();
    return snapshot.docs
        .map((doc) => _revision(doc.id, doc.data()))
        .whereType<PromptGuideRevision>()
        .toList(growable: false);
  }

  Future<PromptGuideOverride> _write({
    required PromptGuideScope scope,
    required String scopeId,
    required String guideId,
    required String body,
    required String actorUid,
    required PromptGuideChange change,
    required String note,
  }) async {
    _definition(guideId);
    final ref = _doc(scope, scopeId);
    final now = _clock();
    final current = _parse((await ref.get()).data()?['guides']);
    final version = (current[guideId]?.version ?? 0) + 1;
    final saved = PromptGuideOverride(
      guideId: guideId,
      body: body,
      version: version,
      updatedBy: actorUid,
      updatedAt: now,
    );
    await ref.set({
      'scope': scope.value,
      'scopeId': scopeId,
      'guides': {
        for (final entry in current.entries)
          if (entry.key != guideId) entry.key: _guideData(entry.value),
        guideId: _guideData(saved),
      },
      'updatedAt': Timestamp.fromDate(now),
    });
    await _recordRevision(
      ref: ref,
      guideId: guideId,
      body: body,
      version: version,
      change: change,
      actorUid: actorUid,
      now: now,
      note: note,
    );
    return saved;
  }

  Future<void> _recordRevision({
    required DocumentReference<Map<String, Object?>> ref,
    required String guideId,
    required String body,
    required int version,
    required PromptGuideChange change,
    required String actorUid,
    required DateTime now,
    required String note,
  }) async {
    await ref.collection(_revisions).doc(_uuid.v4()).create({
      'guideId': guideId,
      'body': body,
      'version': version,
      'change': change.value,
      'createdBy': actorUid,
      'createdAt': Timestamp.fromDate(now),
      'note': note,
    });
  }

  PromptGuideDefinition _definition(String guideId) {
    final definition = promptGuidesById[guideId];
    if (definition == null) {
      throw const ApiError(
        404,
        'prompt_guide_not_found',
        'That prompting guide is not one ii-os uses.',
      );
    }
    return definition;
  }

  static Map<String, Object?> _guideData(PromptGuideOverride guide) => {
    'body': guide.body,
    'version': guide.version,
    'updatedBy': guide.updatedBy,
    'updatedAt': Timestamp.fromDate(guide.updatedAt),
  };

  static Map<String, PromptGuideOverride> _parse(Object? value) {
    if (value is! Map) return const {};
    final out = <String, PromptGuideOverride>{};
    for (final entry in value.cast<String, Object?>().entries) {
      final data = entry.value;
      if (data is! Map) continue;
      final guide = data.cast<String, Object?>();
      final body = guide['body'];
      if (body is! String || body.trim().isEmpty) continue;
      out[entry.key] = PromptGuideOverride(
        guideId: entry.key,
        body: body,
        version: (guide['version'] as num?)?.toInt() ?? 1,
        updatedBy: guide['updatedBy'] as String? ?? '',
        updatedAt: _date(guide['updatedAt']),
      );
    }
    return out;
  }

  static PromptGuideRevision? _revision(String id, Map<String, Object?>? data) {
    if (data == null) return null;
    final body = data['body'];
    final guideId = data['guideId'];
    if (body is! String || guideId is! String) return null;
    return PromptGuideRevision(
      id: id,
      guideId: guideId,
      body: body,
      version: (data['version'] as num?)?.toInt() ?? 0,
      change: PromptGuideChange.values.firstWhere(
        (item) => item.value == data['change'],
        orElse: () => PromptGuideChange.edited,
      ),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _date(data['createdAt']),
      note: data['note'] as String? ?? '',
    );
  }

  static DateTime _date(Object? value) => value is Timestamp
      ? value.toDate().toUtc()
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Normalises and bounds a guide body on its way in.
///
/// Top-level so the rule is testable without a Firestore, and so the two
/// callers that write a body -- an edit and a restore -- cannot drift: a restore
/// replays text that was valid when it was written, and the cap could have
/// changed since.
String validatedPromptGuideBody(String body) {
  final normalized = body.trim();
  if (normalized.isEmpty) {
    throw const ApiError(
      400,
      'invalid_prompt_guide',
      'A guide cannot be empty. Reset it instead to go back to the default.',
    );
  }
  if (normalized.length > promptGuideMaxLength) {
    throw const ApiError(
      400,
      'invalid_prompt_guide',
      'That guide is longer than ii-os can send with every rewrite.',
    );
  }
  return normalized;
}

DateTime _utcNow() => DateTime.now().toUtc();
