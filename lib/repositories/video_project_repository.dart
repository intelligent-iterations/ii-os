import '../models/models.dart';
import '../models/video_project.dart';
import '../services/api_client.dart';

/// The single owner of `v1/workspaces/{id}/video-projects`.
abstract interface class VideoProjectRepository {
  Future<VideoProjectListing> list(String workspaceId);

  Future<VideoProject> create(String workspaceId, {String? name});

  Future<VideoProject> read(String workspaceId, String projectId);

  /// Writes a new revision. [revision] is the one the caller started from; the
  /// control plane refuses the write when someone else has saved since.
  Future<VideoProject> save({
    required String workspaceId,
    required String projectId,
    required JsonMap timeline,
    required List<VideoProjectMediaRecord> media,
    required String change,
    required int revision,
    String? name,
    String? renderJobId,
    bool clearRenderJob = false,
  });

  Future<void> delete(String workspaceId, String projectId);
}

/// Raised when someone else saved the project first.
final class VideoProjectConflict implements Exception {
  const VideoProjectConflict();
}

final class VideoProjectApiRepository implements VideoProjectRepository {
  const VideoProjectApiRepository(this.api);

  final ApiClient api;

  String _collection(String workspaceId) =>
      'v1/workspaces/$workspaceId/video-projects';

  @override
  Future<VideoProjectListing> list(String workspaceId) async {
    final response = await api.get(_collection(workspaceId));
    return parseVideoProjectListing(response);
  }

  @override
  Future<VideoProject> create(String workspaceId, {String? name}) async {
    final response = await api.post(
      _collection(workspaceId),
      body: {'name': ?name},
    );
    return VideoProject.fromJson(asJsonMap(response['data']));
  }

  @override
  Future<VideoProject> read(String workspaceId, String projectId) async {
    final response = await api.get(
      '${_collection(workspaceId)}/${Uri.encodeComponent(projectId)}',
    );
    return VideoProject.fromJson(asJsonMap(response['project']));
  }

  @override
  Future<VideoProject> save({
    required String workspaceId,
    required String projectId,
    required JsonMap timeline,
    required List<VideoProjectMediaRecord> media,
    required String change,
    required int revision,
    String? name,
    String? renderJobId,
    bool clearRenderJob = false,
  }) async {
    try {
      final response = await api.put(
        '${_collection(workspaceId)}/${Uri.encodeComponent(projectId)}',
        body: {
          'timeline': timeline,
          'media': [for (final entry in media) entry.toJson()],
          'change': change,
          'revision': revision,
          'name': ?name,
          if (clearRenderJob || renderJobId != null) 'renderJobId': renderJobId,
        },
      );
      return VideoProject.fromJson(asJsonMap(response['data']));
    } on ApiFailure catch (error) {
      if (error.code == 'video_project_changed_elsewhere') {
        throw const VideoProjectConflict();
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String workspaceId, String projectId) async {
    await api.delete(
      '${_collection(workspaceId)}/${Uri.encodeComponent(projectId)}',
    );
  }
}

VideoProjectListing parseVideoProjectListing(JsonMap response) =>
    VideoProjectListing(
      projects: [
        for (final entry in response['projects'] as List<Object?>? ?? const [])
          VideoProjectSummary.fromJson(asJsonMap(entry)),
      ],
      renderCapability: EditorRenderCapability.fromJson(
        asJsonMap(response['renderCapability']),
      ),
    );
