import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/video_project.dart';
import 'package:ii_os/repositories/generation_history_repository.dart';
import 'package:ii_os/repositories/media_repository.dart';
import 'package:ii_os/repositories/source_asset_repository.dart';
import 'package:ii_os/services/artifact_read_url_cache.dart';
import 'package:ii_os/services/editor_media_source.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/services/video_editor_project.dart';
import 'package:ii_os/services/video_project_media_gateway.dart';

void main() {
  test('publish and restore preserve decoded linked-stream timing', () async {
    final bytes = Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...'ftypisom'.codeUnits,
    ]).asUnmodifiableView();
    final sourceAssets = _SourceAssets();
    final workspaceMedia = _WorkspaceMedia(bytes);
    final gateway = WorkspaceVideoProjectMediaGateway(
      sourceAssets: sourceAssets,
      media: workspaceMedia,
    );
    final local = LocalEditorMedia(
      id: 'linked-offset',
      filename: 'linked-offset.mov',
      path: '/picked/linked-offset.mov',
      bytes: bytes,
      contentType: 'video/mp4',
      duration: const Duration(seconds: 2),
      hasVideo: true,
      hasAudio: true,
      videoTiming: const VideoProjectStreamTiming(
        presentationStart: Duration.zero,
        duration: Duration(seconds: 2),
      ),
      audioTiming: const VideoProjectStreamTiming(
        presentationStart: Duration(milliseconds: 175),
        duration: Duration(milliseconds: 1825),
      ),
      width: 320,
      height: 180,
    );

    final published = await gateway.publish(
      workspaceId: 'workspace-1',
      expectedBucket: 'workspace-bucket',
      media: [local],
    );
    final saved = VideoProjectMediaRecord.fromJson(
      (jsonDecode(jsonEncode(published.single.toJson())) as Map)
          .cast<String, Object?>(),
    );
    final restored = await gateway.restore(
      workspaceId: 'workspace-1',
      expectedBucket: 'workspace-bucket',
      media: [saved],
    );

    expect(sourceAssets.uploadCount, 1);
    expect(workspaceMedia.sourceReadCount, 1);
    expect(workspaceMedia.lastAssetId, 'asset-linked-offset');
    expect(saved.videoTiming, local.videoTiming);
    expect(saved.audioTiming, local.audioTiming);
    expect(restored.single.videoTiming, local.videoTiming);
    expect(restored.single.audioTiming, local.audioTiming);
    expect(restored.single.bytes, orderedEquals(bytes));

    final legacyJson = published.single.toJson()
      ..remove('videoTiming')
      ..remove('audioTiming');
    final legacy = VideoProjectMediaRecord.fromJson(legacyJson);
    final backfilled = await gateway.publish(
      workspaceId: 'workspace-1',
      expectedBucket: 'workspace-bucket',
      media: [local],
      alreadyStored: {local.id: legacy},
    );
    expect(sourceAssets.uploadCount, 1);
    expect(backfilled.single.origin, same(legacy.origin));
    expect(backfilled.single.videoTiming, local.videoTiming);
    expect(backfilled.single.audioTiming, local.audioTiming);

    final project = addLocalMediaToNewLanes(
      projectId: 'round-trip-project',
      project: null,
      media: restored.single,
      videoLaneId: 'video-lane',
      audioLaneId: 'audio-lane',
      videoClipId: 'video-clip',
      audioClipId: 'audio-clip',
      linkGroupId: 'linked-pair',
      videoBitrate: 100000,
      browserOutput: true,
    );
    expect(project.clipById('video-clip')!.timelineStart, MediaTime.zero);
    expect(
      project.clipById('audio-clip')!.timelineStart,
      MediaTime.milliseconds(175),
    );
    expect(
      (project.clipById('audio-clip')! as EditorAudioClip).sourceRange.start,
      MediaTime.zero,
    );
  });

  test('legacy over-target media remains restorable for repair', () async {
    final bytes = Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...'ftypisom'.codeUnits,
    ]).asUnmodifiableView();
    final duration = maxEditorDuration + const Duration(seconds: 1);
    final gateway = WorkspaceVideoProjectMediaGateway(
      sourceAssets: _SourceAssets(),
      media: _WorkspaceMedia(bytes),
    );
    final restored = await gateway.restore(
      workspaceId: 'workspace-1',
      expectedBucket: 'workspace-bucket',
      media: [
        VideoProjectMediaRecord(
          id: 'legacy-long',
          filename: 'legacy-long.mov',
          contentType: 'video/mp4',
          byteLength: bytes.length,
          duration: duration,
          hasVideo: true,
          hasAudio: false,
          origin: const WorkspaceSourceAssetOrigin('asset-legacy-long'),
        ),
        VideoProjectMediaRecord(
          id: 'decoded-long',
          filename: 'decoded-long.mov',
          contentType: 'video/mp4',
          byteLength: bytes.length,
          duration: duration,
          hasVideo: true,
          hasAudio: false,
          videoTiming: VideoProjectStreamTiming(
            presentationStart: Duration.zero,
            duration: duration,
          ),
          origin: const WorkspaceSourceAssetOrigin('asset-decoded-long'),
        ),
      ],
    );

    expect(restored, hasLength(2));
    for (final media in restored) {
      expect(media.duration, duration);
      expect(media.videoTiming!.presentationStart, Duration.zero);
      expect(media.videoTiming!.duration, duration);
    }
  });
}

final class _SourceAssets implements SourceAssetRepository {
  int uploadCount = 0;

  @override
  Future<String> upload({
    required String workspaceId,
    required String filename,
    required Uint8List bytes,
    required String contentType,
    required String expectedBucket,
    bool ghostMode = false,
  }) async {
    uploadCount += 1;
    expect(workspaceId, 'workspace-1');
    expect(filename, 'linked-offset.mov');
    expect(contentType, 'video/mp4');
    expect(expectedBucket, 'workspace-bucket');
    expect(ghostMode, isFalse);
    return 'asset-linked-offset';
  }
}

final class _WorkspaceMedia implements WorkspaceMediaRepository {
  _WorkspaceMedia(this.bytes);

  final Uint8List bytes;
  int sourceReadCount = 0;
  String? lastAssetId;

  @override
  GenerationHistoryRepository history({
    required String workspaceId,
    required int retentionDays,
  }) => throw UnimplementedError();

  @override
  Future<VerifiedArtifactMedia> readVerifiedArtifact({
    required String workspaceId,
    required String jobId,
    required String expectedBucket,
    required JsonMap artifact,
    bool transient = false,
  }) => throw UnimplementedError();

  @override
  Future<VerifiedArtifactMedia> readVerifiedSourceAsset({
    required String workspaceId,
    required String assetId,
    required String expectedBucket,
  }) async {
    sourceReadCount += 1;
    lastAssetId = assetId;
    expect(workspaceId, 'workspace-1');
    expect(expectedBucket, 'workspace-bucket');
    return VerifiedArtifactMedia(
      identity: ArtifactAuthorizationIdentity(
        workspaceId: workspaceId,
        jobId: 'source-asset:$assetId',
        bucket: expectedBucket,
        objectName: 'workspaces/$workspaceId/source-assets/$assetId/source.mov',
        generation: '1',
        sizeBytes: bytes.length,
        sha256: List.filled(64, 'a').join(),
        contentType: 'video/mp4',
      ),
      filename: 'source.mov',
      detectedContentType: 'video/mp4',
      bytes: bytes,
    );
  }
}
