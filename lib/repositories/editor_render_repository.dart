import '../models/models.dart';
import '../services/api_client.dart';

/// The server-owned port for a video-editor render.
abstract interface class EditorRenderRepository {
  Future<String> submit({
    required String workspaceId,
    required String renderManifest,
    required bool ghostMode,
  });
}

enum EditorRenderJobStatus { active, completed, failed, cancelled }

abstract interface class EditorRenderStatusRepository {
  Future<EditorRenderJobStatus> status({
    required String workspaceId,
    required String jobId,
  });
}

final class EditorRenderApiRepository
    implements EditorRenderRepository, EditorRenderStatusRepository {
  const EditorRenderApiRepository(this.api);

  final ApiClient api;

  @override
  Future<String> submit({
    required String workspaceId,
    required String renderManifest,
    required bool ghostMode,
  }) async {
    final response = await api.post(
      'v1/workspaces/$workspaceId/video-projects/render',
      body: {
        'renderManifest': renderManifest,
        if (ghostMode) 'ghostMode': true,
      },
    );
    final job = asJsonMap(response['data']);
    final jobId = job['jobId'] ?? job['id'];
    return jobId is String && jobId.isNotEmpty ? jobId : '';
  }

  @override
  Future<EditorRenderJobStatus> status({
    required String workspaceId,
    required String jobId,
  }) async {
    final response = await api.get(
      'v1/workspaces/$workspaceId/jobs/${Uri.encodeComponent(jobId)}',
    );
    return parseEditorRenderJobStatus(asJsonMap(response['job']));
  }
}

EditorRenderJobStatus parseEditorRenderJobStatus(JsonMap job) {
  final status = job['status']?.toString().trim().toLowerCase() ?? '';
  return switch (status) {
    'completed' || 'succeeded' || 'success' => EditorRenderJobStatus.completed,
    'failed' => EditorRenderJobStatus.failed,
    'cancelled' || 'canceled' => EditorRenderJobStatus.cancelled,
    _ => EditorRenderJobStatus.active,
  };
}
