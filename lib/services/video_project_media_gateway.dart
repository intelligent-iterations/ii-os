import '../models/video_project.dart';
import '../repositories/media_repository.dart';
import '../repositories/source_asset_repository.dart';
import 'editor_media_source.dart';

/// Works out where a project's media lives, and brings it back.
///
/// Media generated in this workspace is already in the bucket, so a project
/// holds it where it is rather than taking a copy -- holding it is what stops
/// the organization's retention window counting down on it. Only media that
/// arrived from someone's own machine has nowhere else to live, and that is
/// the only thing this uploads.
abstract interface class VideoProjectMediaGateway {
  /// Returns what the saved project needs to find its media again, uploading
  /// only the pieces that are not in the workspace already.
  Future<List<VideoProjectMediaRecord>> publish({
    required String workspaceId,
    required String expectedBucket,
    required List<LocalEditorMedia> media,
    Map<String, VideoProjectMediaOrigin> knownOrigins = const {},
    Map<String, VideoProjectMediaRecord> alreadyStored = const {},
    bool ghostMode = false,
  });

  /// Brings a saved project's media back as editable bytes.
  Future<List<LocalEditorMedia>> restore({
    required String workspaceId,
    required String expectedBucket,
    required List<VideoProjectMediaRecord> media,
  });
}

/// Raised when a saved project's media can no longer be fetched.
final class VideoProjectMediaMissing implements Exception {
  const VideoProjectMediaMissing(this.filename);

  final String filename;
}

final class WorkspaceVideoProjectMediaGateway
    implements VideoProjectMediaGateway {
  const WorkspaceVideoProjectMediaGateway({
    required this.sourceAssets,
    required this.media,
  });

  final SourceAssetRepository sourceAssets;
  final WorkspaceMediaRepository media;

  @override
  Future<List<VideoProjectMediaRecord>> publish({
    required String workspaceId,
    required String expectedBucket,
    required List<LocalEditorMedia> media,
    Map<String, VideoProjectMediaOrigin> knownOrigins = const {},
    Map<String, VideoProjectMediaRecord> alreadyStored = const {},
    bool ghostMode = false,
  }) async {
    final records = <VideoProjectMediaRecord>[];
    for (final item in media) {
      final stored = alreadyStored[item.id];
      final origin = stored != null && stored.byteLength == item.bytes.length
          ? stored.origin
          : knownOrigins[item.id] ??
                WorkspaceSourceAssetOrigin(
                  await sourceAssets.upload(
                    workspaceId: workspaceId,
                    expectedBucket: expectedBucket,
                    filename: item.filename,
                    bytes: item.bytes,
                    contentType: item.contentType,
                    ghostMode: ghostMode,
                  ),
                );
      records.add(_mediaRecord(item, origin));
    }
    return records;
  }

  @override
  Future<List<LocalEditorMedia>> restore({
    required String workspaceId,
    required String expectedBucket,
    required List<VideoProjectMediaRecord> media,
  }) async {
    final restored = <LocalEditorMedia>[];
    for (final record in media) {
      final verified = switch (record.origin) {
        WorkspaceSourceAssetOrigin(:final assetId) =>
          await this.media.readVerifiedSourceAsset(
            workspaceId: workspaceId,
            assetId: assetId,
            expectedBucket: expectedBucket,
          ),
        final WorkspaceArtifactOrigin origin =>
          await this.media.readVerifiedArtifact(
            workspaceId: workspaceId,
            jobId: origin.jobId,
            expectedBucket: expectedBucket,
            artifact: origin.artifact,
          ),
      };
      if (verified.bytes.length != record.byteLength) {
        throw VideoProjectMediaMissing(record.filename);
      }
      restored.add(
        LocalEditorMedia(
          id: record.id,
          filename: record.filename,
          path: '',
          bytes: verified.bytes,
          contentType: record.contentType,
          duration: record.duration,
          hasVideo: record.hasVideo,
          hasAudio: record.hasAudio,
          videoTiming: record.videoTiming,
          audioTiming: record.audioTiming,
          width: record.width,
          height: record.height,
        ),
      );
    }
    return restored;
  }
}

VideoProjectMediaRecord _mediaRecord(
  LocalEditorMedia media,
  VideoProjectMediaOrigin origin,
) => VideoProjectMediaRecord(
  id: media.id,
  filename: media.filename,
  contentType: media.contentType,
  byteLength: media.bytes.length,
  duration: media.duration,
  hasVideo: media.hasVideo,
  hasAudio: media.hasAudio,
  videoTiming: media.videoTiming,
  audioTiming: media.audioTiming,
  width: media.width,
  height: media.height,
  origin: origin,
);
