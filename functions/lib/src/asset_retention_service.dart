import 'dart:convert';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';

import 'api_error.dart';
import 'retention_policy.dart';
import 'workspace_store.dart';

const _gcsAttachmentMetadata = 'ii-os-asset-attachments';

final class AssetRetentionService {
  const AssetRetentionService({required this.store});

  final WorkspaceStore store;

  Future<void> protectCompletedTarget({
    required String workspaceId,
    required String jobId,
    required Map<String, Object?> target,
  }) async {
    final attachment = assetAttachmentForTarget(target);
    if (attachment == null ||
        !await _targetStillReferencesJob(workspaceId, jobId, target)) {
      return;
    }
    await protectRecord(
      workspaceId: workspaceId,
      collection: 'jobRuns',
      recordId: jobId,
      attachment: attachment,
    );
  }

  Future<bool> protectRecord({
    required String workspaceId,
    required String collection,
    required String recordId,
    required String attachment,
  }) async {
    _requireRecordIdentity(collection, recordId, attachment);
    final ref = store.firestore.collection(collection).doc(recordId);
    final initial = await ref.get();
    final initialData = initial.data();
    _requireWorkspaceRecord(initial.exists, initialData, workspaceId);
    final objects = _recordObjects(initialData!, workspaceId);
    if (objects.isEmpty) return false;
    await _hold(objects, workspaceId);

    late Set<String> finalAttachments;
    late bool acquired;
    await store.firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      _requireWorkspaceRecord(snapshot.exists, data, workspaceId);
      finalAttachments = assetAttachments(data!);
      acquired = finalAttachments.add(attachment);
      transaction.update(ref, {
        'assetAttachments': finalAttachments.toList()..sort(),
        'expiresAt': FieldValue.delete,
        'updatedAt': Timestamp.now(),
      });
    });
    await _syncObjects(
      objects,
      workspaceId: workspaceId,
      add: finalAttachments,
    );
    return acquired;
  }

  Future<void> releaseRecordAttachments({
    required String workspaceId,
    required String collection,
    required String recordId,
    required Set<String> attachments,
    required int retentionDays,
  }) async {
    if (attachments.isEmpty) return;
    for (final attachment in attachments) {
      _requireRecordIdentity(collection, recordId, attachment);
    }
    final ref = store.firestore.collection(collection).doc(recordId);
    final initial = await ref.get();
    final initialData = initial.data();
    if (!initial.exists ||
        initialData == null ||
        initialData['workspaceId'] != workspaceId) {
      return;
    }
    final effectiveAttachments = assetAttachments(
      initialData,
    ).intersection(attachments);
    if (effectiveAttachments.isEmpty) return;
    final objects = _recordObjects(initialData, workspaceId);
    late Set<String> remaining;
    await store.firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          data['workspaceId'] != workspaceId) {
        remaining = <String>{};
        return;
      }
      remaining = assetAttachments(data)..removeAll(effectiveAttachments);
      transaction.update(ref, {
        if (remaining.isEmpty)
          'assetAttachments': FieldValue.delete
        else
          'assetAttachments': remaining.toList()..sort(),
        if (remaining.isEmpty)
          'expiresAt': Timestamp.fromDate(
            DateTime.now().toUtc().add(
              Duration(
                days: retentionDays.clamp(
                  minArtifactRetentionDays,
                  maxArtifactRetentionDays,
                ),
              ),
            ),
          ),
        'updatedAt': Timestamp.now(),
      });
    });
    final current = await ref.get();
    final currentData = current.data();
    if (current.exists &&
        currentData != null &&
        assetAttachments(
          currentData,
        ).intersection(effectiveAttachments).isNotEmpty) {
      return;
    }
    await _syncObjects(
      objects,
      workspaceId: workspaceId,
      add: remaining,
      remove: effectiveAttachments,
    );
  }

  Future<void> releaseRemovedGraph({
    required String workspaceId,
    required Map<String, Set<String>> before,
    required Map<String, Set<String>> after,
    required int retentionDays,
  }) async {
    for (final entry in before.entries) {
      final removed = entry.value.difference(after[entry.key] ?? const {});
      if (removed.isEmpty) continue;
      final identity = entry.key.split('/');
      await releaseRecordAttachments(
        workspaceId: workspaceId,
        collection: identity.first,
        recordId: identity.last,
        attachments: removed,
        retentionDays: retentionDays,
      );
    }
  }

  Future<bool> _targetStillReferencesJob(
    String workspaceId,
    String jobId,
    Map<String, Object?> target,
  ) async {
    switch (target['kind']) {
      case 'character_image':
        final id = target['characterId'];
        if (id is! String || id.isEmpty) return false;
        final data =
            (await store.firestore.collection('characters').doc(id).get())
                .data();
        if (data == null || data['workspaceId'] != workspaceId) return false;
        final field = target['body'] == true
            ? 'bodyGenerationJobIds'
            : 'generationJobIds';
        return _strings(data[field]).contains(jobId);
      case 'storyboard_panel_image':
      case 'storyboard_panel_video':
        final id = target['storyboardId'];
        final panelId = target['panelId'];
        if (id is! String || panelId is! String) return false;
        final data =
            (await store.firestore.collection('storyboards').doc(id).get())
                .data();
        if (data == null || data['workspaceId'] != workspaceId) return false;
        for (final panel in _maps(data['panels'])) {
          if (panel['id'] != panelId) continue;
          return target['kind'] == 'storyboard_panel_video'
              ? panel['videoJobId'] == jobId
              : (_strings(
                  panel['generationJobIds'],
                )..add('${panel['jobId']}')).contains(jobId);
        }
    }
    return false;
  }

  Future<void> _hold(List<_ObjectIdentity> objects, String workspaceId) async {
    if (store.emulated) return;
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    if (connection.emulated) return;
    await _updateObjects(
      connection.bucket,
      objects,
      (remote) => storage.Object(temporaryHold: true),
    );
  }

  Future<void> _syncObjects(
    List<_ObjectIdentity> objects, {
    required String workspaceId,
    required Set<String> add,
    Set<String> remove = const {},
  }) async {
    if (store.emulated) return;
    final connection = await store.requireConnection(
      workspaceId,
      permission: 'assets.write',
    );
    if (connection.emulated) return;
    await _updateObjects(connection.bucket, objects, (remote) {
      final metadata = <String, String>{...?remote.metadata};
      final attached = _gcsAttachments(metadata)
        ..addAll(add)
        ..removeAll(remove);
      if (attached.isEmpty) {
        metadata.remove(_gcsAttachmentMetadata);
      } else {
        metadata[_gcsAttachmentMetadata] = jsonEncode(
          attached.toList()..sort(),
        );
      }
      return storage.Object(
        metadata: metadata,
        temporaryHold: attached.isNotEmpty,
      );
    });
  }

  Future<void> _updateObjects(
    String bucket,
    List<_ObjectIdentity> objects,
    storage.Object Function(storage.Object) patch,
  ) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      final api = storage.StorageApi(client);
      for (final object in objects) {
        for (var attempt = 0; attempt < 4; attempt++) {
          try {
            final remote = await api.objects.get(
              bucket,
              object.path,
              generation: object.generation,
            );
            if (remote is! storage.Object || remote.metageneration == null) {
              throw StateError('GCS object metadata is unavailable.');
            }
            await api.objects.patch(
              patch(remote),
              bucket,
              object.path,
              generation: object.generation,
              ifGenerationMatch: object.generation,
              ifMetagenerationMatch: remote.metageneration,
            );
            break;
          } catch (_) {
            if (attempt == 3) rethrow;
          }
        }
      }
    } catch (_) {
      throw const ApiError(
        409,
        'asset_retention_update_failed',
        'The attached asset retention state could not be updated.',
      );
    } finally {
      client.close();
    }
  }
}

/// What a saved video project is holding on to.
///
/// A project does not copy the media it uses; it holds it. Everything in this
/// graph keeps its bytes for as long as the project refers to them, and starts
/// its retention window only once the project stops.
Map<String, Set<String>> videoProjectAssetAttachmentGraph(
  Map<String, Object?> project,
) {
  final id = project['id'];
  if (id is! String || id.isEmpty) return {};
  final graph = <String, Set<String>>{};
  for (final entry in project['media'] as List<Object?>? ?? const []) {
    if (entry is! Map) continue;
    final media = entry.map((key, value) => MapEntry('$key', value));
    final mediaId = media['id'];
    final origin = media['origin'];
    if (mediaId is! String || mediaId.isEmpty || origin is! Map) continue;
    final attachment = 'video-project/$id/media/$mediaId';
    final kind = origin['kind'];
    final record = switch (kind) {
      'artifact' => ('jobRuns', origin['jobId']),
      'sourceAsset' => ('sourceAssets', origin['assetId']),
      _ => (null, null),
    };
    final collection = record.$1;
    final recordId = record.$2;
    if (collection == null || recordId is! String || recordId.isEmpty) continue;
    graph
        .putIfAbsent('$collection/$recordId', () => <String>{})
        .add(attachment);
  }
  return graph;
}

Map<String, Set<String>> characterAssetAttachmentGraph(
  Map<String, Object?> character,
) {
  final id = character['id'];
  if (id is! String || id.isEmpty) return {};
  final graph = <String, Set<String>>{};
  void add(String collection, String recordId, String attachment) {
    if (recordId.isEmpty || recordId == 'null') return;
    graph
        .putIfAbsent('$collection/$recordId', () => <String>{})
        .add(attachment);
  }

  for (final jobId in _strings(character['generationJobIds'])) {
    add('jobRuns', jobId, 'character/$id/head');
  }
  for (final jobId in _strings(character['bodyGenerationJobIds'])) {
    add('jobRuns', jobId, 'character/$id/body');
  }
  final sourceId = character['sourceAssetId'];
  if (sourceId is String) {
    add('sourceAssets', sourceId, 'character/$id/source');
  }
  return graph;
}

Map<String, Set<String>> storyboardAssetAttachmentGraph(
  Map<String, Object?> storyboard,
) {
  final id = storyboard['id'];
  if (id is! String || id.isEmpty) return {};
  final graph = <String, Set<String>>{};
  void add(String jobId, String attachment) {
    if (jobId.isEmpty || jobId == 'null') return;
    graph.putIfAbsent('jobRuns/$jobId', () => <String>{}).add(attachment);
  }

  for (final panel in _maps(storyboard['panels'])) {
    final panelId = panel['id'];
    if (panelId is! String || panelId.isEmpty) continue;
    final imageAttachment = 'storyboard/$id/panel/$panelId/image';
    for (final jobId in {
      ..._strings(panel['generationJobIds']),
      if (panel['jobId'] is String) panel['jobId']! as String,
    }) {
      add(jobId, imageAttachment);
    }
    final videoId = panel['videoJobId'];
    if (videoId is String) {
      add(videoId, 'storyboard/$id/panel/$panelId/video');
    }
  }
  return graph;
}

String? assetAttachmentForTarget(Map<String, Object?> target) {
  switch (target['kind']) {
    case 'character_image':
      final id = target['characterId'];
      return id is String && id.isNotEmpty
          ? 'character/$id/${target['body'] == true ? 'body' : 'head'}'
          : null;
    case 'storyboard_panel_image':
    case 'storyboard_panel_video':
      final storyboardId = target['storyboardId'];
      final panelId = target['panelId'];
      if (storyboardId is! String || panelId is! String) return null;
      return 'storyboard/$storyboardId/panel/$panelId/'
          '${target['kind'] == 'storyboard_panel_video' ? 'video' : 'image'}';
  }
  return null;
}

Set<String> assetAttachments(Map<String, Object?> data) =>
    _strings(data['assetAttachments']).where(_validAttachment).toSet();

List<_ObjectIdentity> _recordObjects(
  Map<String, Object?> data,
  String workspaceId,
) {
  final raw = data['artifacts'] is List<Object?>
      ? data['artifacts']! as List<Object?>
      : <Object?>[data];
  return raw
      .whereType<Map<Object?, Object?>>()
      .map((value) {
        final item = value.cast<String, Object?>();
        return _ObjectIdentity(
          item['path']?.toString() ?? '',
          item['generation']?.toString() ?? '',
        );
      })
      .where((item) {
        return item.path.startsWith('workspaces/$workspaceId/') &&
            RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(item.generation);
      })
      .toList();
}

Set<String> _gcsAttachments(Map<String, String> metadata) {
  try {
    final decoded = jsonDecode(metadata[_gcsAttachmentMetadata] ?? '[]');
    return decoded is List
        ? decoded.whereType<String>().where(_validAttachment).toSet()
        : <String>{};
  } catch (_) {
    return <String>{};
  }
}

void _requireRecordIdentity(
  String collection,
  String recordId,
  String attachment,
) {
  if (!const {'jobRuns', 'sourceAssets'}.contains(collection) ||
      recordId.isEmpty ||
      recordId.length > 200 ||
      !_validAttachment(attachment)) {
    throw const ApiError(
      400,
      'invalid_asset_attachment',
      'The asset attachment identity is invalid.',
    );
  }
}

void _requireWorkspaceRecord(
  bool exists,
  Map<String, Object?>? data,
  String workspaceId,
) {
  if (!exists || data == null || data['workspaceId'] != workspaceId) {
    throw const ApiError(
      404,
      'asset_record_not_found',
      'The attached asset record was not found.',
    );
  }
}

bool _validAttachment(String value) =>
    value.isNotEmpty &&
    value.length <= 400 &&
    RegExp(r'^[A-Za-z0-9._:/-]+$').hasMatch(value);

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.isNotEmpty).toList()
    : <String>[];

List<Map<String, Object?>> _maps(Object? value) => value is List
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.cast<String, Object?>())
          .toList()
    : <Map<String, Object?>>[];

final class _ObjectIdentity {
  const _ObjectIdentity(this.path, this.generation);

  final String path;
  final String generation;
}
