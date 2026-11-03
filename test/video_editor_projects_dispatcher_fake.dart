part of 'video_editor_projects_view_model_test.dart';

final class _FakeDispatcher implements EditorRenderDispatcher {
  _FakeDispatcher({this.failure});

  final Object? failure;
  int dispatches = 0;
  Map<String, VideoProjectMediaOrigin>? sawOrigins;

  @override
  Future<String> dispatch({
    required String workspaceId,
    required String expectedBucket,
    required EditorProject timeline,
    Map<String, VideoProjectMediaOrigin> origins = const {},
    bool ghostMode = false,
  }) async {
    if (failure != null) throw failure!;
    dispatches++;
    sawOrigins = origins;
    return 'job-1';
  }
}
