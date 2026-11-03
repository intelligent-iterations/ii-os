import 'dart:convert';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'workspace_store.dart';

const videoProjectCollection = 'videoProjects';
const videoProjectNameLimit = 80;
const videoProjectMediaLimit = 32;
const videoProjectHistoryLimit = 200;
const videoProjectLaneLimit = 24;
const videoProjectClipLimit = 256;
const videoProjectTimelineByteLimit = 512 * 1024;
const videoProjectRevisionKeepCount = 50;
const videoProjectListLimit = 100;

final _videoProjectUuid = Uuid();
final RegExp _mediaIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final RegExp _renderJobId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$');

/// The name a person gave the project, or a usable one if they gave none.
String validateVideoProjectName(Object? value) {
  if (value == null) return 'Untitled project';
  if (value is! String) {
    throw const ApiError(
      400,
      'invalid_video_project_name',
      'A project name must be text.',
    );
  }
  final name = value.trim();
  if (name.isEmpty) return 'Untitled project';
  if (name.length > videoProjectNameLimit) {
    throw const ApiError(
      400,
      'invalid_video_project_name',
      'A project name must be 80 characters or fewer.',
    );
  }
  return name;
}

/// Bounds the stored timeline. The editor decides whether a timeline is
/// coherent; this decides only whether it is small enough to keep.
Map<String, Object?> validateVideoProjectTimeline(Object? value) {
  if (value is! Map) {
    throw const ApiError(
      400,
      'invalid_video_project_timeline',
      'A project timeline is required.',
    );
  }
  final timeline = value.map((key, item) => MapEntry('$key', item));
  final encoded = jsonEncode(timeline);
  if (encoded.length > videoProjectTimelineByteLimit) {
    throw const ApiError(
      413,
      'video_project_timeline_too_large',
      'This timeline is too large to save. Remove some clips and try again.',
    );
  }
  final lanes = timeline['lanes'];
  if (lanes is! List || lanes.length > videoProjectLaneLimit) {
    throw const ApiError(
      400,
      'invalid_video_project_timeline',
      'A project timeline holds up to 24 lanes.',
    );
  }
  var clips = 0;
  for (final lane in lanes) {
    if (lane is! Map) {
      throw const ApiError(
        400,
        'invalid_video_project_timeline',
        'A project timeline lane is not readable.',
      );
    }
    final laneClips = lane['clips'];
    clips += laneClips is List ? laneClips.length : 0;
  }
  if (clips > videoProjectClipLimit) {
    throw const ApiError(
      400,
      'invalid_video_project_timeline',
      'A project timeline holds up to 256 clips.',
    );
  }
  return timeline;
}

/// Bounds the list of media a project needs to reopen.
List<Map<String, Object?>> validateVideoProjectMedia(Object? value) {
  if (value is! List || value.length > videoProjectMediaLimit) {
    throw const ApiError(
      400,
      'invalid_video_project_media',
      'A project refers to up to 32 pieces of media.',
    );
  }
  final media = <Map<String, Object?>>[];
  final ids = <String>{};
  for (final entry in value) {
    if (entry is! Map) {
      throw const ApiError(
        400,
        'invalid_video_project_media',
        'A media entry is not readable.',
      );
    }
    final item = entry.map((key, item) => MapEntry('$key', item));
    final id = item['id'];
    if (id is! String || !_mediaIdPattern.hasMatch(id) || !ids.add(id)) {
      throw const ApiError(
        400,
        'invalid_video_project_media',
        'A media entry has a missing or repeated identifier.',
      );
    }
    _requireText(item, 'filename', 200);
    _requireText(item, 'contentType', 100);
    _requireCount(item, 'byteLength');
    _requireCount(item, 'durationMicros');
    _requireStreamTiming(item, 'videoTiming', 'hasVideo');
    _requireStreamTiming(item, 'audioTiming', 'hasAudio');
    _requireStreamTimingEnvelope(item);
    _requireOrigin(item['origin']);
    media.add(item);
  }
  return media;
}

void _requireStreamTimingEnvelope(Map<String, Object?> item) {
  final video = item['videoTiming'];
  final audio = item['audioTiming'];
  if (video == null && audio == null) return;
  if ((item['hasVideo'] == true && video is! Map) ||
      (item['hasAudio'] == true && audio is! Map)) {
    throw const ApiError(
      400,
      'invalid_video_project_media',
      'A media entry has invalid decoded stream timing.',
    );
  }
  final timings = [video, audio].whereType<Map<Object?, Object?>>();
  final starts = timings
      .map<int>((timing) => timing['presentationStartMicros']! as int)
      .toList(growable: false);
  final ends = timings
      .map<int>(
        (timing) =>
            (timing['presentationStartMicros']! as int) +
            (timing['durationMicros']! as int),
      )
      .toList(growable: false);
  final parentDuration = item['durationMicros'];
  if (starts.reduce((left, right) => left < right ? left : right) != 0 ||
      ends.reduce((left, right) => left > right ? left : right) !=
          parentDuration) {
    throw const ApiError(
      400,
      'invalid_video_project_media',
      'A media entry has invalid decoded stream timing.',
    );
  }
}

void _requireStreamTiming(
  Map<String, Object?> item,
  String key,
  String streamFlag,
) {
  final value = item[key];
  if (value == null) return;
  final parentDuration = item['durationMicros'];
  if (item[streamFlag] != true ||
      parentDuration is! int ||
      value is! Map ||
      value.length != 2 ||
      !value.keys.every((entry) => entry is String) ||
      !value.containsKey('presentationStartMicros') ||
      !value.containsKey('durationMicros')) {
    throw const ApiError(
      400,
      'invalid_video_project_media',
      'A media entry has invalid decoded stream timing.',
    );
  }
  final start = value['presentationStartMicros'];
  final duration = value['durationMicros'];
  if (start is! int ||
      duration is! int ||
      start < 0 ||
      duration <= 0 ||
      start + duration > parentDuration) {
    throw const ApiError(
      400,
      'invalid_video_project_media',
      'A media entry has invalid decoded stream timing.',
    );
  }
}

void _requireText(Map<String, Object?> item, String key, int limit) {
  final value = item[key];
  if (value is! String || value.trim().isEmpty || value.length > limit) {
    throw ApiError(
      400,
      'invalid_video_project_media',
      'A media entry is missing its $key.',
    );
  }
}

void _requireCount(Map<String, Object?> item, String key) {
  final value = item[key];
  if (value is! num || value < 0 || value > 1 << 40) {
    throw ApiError(
      400,
      'invalid_video_project_media',
      'A media entry has an out-of-range $key.',
    );
  }
}

void _requireOrigin(Object? value) {
  if (value is! Map) {
    throw const ApiError(
      400,
      'invalid_video_project_media',
      'A media entry must say where it lives in the workspace.',
    );
  }
  final origin = value.map((key, item) => MapEntry('$key', item));
  switch (origin['kind']) {
    case 'sourceAsset':
      _requireText(origin, 'assetId', 200);
    case 'artifact':
      _requireText(origin, 'jobId', 200);
      _requireText(origin, 'path', 900);
      _requireText(origin, 'generation', 100);
    default:
      throw const ApiError(
        400,
        'invalid_video_project_media',
        'A media entry names a kind of storage this workspace does not use.',
      );
  }
}

/// The job now rendering this project somewhere other than the browser.
///
/// Kept on the project so that closing the tab does not lose track of work
/// that outlives it: reopening the project finds the render still running.
String? validateVideoProjectRenderJob(Object? value) {
  if (value == null || value == '') return null;
  if (value is! String || !_renderJobId.hasMatch(value)) {
    throw const ApiError(
      400,
      'invalid_video_project_render_job',
      'A render job identity is invalid.',
    );
  }
  return value;
}

/// The description a person will read in the project's history.
String validateVideoProjectChange(Object? value) {
  if (value == null) return 'Saved the project';
  if (value is! String || value.trim().isEmpty || value.length > 200) {
    throw const ApiError(
      400,
      'invalid_video_project_change',
      'A change description must be short text.',
    );
  }
  return value.trim();
}

/// Keeps the newest [videoProjectHistoryLimit] entries and drops the rest.
List<Object?> boundedVideoProjectHistory(
  List<Object?> existing,
  Map<String, Object?> entry,
) {
  final history = [...existing, entry];
  if (history.length <= videoProjectHistoryLimit) return history;
  return history.sublist(history.length - videoProjectHistoryLimit);
}

/// What the project list shows without reading a whole timeline.
Map<String, Object?> videoProjectSummary(String id, Map<String, Object?> data) {
  return {
    'id': id,
    'name': data['name'],
    'durationMicros': data['durationMicros'] ?? 0,
    'clipCount': data['clipCount'] ?? 0,
    'mediaCount': (data['media'] as List<Object?>? ?? const []).length,
    'revision': data['revision'] ?? 0,
    'renderJobId': data['renderJobId'],
    'updatedBy': data['updatedBy'],
    'updatedAt': _isoTime(data['updatedAt']),
    'createdAt': _isoTime(data['createdAt']),
  };
}

Map<String, Object?> videoProjectDetail(String id, Map<String, Object?> data) {
  return {
    ...videoProjectSummary(id, data),
    'timeline': data['timeline'] ?? const <String, Object?>{},
    'media': data['media'] ?? const <Object?>[],
    'history': data['history'] ?? const <Object?>[],
  };
}

int videoProjectClipCount(Map<String, Object?> timeline) {
  var clips = 0;
  for (final lane in timeline['lanes'] as List<Object?>? ?? const []) {
    if (lane is! Map) continue;
    final laneClips = lane['clips'];
    clips += laneClips is List ? laneClips.length : 0;
  }
  return clips;
}

int videoProjectDurationMicros(Map<String, Object?> timeline) {
  final value = timeline['durationMicros'];
  return value is num ? value.toInt() : 0;
}

String _isoTime(Object? value) => switch (value) {
  Timestamp() => value.toDate().toUtc().toIso8601String(),
  String() => value,
  _ => DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String(),
};

extension WorkspaceVideoProjects on WorkspaceStore {
  Future<List<Map<String, Object?>>> listVideoProjects(
    String workspaceId,
  ) async {
    final snapshots = await firestore
        .collection(videoProjectCollection)
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .limit(videoProjectListLimit)
        .get();
    final projects = snapshots.docs
        .map((snapshot) => videoProjectSummary(snapshot.id, snapshot.data()))
        .toList();
    projects.sort(
      (left, right) => (right['updatedAt']! as String).compareTo(
        left['updatedAt']! as String,
      ),
    );
    return projects;
  }

  Future<Map<String, Object?>> getVideoProject(
    String workspaceId,
    String projectId,
  ) async {
    final snapshot = await firestore
        .collection(videoProjectCollection)
        .doc(projectId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId) {
      throw const ApiError(
        404,
        'video_project_not_found',
        'That project is not in this workspace.',
      );
    }
    return videoProjectDetail(snapshot.id, data);
  }

  Future<Map<String, Object?>> createVideoProject({
    required String workspaceId,
    required String createdBy,
    required Object? name,
  }) async {
    final projectId = _videoProjectUuid.v4();
    final now = Timestamp.now();
    final data = <String, Object?>{
      'workspaceId': workspaceId,
      'name': validateVideoProjectName(name),
      'timeline': <String, Object?>{},
      'media': <Object?>[],
      'history': <Object?>[
        {
          'at': now.toDate().toUtc().toIso8601String(),
          'by': createdBy,
          'description': 'Started the project',
        },
      ],
      'revision': 0,
      'renderJobId': null,
      'durationMicros': 0,
      'clipCount': 0,
      'createdBy': createdBy,
      'updatedBy': createdBy,
      'createdAt': now,
      'updatedAt': now,
    };
    await firestore
        .collection(videoProjectCollection)
        .doc(projectId)
        .create(data);
    return videoProjectDetail(projectId, data);
  }

  Future<Map<String, Object?>> saveVideoProject({
    required String workspaceId,
    required String projectId,
    required String updatedBy,
    required Map<String, Object?> body,
  }) async {
    final timeline = validateVideoProjectTimeline(body['timeline']);
    final media = validateVideoProjectMedia(body['media']);
    final change = validateVideoProjectChange(body['change']);
    final expected = body['revision'];
    final reference = firestore
        .collection(videoProjectCollection)
        .doc(projectId);
    late int revision;
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data();
      if (!snapshot.exists ||
          current == null ||
          current['workspaceId'] != workspaceId) {
        throw const ApiError(
          404,
          'video_project_not_found',
          'That project is not in this workspace.',
        );
      }
      final held = current['revision'] is num
          ? (current['revision']! as num).toInt()
          : 0;
      if (expected is num && expected.toInt() != held) {
        throw const ApiError(
          409,
          'video_project_changed_elsewhere',
          'Someone else saved this project while you were working. Reopen it '
              'to pick up their version.',
        );
      }
      revision = held + 1;
      final now = Timestamp.now();
      transaction.update(reference, {
        'timeline': timeline,
        'media': media,
        'durationMicros': videoProjectDurationMicros(timeline),
        'clipCount': videoProjectClipCount(timeline),
        'revision': revision,
        'updatedBy': updatedBy,
        'updatedAt': now,
        'history': boundedVideoProjectHistory(
          current['history'] as List<Object?>? ?? const [],
          {
            'at': now.toDate().toUtc().toIso8601String(),
            'by': updatedBy,
            'description': change,
            'revision': revision,
          },
        ),
        if (body.containsKey('name'))
          'name': validateVideoProjectName(body['name']),
        if (body.containsKey('renderJobId'))
          'renderJobId':
              validateVideoProjectRenderJob(body['renderJobId']) ??
              FieldValue.delete,
      });
    });
    await _writeVideoProjectRevision(
      reference: reference,
      revision: revision,
      timeline: timeline,
      media: media,
      updatedBy: updatedBy,
    );
    return getVideoProject(workspaceId, projectId);
  }

  Future<Map<String, Object?>> getVideoProjectRevision({
    required String workspaceId,
    required String projectId,
    required int revision,
  }) async {
    await getVideoProject(workspaceId, projectId);
    final snapshot = await firestore
        .collection(videoProjectCollection)
        .doc(projectId)
        .collection('revisions')
        .doc('$revision')
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const ApiError(
        404,
        'video_project_revision_not_found',
        'That version of the project is no longer kept.',
      );
    }
    return {
      'revision': revision,
      'timeline': data['timeline'] ?? const <String, Object?>{},
      'media': data['media'] ?? const <Object?>[],
    };
  }

  Future<void> deleteVideoProject(String workspaceId, String projectId) async {
    await getVideoProject(workspaceId, projectId);
    await firestore.collection(videoProjectCollection).doc(projectId).delete();
  }

  Future<void> _writeVideoProjectRevision({
    required DocumentReference<Map<String, Object?>> reference,
    required int revision,
    required Map<String, Object?> timeline,
    required List<Map<String, Object?>> media,
    required String updatedBy,
  }) async {
    final revisions = reference.collection('revisions');
    await revisions.doc('$revision').set({
      'timeline': timeline,
      'media': media,
      'updatedBy': updatedBy,
      'updatedAt': Timestamp.now(),
    });
    final expired = revision - videoProjectRevisionKeepCount;
    if (expired > 0) await revisions.doc('$expired').delete();
  }
}
