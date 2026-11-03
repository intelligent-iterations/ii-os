import 'app_controller.dart';

extension AppControllerGhost on AppController {
  Future<void> consumeGhostJob(String jobId) async {
    final workspaceId = workspace?.id ?? '';
    if (workspaceId.isEmpty || jobId.isEmpty) {
      throw const FormatException('The Ghost-mode generation is unavailable.');
    }
    await api.post(
      'v1/workspaces/$workspaceId/jobs/'
      '${Uri.encodeComponent(jobId)}/artifacts/consume',
    );
  }
}
