import 'package:crypto/crypto.dart';

import '../models/models.dart';
import '../models/storyboard.dart';
import '../state/app_controller.dart';
import '../widgets/storyboard_editor_components.dart';
import 'direct_gcs_write_grant.dart';
import 'video_last_frame_capture.dart';

const int maxStoryboardExtendFrameBytes = 25 * 1024 * 1024;

final class StoryboardPanelExtendService {
  StoryboardPanelExtendService({required this.controller});

  final AppController controller;

  Future<StoryboardModel> extendPanel({
    required String workspaceId,
    required String storyboardId,
    required String panelId,
    required StoryboardPanelDraft sourcePanel,
  }) async {
    final videoJobId = sourcePanel.videoJobId;
    final videoArtifact = sourcePanel.videoArtifact;
    if (videoJobId == null || videoArtifact == null) {
      throw const FormatException(
        'The selected panel has no generated video yet.',
      );
    }
    final video = await controller.readVerifiedArtifact(
      workspaceId: workspaceId,
      jobId: videoJobId,
      artifact: videoArtifact,
    );
    final frameBytes = await captureVideoLastFrame(
      video.bytes,
      contentType: video.detectedContentType,
    );
    if (frameBytes.length > maxStoryboardExtendFrameBytes) {
      throw const FormatException('The extracted frame is too large.');
    }
    final sha256Hex = sha256.convert(frameBytes).toString();
    final prepared = await controller.api.post(
      'v1/workspaces/$workspaceId/storyboards/$storyboardId/panels/'
      '$panelId/extend/prepare-upload',
      body: {
        'sourcePanelId': sourcePanel.id,
        'contentType': 'image/png',
        'sizeBytes': frameBytes.length,
        'sha256': sha256Hex,
      },
    );
    final preparedData = asJsonMap(prepared['data']);
    final jobId = preparedData['jobId'] as String? ?? '';
    final expectedObject =
        'workspaces/$workspaceId/runs/$jobId/extended-frame.png';
    final bucket = controller.connection?.bucket ?? '';
    if (jobId.isEmpty || bucket.isEmpty) {
      throw const FormatException('The extend upload grant is invalid.');
    }
    final grant = validateDirectGcsWriteGrant(
      data: preparedData,
      expectedBucket: bucket,
      expectedObject: expectedObject,
      expectedContentType: 'image/png',
      expectedSha256: sha256Hex,
    );
    await controller.api.putBytes(
      grant.uri,
      frameBytes,
      headers: grant.headers,
    );
    final completed = await controller.api.post(
      'v1/workspaces/$workspaceId/storyboards/$storyboardId/panels/'
      '$panelId/extend/complete',
      body: storyboardExtendCompletionBody(
        sourcePanelId: sourcePanel.id,
        jobId: jobId,
        sizeBytes: frameBytes.length,
        sha256: sha256Hex,
      ),
    );
    final completedData = asJsonMap(completed['data']);
    return StoryboardModel.fromJson(asJsonMap(completedData['storyboard']));
  }
}

JsonMap storyboardExtendCompletionBody({
  required String sourcePanelId,
  required String jobId,
  required int sizeBytes,
  required String sha256,
}) => {
  'sourcePanelId': sourcePanelId,
  'jobId': jobId,
  'sizeBytes': sizeBytes,
  'sha256': sha256,
};
