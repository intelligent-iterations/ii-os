import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'storyboard_store.dart';
import 'workspace_store.dart';

extension WorkspaceStoryboardPanelImages on WorkspaceStore {
  Future<List<Map<String, Object?>>> listStoryboardPanelImages({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
  }) async {
    final storyboard = await getStoryboard(workspaceId, storyboardId);
    final panel = _panel(storyboard, panelId);
    final selected = _imageMap(panel['selectedImage']);
    final images = <Map<String, Object?>>[];
    for (final jobId in _storyboardImageJobIds(panel).reversed.take(20)) {
      final snapshot = await firestore.collection('jobRuns').doc(jobId).get();
      final job = snapshot.data();
      if (!snapshot.exists ||
          job == null ||
          job['workspaceId'] != workspaceId) {
        continue;
      }
      final createdAt = _storyboardImageDate(
        job['completedAt'] ?? job['createdAt'],
      );
      for (final artifact in _imageMaps(job['artifacts'])) {
        final contentType = artifact['content_type'];
        final path = artifact['path'];
        final generation = artifact['generation'];
        final sizeBytes = artifact['size_bytes'];
        final sha256 = artifact['sha256'];
        if (contentType is! String ||
            !contentType.startsWith('image/') ||
            path is! String ||
            path.isEmpty ||
            generation is! String ||
            generation.isEmpty) {
          continue;
        }
        final hasVerifiedIdentity =
            sizeBytes is num &&
            sizeBytes.isFinite &&
            sizeBytes > 0 &&
            sizeBytes == sizeBytes.truncateToDouble() &&
            sha256 is String &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256);
        images.add({
          'jobId': jobId,
          'path': path,
          'generation': generation,
          'content_type': contentType,
          if (hasVerifiedIdentity) ...{
            'size_bytes': sizeBytes.toInt(),
            'sha256': sha256,
          },
          'createdAt': createdAt,
          'selected':
              selected?['jobId'] == jobId &&
              selected?['path'] == path &&
              selected?['generation'] == generation,
        });
      }
    }
    if (selected == null &&
        images.isNotEmpty &&
        images.first['jobId'] == panel['jobId']) {
      images.first['selected'] = true;
    }
    return images;
  }

  Future<Map<String, Object?>> selectStoryboardPanelImage({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String jobId,
    required String path,
    required String generation,
    required String updatedBy,
  }) async {
    final selected = await _selectableStoryboardPanelImage(
      workspaceId: workspaceId,
      storyboardId: storyboardId,
      panelId: panelId,
      jobId: jobId,
      path: path,
      generation: generation,
    );
    final ref = firestore.collection('storyboards').doc(storyboardId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
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
      final panels = _imageMaps(data['panels']);
      final index = panels.indexWhere((panel) => panel['id'] == panelId);
      if (index < 0 || !_storyboardImageJobIds(panels[index]).contains(jobId)) {
        throw const ApiError(
          404,
          'storyboard_panel_image_not_found',
          'The generated panel image was not found.',
        );
      }
      panels[index] = {
        ...panels[index],
        'selectedImage': {
          'jobId': jobId,
          'path': path,
          'generation': generation,
          'content_type': selected['content_type'],
        },
      };
      transaction.update(ref, {
        'panels': panels,
        'updatedBy': updatedBy,
        'updatedAt': Timestamp.now(),
      });
    });
    return getStoryboard(workspaceId, storyboardId);
  }

  Future<void> requireSelectableStoryboardPanelImage({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String jobId,
    required String path,
    required String generation,
  }) async {
    await _selectableStoryboardPanelImage(
      workspaceId: workspaceId,
      storyboardId: storyboardId,
      panelId: panelId,
      jobId: jobId,
      path: path,
      generation: generation,
    );
  }

  Future<Map<String, Object?>> _selectableStoryboardPanelImage({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String jobId,
    required String path,
    required String generation,
  }) async {
    final images = await listStoryboardPanelImages(
      workspaceId: workspaceId,
      storyboardId: storyboardId,
      panelId: panelId,
    );
    final selected = images.cast<Map<String, Object?>?>().firstWhere(
      (image) =>
          image?['jobId'] == jobId &&
          image?['path'] == path &&
          image?['generation'] == generation,
      orElse: () => null,
    );
    if (selected == null) {
      throw const ApiError(
        404,
        'storyboard_panel_image_not_found',
        'The generated panel image was not found.',
      );
    }
    return selected;
  }
}

Map<String, Object?> _panel(Map<String, Object?> storyboard, String panelId) {
  for (final panel in _imageMaps(storyboard['panels'])) {
    if (panel['id'] == panelId) return panel;
  }
  throw const ApiError(
    404,
    'storyboard_panel_not_found',
    'Storyboard panel not found.',
  );
}

List<String> _storyboardImageJobIds(Map<String, Object?> panel) {
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

List<Map<String, Object?>> _imageMaps(Object? value) => value is List
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((map) => map.cast<String, Object?>())
          .toList()
    : <Map<String, Object?>>[];

Map<String, Object?>? _imageMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

String _storyboardImageDate(Object? value) => value is Timestamp
    ? value.toDate().toUtc().toIso8601String()
    : value?.toString() ?? '';
