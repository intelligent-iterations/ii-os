import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'storyboard_store.dart';
import 'workspace_store.dart';

extension WorkspaceStoryboardPanelExtend on WorkspaceStore {
  Future<Map<String, Object?>> recordStoryboardPanelExtendedFrame({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required String sourcePanelId,
    required String jobId,
    required String path,
    required String generation,
    required String contentType,
    required int sizeBytes,
    required String sha256,
    required String updatedBy,
  }) async {
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
      final panels = _extendPanelMaps(data['panels']);
      final index = panels.indexWhere((panel) => panel['id'] == panelId);
      if (index < 0) {
        throw const ApiError(
          404,
          'storyboard_panel_not_found',
          'Storyboard panel not found.',
        );
      }
      if (!panels.any((panel) => panel['id'] == sourcePanelId)) {
        throw const ApiError(
          404,
          'storyboard_panel_not_found',
          'Source storyboard panel not found.',
        );
      }
      final generationJobIds = _extendPanelJobIds(panels[index]);
      if (!generationJobIds.contains(jobId)) generationJobIds.add(jobId);
      panels[index] = {
        ...panels[index],
        'jobId': jobId,
        'generationJobIds': generationJobIds,
        'selectedImage': {
          'jobId': jobId,
          'path': path,
          'generation': generation,
          'content_type': contentType,
          'size_bytes': sizeBytes,
          'sha256': sha256,
        },
        'extendedFromPanelId': sourcePanelId,
        'generationPrompt': null,
        'generationRequestedAt': Timestamp.now(),
        'generationError': null,
      };
      transaction.update(ref, {
        'panels': panels,
        'updatedBy': updatedBy,
        'updatedAt': Timestamp.now(),
      });
    });
    return getStoryboard(workspaceId, storyboardId);
  }
}

List<Map<String, Object?>> _extendPanelMaps(Object? value) =>
    value is List<Object?>
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.cast<String, Object?>())
          .toList()
    : <Map<String, Object?>>[];

List<String> _extendPanelJobIds(Map<String, Object?> panel) {
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
