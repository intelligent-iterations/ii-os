import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'workspace_store.dart';

const storyboardOverviewWordLimit = 150;
const storyboardMinimumPanels = 3;
const storyboardMaximumPanels = 9;

final _storyboardUuid = Uuid();

extension WorkspaceStoryboards on WorkspaceStore {
  Future<List<Map<String, Object?>>> listStoryboards(String workspaceId) async {
    final snapshots = await firestore
        .collection('storyboards')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .limit(100)
        .get();
    final storyboards = snapshots.docs
        .map((snapshot) => _publicStoryboard(snapshot.id, snapshot.data()))
        .toList();
    storyboards.sort(
      (left, right) =>
          (right['updatedAt'] as String).compareTo(left['updatedAt'] as String),
    );
    return storyboards;
  }

  Future<Map<String, Object?>> getStoryboard(
    String workspaceId,
    String storyboardId,
  ) async {
    final snapshot = await firestore
        .collection('storyboards')
        .doc(storyboardId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId) {
      throw const ApiError(
        404,
        'storyboard_not_found',
        'Storyboard not found.',
      );
    }
    return _publicStoryboard(snapshot.id, data);
  }

  Future<Map<String, Object?>> createStoryboard({
    required String workspaceId,
    required String createdBy,
    required Object? name,
    required Object? overview,
    int panelCount = storyboardMinimumPanels,
  }) async {
    if (panelCount < storyboardMinimumPanels ||
        panelCount > storyboardMaximumPanels) {
      throw const ApiError(
        400,
        'invalid_storyboard_panel_count',
        'A storyboard must contain between 3 and 9 panels.',
      );
    }
    final storyboardId = _storyboardUuid.v4();
    final now = Timestamp.now();
    final data = <String, Object?>{
      'workspaceId': workspaceId,
      'name': _storyboardName(name),
      'overview': validateStoryboardOverview(overview),
      'panels': List.generate(panelCount, (_) => _newPanel()),
      'createdBy': createdBy,
      'updatedBy': createdBy,
      'createdAt': now,
      'updatedAt': now,
    };
    await firestore.collection('storyboards').doc(storyboardId).create(data);
    return _publicStoryboard(storyboardId, data);
  }

  Future<Map<String, Object?>> updateStoryboard({
    required String workspaceId,
    required String storyboardId,
    required String updatedBy,
    required Map<String, Object?> changes,
  }) async {
    const allowed = {'name', 'overview', 'panels'};
    if (changes.keys.any((key) => !allowed.contains(key))) {
      throw const ApiError(
        400,
        'invalid_storyboard_update',
        'Only storyboard name, overview, and panels may be updated.',
      );
    }
    final ref = firestore.collection('storyboards').doc(storyboardId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = snapshot.data();
      if (!snapshot.exists ||
          current == null ||
          current['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'storyboard_not_found',
          'Storyboard not found.',
        );
      }
      final update = <String, Object?>{
        'updatedBy': updatedBy,
        'updatedAt': Timestamp.now(),
      };
      if (changes.containsKey('name')) {
        update['name'] = _storyboardName(changes['name']);
      }
      if (changes.containsKey('overview')) {
        update['overview'] = validateStoryboardOverview(changes['overview']);
      }
      if (changes.containsKey('panels')) {
        update['panels'] = validateStoryboardPanels(
          changes['panels'],
          current['panels'],
        );
      }
      transaction.update(ref, update);
    });
    return getStoryboard(workspaceId, storyboardId);
  }

  Future<Map<String, Object?>> recordStoryboardPanelGeneration({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String jobId,
    required String generationPrompt,
    required String updatedBy,
  }) async {
    final ref = firestore.collection('storyboards').doc(storyboardId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = snapshot.data();
      if (!snapshot.exists ||
          current == null ||
          current['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'storyboard_not_found',
          'Storyboard not found.',
        );
      }
      final panels = _maps(current['panels']);
      final index = panels.indexWhere((panel) => panel['id'] == panelId);
      if (index < 0) {
        throw const ApiError(
          404,
          'storyboard_panel_not_found',
          'Storyboard panel not found.',
        );
      }
      final generationJobIds = _storyboardPanelJobIds(panels[index]);
      if (!generationJobIds.contains(jobId)) generationJobIds.add(jobId);
      panels[index] = {
        ...panels[index],
        'jobId': jobId,
        'generationJobIds': generationJobIds,
        'generationPrompt': generationPrompt,
        'generationRequestedAt': Timestamp.now(),
        'generationError': null,
        'extendedFromPanelId': null,
      };
      transaction.update(ref, {
        'panels': panels,
        'updatedBy': updatedBy,
        'updatedAt': Timestamp.now(),
      });
    });
    return getStoryboard(workspaceId, storyboardId);
  }

  Future<void> recordStoryboardPanelGenerationFailure({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String jobId,
    required String code,
    required String message,
    required String updatedBy,
  }) async {
    final ref = firestore.collection('storyboards').doc(storyboardId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = snapshot.data();
      if (!snapshot.exists ||
          current == null ||
          current['workspaceId'] != workspaceId) {
        return;
      }
      final panels = _maps(current['panels']);
      final index = panels.indexWhere(
        (panel) => panel['id'] == panelId && panel['jobId'] == jobId,
      );
      if (index < 0) return;
      panels[index] = {
        ...panels[index],
        'generationError': {
          'code': code,
          'message': message,
          'at': Timestamp.now(),
        },
      };
      transaction.update(ref, {
        'panels': panels,
        'updatedBy': updatedBy,
        'updatedAt': Timestamp.now(),
      });
    });
  }

  Future<Map<String, Object?>> recordStoryboardPanelVideoGeneration({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String jobId,
    required String generationPrompt,
    required int durationSeconds,
    required String updatedBy,
  }) async {
    final ref = firestore.collection('storyboards').doc(storyboardId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = snapshot.data();
      if (!snapshot.exists ||
          current == null ||
          current['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'storyboard_not_found',
          'Storyboard not found.',
        );
      }
      final panels = _maps(current['panels']);
      final index = panels.indexWhere((panel) => panel['id'] == panelId);
      if (index < 0) {
        throw const ApiError(
          404,
          'storyboard_panel_not_found',
          'Storyboard panel not found.',
        );
      }
      panels[index] = {
        ...panels[index],
        'videoJobId': jobId,
        'videoGenerationPrompt': generationPrompt,
        'videoDurationSeconds': durationSeconds,
        'videoGenerationRequestedAt': Timestamp.now(),
        'videoGenerationError': null,
      };
      transaction.update(ref, {
        'panels': panels,
        'updatedBy': updatedBy,
        'updatedAt': Timestamp.now(),
      });
    });
    return getStoryboard(workspaceId, storyboardId);
  }

  Future<void> recordStoryboardPanelVideoGenerationFailure({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String jobId,
    required String code,
    required String message,
    required String updatedBy,
  }) async {
    final ref = firestore.collection('storyboards').doc(storyboardId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = snapshot.data();
      if (!snapshot.exists ||
          current == null ||
          current['workspaceId'] != workspaceId) {
        return;
      }
      final panels = _maps(current['panels']);
      final index = panels.indexWhere(
        (panel) => panel['id'] == panelId && panel['videoJobId'] == jobId,
      );
      if (index < 0) return;
      panels[index] = {
        ...panels[index],
        'videoGenerationError': {
          'code': code,
          'message': message,
          'at': Timestamp.now(),
        },
      };
      transaction.update(ref, {
        'panels': panels,
        'updatedBy': updatedBy,
        'updatedAt': Timestamp.now(),
      });
    });
  }

  Future<void> deleteStoryboard(String workspaceId, String storyboardId) async {
    await getStoryboard(workspaceId, storyboardId);
    await firestore.collection('storyboards').doc(storyboardId).delete();
  }
}

int storyboardWordCount(String value) =>
    RegExp(r'\S+').allMatches(value.trim()).length;

String validateStoryboardOverview(Object? value) {
  if (value is! String) {
    throw const ApiError(
      400,
      'invalid_storyboard_overview',
      'The storyboard overview must be text.',
    );
  }
  final overview = value.trim();
  if (storyboardWordCount(overview) > storyboardOverviewWordLimit) {
    throw const ApiError(
      400,
      'storyboard_overview_too_long',
      'Keep the storyboard overview to 150 words or fewer.',
    );
  }
  return overview;
}

String storyboardGenerationPrompt(Object? value) {
  if (value is! String) {
    throw const ApiError(
      400,
      'invalid_storyboard_panel_prompt',
      'A panel prompt of at most 4,000 characters is required.',
    );
  }
  final prompt = value.trim();
  if (prompt.isEmpty || prompt.length > 4000) {
    throw const ApiError(
      400,
      'invalid_storyboard_panel_prompt',
      'A panel prompt of at most 4,000 characters is required.',
    );
  }
  return prompt;
}

Map<String, Object?> _newPanel() => {
  'id': _storyboardUuid.v4(),
  'prompt': '',
  'characterIds': <String>[],
  'referencePanelIds': <String>[],
  'jobId': null,
  'generationJobIds': <String>[],
  'selectedImage': null,
  'generationPrompt': null,
  'generationRequestedAt': null,
  'generationError': null,
  'extendedFromPanelId': null,
  'videoJobId': null,
  'videoGenerationPrompt': null,
  'videoDurationSeconds': 5,
  'videoGenerationRequestedAt': null,
  'videoGenerationError': null,
};

List<Map<String, Object?>> validateStoryboardPanels(
  Object? value,
  Object? existingValue,
) {
  if (value is! List<Object?> ||
      value.length < storyboardMinimumPanels ||
      value.length > storyboardMaximumPanels) {
    throw const ApiError(
      400,
      'invalid_storyboard_panels',
      'A storyboard must contain between 3 and 9 panels.',
    );
  }
  final existing = {
    for (final panel in _maps(existingValue)) panel['id']?.toString(): panel,
  };
  final ids = <String>{};
  final panels = value.map((raw) {
    final panel = _map(raw);
    final requestedId = panel['id']?.toString().trim() ?? '';
    final id = requestedId.isEmpty ? _storyboardUuid.v4() : requestedId;
    if (id.length > 100 || !ids.add(id)) {
      throw const ApiError(
        400,
        'invalid_storyboard_panel_id',
        'Storyboard panel IDs must be unique.',
      );
    }
    final prompt = panel['prompt'];
    if (prompt is! String || prompt.length > 4000) {
      throw const ApiError(
        400,
        'invalid_storyboard_panel_prompt',
        'Panel prompts must be text no longer than 4,000 characters.',
      );
    }
    final characterIds = panel['characterIds'];
    if (characterIds is! List<Object?> ||
        characterIds.length > 20 ||
        characterIds.any(
          (id) => id is! String || id.isEmpty || id.length > 200,
        )) {
      throw const ApiError(
        400,
        'invalid_storyboard_characters',
        'A panel may attach up to 20 valid characters.',
      );
    }
    final referencePanelIds = panel['referencePanelIds'] ?? const <Object?>[];
    if (referencePanelIds is! List<Object?> ||
        referencePanelIds.length > storyboardMaximumPanels ||
        referencePanelIds.any(
          (id) => id is! String || id.isEmpty || id.length > 100,
        )) {
      throw const ApiError(
        400,
        'invalid_storyboard_panel_references',
        'Panel references must identify panels in this storyboard.',
      );
    }
    final selectedCharacterIds = characterIds.whereType<String>().toSet();
    final selectedPanelIds = referencePanelIds.whereType<String>().toSet();
    if (selectedCharacterIds.length + selectedPanelIds.length > 3) {
      throw const ApiError(
        400,
        'storyboard_reference_limit',
        'Select up to 3 total character and panel references.',
      );
    }
    final prior = existing[id];
    return {
      'id': id,
      'prompt': prompt.trim(),
      'characterIds': selectedCharacterIds.toList(),
      'referencePanelIds': selectedPanelIds.toList(),
      'jobId': prior?['jobId'],
      'generationJobIds': prior == null
          ? <String>[]
          : _storyboardPanelJobIds(prior),
      'selectedImage': prior?['selectedImage'],
      'generationPrompt': prior?['generationPrompt'],
      'generationRequestedAt': prior?['generationRequestedAt'],
      'generationError': prior?['generationError'],
      'extendedFromPanelId': prior?['extendedFromPanelId'],
      'videoJobId': prior?['videoJobId'],
      'videoGenerationPrompt': prior?['videoGenerationPrompt'],
      'videoDurationSeconds': prior?['videoDurationSeconds'] ?? 5,
      'videoGenerationRequestedAt': prior?['videoGenerationRequestedAt'],
      'videoGenerationError': prior?['videoGenerationError'],
    };
  }).toList();
  for (final panel in panels) {
    final referencePanelIds = panel['referencePanelIds']! as List<String>;
    if (referencePanelIds.any((id) => !ids.contains(id))) {
      throw const ApiError(
        400,
        'storyboard_panel_reference_not_found',
        'Panel references must identify panels in this storyboard.',
      );
    }
  }
  return panels;
}

String _storyboardName(Object? value) {
  if (value is! String || value.trim().isEmpty || value.trim().length > 100) {
    throw const ApiError(
      400,
      'invalid_storyboard_name',
      'A storyboard name of at most 100 characters is required.',
    );
  }
  return value.trim();
}

Map<String, Object?> _publicStoryboard(
  String storyboardId,
  Map<String, Object?> data,
) => {'id': storyboardId, ..._jsonSafe(data)};

Map<String, Object?> _jsonSafe(Map<String, Object?> data) =>
    data.map((key, value) => MapEntry(key, _jsonSafeValue(value)));

Object? _jsonSafeValue(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  if (value is List<Object?>) return value.map(_jsonSafeValue).toList();
  if (value is Map<String, Object?>) return _jsonSafe(value);
  if (value is Map) return _jsonSafe(value.cast<String, Object?>());
  return value;
}

List<Map<String, Object?>> _maps(Object? value) => value is List<Object?>
    ? value.map(_map).toList()
    : <Map<String, Object?>>[];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

List<String> _storyboardPanelJobIds(Map<String, Object?> panel) {
  final raw = panel['generationJobIds'];
  final ids = raw is List
      ? raw.whereType<String>().where((id) => id.isNotEmpty).toList()
      : <String>[];
  final latest = panel['jobId'];
  if (latest is String && latest.isNotEmpty && !ids.contains(latest)) {
    ids.add(latest);
  }
  return ids;
}
