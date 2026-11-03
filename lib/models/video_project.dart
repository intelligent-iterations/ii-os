import 'models.dart';

/// Where a project's media lives in the workspace once the project is saved.
sealed class VideoProjectMediaOrigin {
  const VideoProjectMediaOrigin();

  static VideoProjectMediaOrigin fromJson(JsonMap json) =>
      switch (json['kind']) {
        'artifact' => WorkspaceArtifactOrigin(
          jobId: '${json['jobId']}',
          path: '${json['path']}',
          generation: '${json['generation']}',
          sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
          sha256: '${json['sha256']}',
          contentType: '${json['contentType']}',
        ),
        _ => WorkspaceSourceAssetOrigin('${json['assetId']}'),
      };

  JsonMap toJson();
}

/// A copy of the media that belongs to the project itself.
final class WorkspaceSourceAssetOrigin extends VideoProjectMediaOrigin {
  const WorkspaceSourceAssetOrigin(this.assetId);

  final String assetId;

  @override
  JsonMap toJson() => {'kind': 'sourceAsset', 'assetId': assetId};
}

/// Media the project holds where the job that generated it already put it.
///
/// The project does not take a copy. It holds this record, which is what stops
/// the organization's retention window from counting down on it.
final class WorkspaceArtifactOrigin extends VideoProjectMediaOrigin {
  const WorkspaceArtifactOrigin({
    required this.jobId,
    required this.path,
    required this.generation,
    required this.sizeBytes,
    required this.sha256,
    required this.contentType,
  });

  final String jobId;
  final String path;
  final String generation;
  final int sizeBytes;
  final String sha256;
  final String contentType;

  /// The shape the media repository verifies bytes against.
  JsonMap get artifact => {
    'path': path,
    'generation': generation,
    'size_bytes': sizeBytes,
    'sha256': sha256,
    'content_type': contentType,
  };

  @override
  JsonMap toJson() => {
    'kind': 'artifact',
    'jobId': jobId,
    'path': path,
    'generation': generation,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'contentType': contentType,
  };
}

/// The decoded interval occupied by one stream in a saved media source.
final class VideoProjectStreamTiming {
  const VideoProjectStreamTiming({
    required this.presentationStart,
    required this.duration,
  });

  factory VideoProjectStreamTiming.fromJson(JsonMap json) {
    if (json.length != 2 ||
        !json.containsKey('presentationStartMicros') ||
        !json.containsKey('durationMicros')) {
      throw const FormatException('Invalid saved media stream timing.');
    }
    final timing = VideoProjectStreamTiming(
      presentationStart: Duration(
        microseconds: _savedTimingInt(json, 'presentationStartMicros'),
      ),
      duration: Duration(microseconds: _savedTimingInt(json, 'durationMicros')),
    );
    if (timing.presentationStart < Duration.zero ||
        timing.duration <= Duration.zero) {
      throw const FormatException('Invalid saved media stream timing.');
    }
    return timing;
  }

  /// This stream's start relative to the source's earliest presentation time.
  ///
  /// Editor source ranges remain local to the first decoded frame or sample;
  /// this value derives only the linked stream's timeline offset.
  final Duration presentationStart;
  final Duration duration;

  Duration get presentationEnd => presentationStart + duration;

  JsonMap toJson() => {
    'presentationStartMicros': presentationStart.inMicroseconds,
    'durationMicros': duration.inMicroseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is VideoProjectStreamTiming &&
      presentationStart == other.presentationStart &&
      duration == other.duration;

  @override
  int get hashCode => Object.hash(presentationStart, duration);
}

/// One piece of media a saved project needs before it can be opened.
final class VideoProjectMediaRecord {
  const VideoProjectMediaRecord({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.byteLength,
    required this.duration,
    required this.hasVideo,
    required this.hasAudio,
    required this.origin,
    this.videoTiming,
    this.audioTiming,
    this.width,
    this.height,
  });

  factory VideoProjectMediaRecord.fromJson(JsonMap json) {
    final savedDuration = json['durationMicros'];
    final duration = Duration(microseconds: _int(savedDuration));
    final hasVideo = json['hasVideo'] == true;
    final hasAudio = json['hasAudio'] == true;
    final videoTiming = _savedStreamTiming(json, 'videoTiming');
    final audioTiming = _savedStreamTiming(json, 'audioTiming');
    final timings = [?videoTiming, ?audioTiming];
    final hasDecodedTiming = timings.isNotEmpty;
    final hasCompleteDecodedTiming =
        (!hasVideo || videoTiming != null) &&
        (!hasAudio || audioTiming != null);
    final decodedOrigin = hasDecodedTiming
        ? timings
              .map((timing) => timing.presentationStart)
              .reduce((left, right) => left < right ? left : right)
        : null;
    final decodedEnd = hasDecodedTiming
        ? timings
              .map((timing) => timing.presentationEnd)
              .reduce((left, right) => left > right ? left : right)
        : null;
    if ((!hasVideo && videoTiming != null) ||
        (!hasAudio && audioTiming != null) ||
        (hasDecodedTiming &&
            (savedDuration is! int ||
                !hasCompleteDecodedTiming ||
                decodedOrigin != Duration.zero ||
                decodedEnd != duration))) {
      throw const FormatException('Invalid saved media stream timing.');
    }
    return VideoProjectMediaRecord(
      id: '${json['id']}',
      filename: '${json['filename']}',
      contentType: '${json['contentType']}',
      byteLength: _int(json['byteLength']),
      duration: duration,
      hasVideo: hasVideo,
      hasAudio: hasAudio,
      videoTiming: videoTiming,
      audioTiming: audioTiming,
      width: json['width'] is num ? (json['width']! as num).toInt() : null,
      height: json['height'] is num ? (json['height']! as num).toInt() : null,
      origin: VideoProjectMediaOrigin.fromJson(asJsonMap(json['origin'])),
    );
  }

  final String id;
  final String filename;
  final String contentType;
  final int byteLength;
  final Duration duration;
  final bool hasVideo;
  final bool hasAudio;
  final VideoProjectStreamTiming? videoTiming;
  final VideoProjectStreamTiming? audioTiming;
  final int? width;
  final int? height;
  final VideoProjectMediaOrigin origin;

  JsonMap toJson() => {
    'id': id,
    'filename': filename,
    'contentType': contentType,
    'byteLength': byteLength,
    'durationMicros': duration.inMicroseconds,
    'hasVideo': hasVideo,
    'hasAudio': hasAudio,
    if (videoTiming case final timing?) 'videoTiming': timing.toJson(),
    if (audioTiming case final timing?) 'audioTiming': timing.toJson(),
    'width': ?width,
    'height': ?height,
    'origin': origin.toJson(),
  };
}

/// One line of a project's history: what changed, when, and who changed it.
final class VideoProjectChange {
  const VideoProjectChange({
    required this.at,
    required this.by,
    required this.description,
    this.revision,
  });

  factory VideoProjectChange.fromJson(JsonMap json) => VideoProjectChange(
    at: DateTime.tryParse('${json['at']}')?.toLocal() ?? DateTime(1970),
    by: '${json['by']}',
    description: '${json['description']}',
    revision: json['revision'] is num
        ? (json['revision']! as num).toInt()
        : null,
  );

  final DateTime at;
  final String by;
  final String description;
  final int? revision;
}

/// What the project list shows without reading a whole timeline.
final class VideoProjectSummary {
  const VideoProjectSummary({
    required this.id,
    required this.name,
    required this.duration,
    required this.clipCount,
    required this.mediaCount,
    required this.revision,
    required this.updatedAt,
    required this.updatedBy,
    this.renderJobId,
  });

  factory VideoProjectSummary.fromJson(JsonMap json) => VideoProjectSummary(
    id: '${json['id']}',
    name: '${json['name']}',
    duration: Duration(microseconds: _int(json['durationMicros'])),
    clipCount: _int(json['clipCount']),
    mediaCount: _int(json['mediaCount']),
    revision: _int(json['revision']),
    updatedAt:
        DateTime.tryParse('${json['updatedAt']}')?.toLocal() ?? DateTime(1970),
    updatedBy: '${json['updatedBy']}',
    renderJobId: json['renderJobId'] is String && json['renderJobId'] != ''
        ? json['renderJobId']! as String
        : null,
  );

  final String id;
  final String name;
  final Duration duration;
  final int clipCount;
  final int mediaCount;
  final int revision;
  final DateTime updatedAt;
  final String updatedBy;

  /// The job rendering this project on a workspace machine, if one is.
  ///
  /// It lives on the project rather than in the tab that started it, so
  /// closing the tab does not lose track of work that outlives it.
  final String? renderJobId;

  bool get isEmpty => clipCount == 0;
}

enum EditorRenderCapabilityStatus { unknown, unavailable, available }

/// Whether the control plane found a compatible connected render route.
final class EditorRenderCapability {
  const EditorRenderCapability(this.status);

  const EditorRenderCapability.available()
    : status = EditorRenderCapabilityStatus.available;

  factory EditorRenderCapability.fromJson(JsonMap json) =>
      EditorRenderCapability(switch (json['status']) {
        'available' => EditorRenderCapabilityStatus.available,
        'unavailable' => EditorRenderCapabilityStatus.unavailable,
        _ => EditorRenderCapabilityStatus.unknown,
      });

  final EditorRenderCapabilityStatus status;

  bool get isAvailable => status == EditorRenderCapabilityStatus.available;
}

/// Saved projects and the server-owned render capability discovered with them.
final class VideoProjectListing {
  const VideoProjectListing({
    required this.projects,
    required this.renderCapability,
  });

  final List<VideoProjectSummary> projects;
  final EditorRenderCapability renderCapability;
}

/// A saved project, with everything needed to put it back on screen.
final class VideoProject {
  const VideoProject({
    required this.summary,
    required this.timeline,
    required this.media,
    required this.history,
  });

  factory VideoProject.fromJson(JsonMap json) => VideoProject(
    summary: VideoProjectSummary.fromJson(json),
    timeline: asJsonMap(json['timeline']),
    media: [
      for (final entry in json['media'] as List<Object?>? ?? const [])
        VideoProjectMediaRecord.fromJson(asJsonMap(entry)),
    ],
    history: [
      for (final entry in json['history'] as List<Object?>? ?? const [])
        VideoProjectChange.fromJson(asJsonMap(entry)),
    ],
  );

  final VideoProjectSummary summary;
  final JsonMap timeline;
  final List<VideoProjectMediaRecord> media;
  final List<VideoProjectChange> history;

  String get id => summary.id;
  String get name => summary.name;
  int get revision => summary.revision;

  /// A project that has been created but never saved with a timeline.
  bool get isBlank => timeline.isEmpty;
}

int _int(Object? value) => value is num ? value.toInt() : 0;

int _savedTimingInt(JsonMap json, String key) {
  final value = json[key];
  if (value is! int) {
    throw const FormatException('Invalid saved media stream timing.');
  }
  return value;
}

VideoProjectStreamTiming? _savedStreamTiming(JsonMap json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! Map) {
    throw const FormatException('Invalid saved media stream timing.');
  }
  return VideoProjectStreamTiming.fromJson(asJsonMap(value));
}
