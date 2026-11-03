import 'dart:convert';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'fleet_template.dart';
import 'retention.dart';
import 'retention_policy.dart';
import 'workflow_catalog.dart';
import 'workflow_source_references.dart';
import 'workspace_store.dart';

part 'job_public_view.dart';

final class JobListCursor {
  const JobListCursor({
    required this.orderedAt,
    required this.jobId,
    this.offset = 0,
  });

  factory JobListCursor.decode(String value) {
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(value))),
      );
      if (decoded is! Map) throw const FormatException();
      final orderedAt = DateTime.tryParse(decoded['at']?.toString() ?? '');
      final jobId = decoded['jobId']?.toString() ?? '';
      final offset = decoded['offset'] is num
          ? (decoded['offset'] as num).toInt()
          : 0;
      if (orderedAt == null ||
          jobId.isEmpty ||
          jobId.length > 200 ||
          offset < 0 ||
          offset > 10000) {
        throw const FormatException();
      }
      return JobListCursor(
        orderedAt: orderedAt.toUtc(),
        jobId: jobId,
        offset: offset,
      );
    } on Object {
      throw const ApiError(
        400,
        'invalid_job_cursor',
        'The job history cursor is invalid.',
      );
    }
  }

  final DateTime orderedAt;
  final String jobId;
  final int offset;

  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'at': orderedAt.toIso8601String(),
            'jobId': jobId,
            'offset': offset,
          }),
        ),
      )
      .replaceAll('=', '');
}

final class RecordedJobPage {
  const RecordedJobPage({
    required this.jobs,
    required this.hasMore,
    required this.nextCursor,
    required this.syncAfter,
  });

  final List<Map<String, Object?>> jobs;
  final bool hasMore;
  final String? nextCursor;
  final DateTime? syncAfter;

  Map<String, Object?> toJson({bool stale = false}) => {
    'jobs': jobs,
    'stale': stale,
    'hasMore': hasMore,
    'nextCursor': nextCursor,
    'syncAfter': syncAfter?.toUtc().toIso8601String(),
  };
}

extension WorkspaceJobRuns on WorkspaceStore {
  Future<({Map<String, Object?> job, bool created})> queueGitHubJob({
    required String workspaceId,
    required String organizationId,
    required String jobId,
    required WorkflowCatalog catalog,
    required WorkflowDefinition workflow,
    required Map<String, String> inputs,
    required Map<String, Object?>? promptEnhancement,
    Map<String, Object?>? generationSelection,
    Map<String, Object?>? retentionAttachment,
    Map<String, Object?>? generationReview,
    String? notificationDeepLink,
    required String createdBy,
    int retentionDays = defaultArtifactRetentionDays,
    bool ghostMode = false,
    Map<String, Object?>? runnerGrant,
  }) async {
    final now = Timestamp.now();
    final data = <String, Object?>{
      'workspaceId': workspaceId,
      if (organizationId.isNotEmpty) 'organizationId': organizationId,
      'jobId': jobId,
      'provider': 'github_actions',
      'kind': workflow.id,
      'workType': workflow.workType.name,
      'workflowKey': '${catalog.repository}#${workflow.id}',
      'workflowName': workflow.name,
      'generationMetadata': _generationMetadata(
        prompt: inputs['prompt'],
        model: workflow.model,
        workflowKey: '${catalog.repository}#${workflow.id}',
      ),
      'runtimeEstimate': ?workflow.runtimeEstimateFor(inputs),
      'promptEnhancement': promptEnhancement,
      'generationSelection': ?generationSelection,
      'retentionAttachment': ?retentionAttachment,
      'generationReview': ?generationReview,
      'notificationDeepLink': ?notificationDeepLink,
      'ghostMode': ghostMode,
      'runnerGrant': ?runnerGrant,
      'contractVersion': workflow.contractVersion,
      'repository': catalog.repository,
      'workflowPath': workflow.dispatchWorkflow,
      'workflowRef': catalog.ref,
      'catalogSha': catalog.sha,
      'inputs': inputs,
      'sourceAssetIds': workflowSourceReferences(
        inputs,
      ).map((reference) => reference.assetId).toList(growable: false),
      'status': 'dispatching',
      'githubStatus': null,
      'githubConclusion': null,
      'githubRunId': null,
      'githubRunAttempt': null,
      'githubUrl': null,
      'events': <Map<String, Object?>>[
        {'kind': 'dispatching', 'at': now},
      ],
      'artifacts': <Map<String, Object?>>[],
      'createdBy': createdBy,
      'createdAt': now,
      'submittedAt': now,
      'updatedAt': now,
      'expiresAt': _retentionTimestamp(ghostMode ? 1 : retentionDays),
      'bridgeManaged': false,
    };
    final ref = firestore.collection('jobRuns').doc(jobId);
    try {
      await ref.create(data);
    } on Object {
      final existing = await ref.get();
      final existingData = existing.data();
      if (!existing.exists ||
          existingData == null ||
          existingData['workspaceId'] != workspaceId ||
          existingData['createdBy'] != createdBy ||
          existingData['workflowKey'] != data['workflowKey']) {
        throw const ApiError(
          409,
          'job_request_conflict',
          'A different job already uses this request identity.',
        );
      }
      return (job: _publicJob(existingData), created: false);
    }
    return (job: _publicJob(data), created: true);
  }

  Future<Map<String, Object?>> markGitHubJobDispatched(
    String workspaceId,
    String jobId,
  ) => _updateGitHubJob(
    workspaceId,
    jobId,
    status: 'dispatched',
    values: {'dispatchedAt': Timestamp.now()},
  );

  Future<void> markGitHubJobDispatchFailed(
    String workspaceId,
    String jobId,
    String errorCode,
  ) async {
    await _updateGitHubJob(
      workspaceId,
      jobId,
      status: 'failed',
      values: {'errorCode': errorCode},
    );
  }

  Future<Map<String, Object?>> updateGitHubJobRun(
    String workspaceId,
    String jobId, {
    required int runId,
    required int runAttempt,
    required String status,
    required String githubStatus,
    required String? conclusion,
    required String url,
  }) => _updateGitHubJob(
    workspaceId,
    jobId,
    status: status,
    values: {
      'githubRunId': runId,
      'githubRunAttempt': runAttempt,
      'githubStatus': githubStatus,
      'githubConclusion': conclusion,
      'githubUrl': url,
      'errorCode': FieldValue.delete,
      'workflowResult': FieldValue.delete,
    },
  );

  Future<List<Map<String, Object?>>> listGitHubJobsToReconcile(
    String workspaceId,
  ) async {
    const targetLimit = 20;
    const scanPageSize = 50;
    final query = firestore
        .collection('jobRuns')
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .orderBy('createdAt', descending: true);
    final pending = <Map<String, Object?>>[];
    QueryDocumentSnapshot<Map<String, Object?>>? cursor;
    while (pending.length < targetLimit) {
      var pageQuery = query.limit(scanPageSize);
      if (cursor != null) {
        pageQuery = pageQuery.startAfterDocument(cursor);
      }
      final snapshots = await pageQuery.get();
      if (snapshots.docs.isEmpty) break;
      for (final snapshot in snapshots.docs) {
        final data = snapshot.data();
        if (githubJobNeedsReconciliation(
          data,
          retentionExpired: recordRetentionExpired(data),
        )) {
          pending.add(data);
          if (pending.length == targetLimit) break;
        }
      }
      if (snapshots.docs.length < scanPageSize) break;
      cursor = snapshots.docs.last;
    }
    return pending;
  }

  Future<Map<String, Object?>> requestGitHubJobCancellation(
    String workspaceId,
    String jobId,
  ) async {
    final ref = firestore.collection('jobRuns').doc(jobId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId ||
        recordRetentionExpired(data)) {
      throw const ApiError(404, 'job_not_found', 'Job not found.');
    }
    if (data['provider'] != 'github_actions') {
      throw const ApiError(
        409,
        'job_not_cancellable',
        'This job cannot be cancelled through GitHub Actions.',
      );
    }
    if (_githubTerminalStatuses.contains(data['status'])) {
      throw const ApiError(
        409,
        'job_not_cancellable',
        'This job has already finished.',
      );
    }
    if (data['cancelRequestedAt'] != null) return _publicJob(data);

    final now = Timestamp.now();
    final events =
        (data['events'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .toList()
          ..add({'kind': 'cancelling', 'at': now});
    await ref.update({
      'status': 'cancelling',
      'cancelRequestedAt': now,
      'events': events,
      'updatedAt': now,
    });
    return getRecordedJob(workspaceId, jobId);
  }

  Future<Map<String, Object?>> expireUnobservedGitHubJob({
    required String workspaceId,
    required String jobId,
    required String errorCode,
  }) async {
    final ref = firestore.collection('jobRuns').doc(jobId);
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data == null ||
          data['workspaceId'] != workspaceId ||
          data['jobId'] != jobId ||
          data['provider'] != 'github_actions') {
        throw const ApiError(404, 'job_not_found', 'Job not found.');
      }
      if (_githubTerminalStatuses.contains(data['status'])) return;

      final cancelled = data['cancelRequestedAt'] != null;
      final status = cancelled ? 'cancelled' : 'failed';
      final conclusion = cancelled ? 'cancelled' : 'failure';
      final now = Timestamp.now();
      final events =
          (data['events'] as List<Object?>? ?? const [])
              .whereType<Map<String, Object?>>()
              .toList()
            ..add({'kind': status, 'errorCode': errorCode, 'at': now});
      transaction.update(ref, {
        'status': status,
        'githubStatus': 'completed',
        'githubConclusion': conclusion,
        'errorCode': errorCode,
        'workflowResult': {
          'reportedBy': 'ii-os-reconciler',
          'status': status,
          'errorCode': errorCode,
          'completedAt': now,
        },
        'events': events,
        'completedAt': now,
        'updatedAt': now,
      });
    });
    return getRecordedJob(workspaceId, jobId);
  }

  Future<Map<String, Object?>> _updateGitHubJob(
    String workspaceId,
    String jobId, {
    required String status,
    required Map<String, Object?> values,
  }) async {
    final ref = firestore.collection('jobRuns').doc(jobId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId ||
        recordRetentionExpired(data) ||
        data['provider'] != 'github_actions') {
      throw const ApiError(404, 'job_not_found', 'Job not found.');
    }
    final resolvedStatus =
        data['cancelRequestedAt'] != null &&
            !_githubTerminalStatuses.contains(status)
        ? 'cancelling'
        : status;
    final events = (data['events'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    if (data['status'] != resolvedStatus) {
      events.add({'kind': resolvedStatus, 'at': Timestamp.now()});
    }
    await ref.update({
      ...values,
      'status': resolvedStatus,
      'events': events,
      'updatedAt': Timestamp.now(),
    });
    return getRecordedJob(workspaceId, jobId);
  }

  Future<Map<String, Object?>> queueJob({
    required String workspaceId,
    required FleetBuiltJob built,
    required String createdBy,
    int retentionDays = defaultArtifactRetentionDays,
  }) async {
    final now = Timestamp.now();
    final data = <String, Object?>{
      'workspaceId': workspaceId,
      'jobId': built.jobId,
      'leaseId': null,
      'kind': built.templateId,
      'templateVersion': built.templateVersion,
      'inputs': built.normalizedInput,
      'generationMetadata': _generationMetadata(
        prompt: built.normalizedInput['prompt'],
        model: built.model,
        workflowKey: built.templateId,
      ),
      'status': 'queued',
      'fleetStatus': null,
      'fleetRequest': built.request,
      'events': <Map<String, Object?>>[],
      'artifacts': <Map<String, Object?>>[],
      'createdBy': createdBy,
      'createdAt': now,
      'updatedAt': now,
      'expiresAt': _retentionTimestamp(retentionDays),
      'bridgeAttempts': 0,
      'bridgeManaged': true,
    };
    final ref = firestore.collection('jobRuns').doc(built.jobId);
    try {
      await ref.create(data);
    } on Object {
      final existing = await ref.get();
      final existingData = existing.data();
      if (!existing.exists ||
          existingData == null ||
          existingData['workspaceId'] != workspaceId ||
          existingData['createdBy'] != createdBy) {
        throw const ApiError(
          409,
          'job_request_conflict',
          'A different job already uses this request identity.',
        );
      }
      return _publicJob(existingData);
    }
    return _publicJob(data);
  }

  Future<Map<String, Object?>> recordClientExtractedFrameJob({
    required String workspaceId,
    required String jobId,
    required String sourcePanelId,
    required String sourceVideoJobId,
    required Map<String, Object?> artifact,
    required String createdBy,
    int retentionDays = defaultArtifactRetentionDays,
  }) async {
    const workflowKey = 'client#video-frame-extract';
    final now = Timestamp.now();
    final data = <String, Object?>{
      'workspaceId': workspaceId,
      'jobId': jobId,
      'provider': 'client_frame_extract',
      'kind': 'video-frame-extract',
      'workflowKey': workflowKey,
      'workflowName': 'Extend from panel (last frame)',
      'generationMetadata': _generationMetadata(
        prompt: '',
        model: 'ffmpeg-local',
        workflowKey: workflowKey,
      ),
      'inputs': {
        'sourcePanelId': sourcePanelId,
        'sourceVideoJobId': sourceVideoJobId,
      },
      'status': 'completed',
      'events': <Map<String, Object?>>[
        {'kind': 'completed', 'at': now},
      ],
      'artifacts': <Map<String, Object?>>[artifact],
      'createdBy': createdBy,
      'createdAt': now,
      'submittedAt': now,
      'completedAt': now,
      'updatedAt': now,
      'expiresAt': _retentionTimestamp(retentionDays),
      'bridgeManaged': false,
    };
    final ref = firestore.collection('jobRuns').doc(jobId);
    try {
      await ref.create(data);
    } on Object {
      final existing = await ref.get();
      final existingData = existing.data();
      if (!existing.exists ||
          existingData == null ||
          existingData['workspaceId'] != workspaceId ||
          existingData['createdBy'] != createdBy ||
          existingData['workflowKey'] != workflowKey) {
        throw const ApiError(
          409,
          'job_request_conflict',
          'A different job already uses this request identity.',
        );
      }
      return _publicJob(existingData);
    }
    return _publicJob(data);
  }

  Future<Map<String, Object?>> getRecordedJob(
    String workspaceId,
    String jobId,
  ) async => (await readRecordedJob(workspaceId, jobId)).job;

  /// The public job plus the record behind it, from a single read.
  ///
  /// The read-url path needs both: the public shape to answer with, and the
  /// stored retention fields to decide whether opening this media should push
  /// its window out. Returning them together keeps a playback at one read.
  Future<({Map<String, Object?> job, Map<String, Object?> record})>
  readRecordedJob(String workspaceId, String jobId) async {
    final snapshot = await firestore.collection('jobRuns').doc(jobId).get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId ||
        recordRetentionExpired(data)) {
      throw const ApiError(404, 'job_not_found', 'Job not found.');
    }
    return (job: _publicJob(data), record: data);
  }

  /// Records that someone opened this media, and starts its window again.
  ///
  /// Media something still holds has no window to restart, and a play within
  /// [artifactPlayRefreshInterval] of the last one writes nothing, so this
  /// costs at most one write per piece of media per day.
  Future<void> recordArtifactPlay({
    required String jobId,
    required Map<String, Object?> record,
    required int retentionDays,
  }) async {
    final expiry = refreshedArtifactExpiry(
      data: record,
      retentionDays: retentionDays,
    );
    if (expiry == null) return;
    await firestore.collection('jobRuns').doc(jobId).update({
      'expiresAt': expiry,
      'lastPlayedAt': Timestamp.now(),
    });
  }

  Future<RecordedJobPage> listRecordedJobsPage(
    String workspaceId, {
    int limit = 50,
    JobListCursor? cursor,
  }) {
    return _listRecordedJobPage(
      workspaceId,
      orderedField: 'createdAt',
      descending: true,
      limit: limit,
      cursor: cursor,
    );
  }

  Future<RecordedJobPage> listRecordedJobChanges(
    String workspaceId, {
    required DateTime changesSince,
    int limit = 50,
    JobListCursor? cursor,
  }) {
    return _listRecordedJobPage(
      workspaceId,
      orderedField: 'updatedAt',
      descending: false,
      limit: limit,
      cursor: cursor,
      after: changesSince,
    );
  }

  Future<RecordedJobPage> _listRecordedJobPage(
    String workspaceId, {
    required String orderedField,
    required bool descending,
    required int limit,
    required JobListCursor? cursor,
    DateTime? after,
  }) async {
    final collection = firestore.collection('jobRuns');
    var query = collection
        .where('workspaceId', WhereFilter.equal, workspaceId)
        .orderBy(orderedField, descending: descending)
        .orderByFieldPath(FieldPath.documentId, descending: descending);
    if (after != null) {
      query = query.where(
        orderedField,
        WhereFilter.greaterThan,
        Timestamp.fromDate(after.toUtc()),
      );
    }
    if (cursor != null && cursor.offset > 0) {
      query = query.offset(cursor.offset);
    }
    // The Firestore REST stream may omit its terminal readTime. Capture a
    // lower bound before the read so incremental clients can safely ask for
    // changes without creating a gap. At worst, an update concurrent with
    // this page is returned twice and merged by jobId.
    final syncFloor = Timestamp.now();
    final snapshots = await query.limit(limit + 1).get();
    final documents = snapshots.docs;
    final hasMore = documents.length > limit;
    final pageDocuments = documents.take(limit).toList(growable: false);
    final last = pageDocuments.isEmpty ? null : pageDocuments.last;
    final lastData = last?.data();
    final orderedAt = lastData?[orderedField];
    final nextCursor = hasMore && last != null && orderedAt is Timestamp
        ? JobListCursor(
            orderedAt: orderedAt.toDate().toUtc(),
            jobId: last.ref.id,
            offset: (cursor?.offset ?? 0) + pageDocuments.length,
          ).encode()
        : null;
    return RecordedJobPage(
      jobs: pageDocuments
          .map((snapshot) => snapshot.data())
          .where((data) => !recordRetentionExpired(data))
          .where((data) => data['ghostMode'] != true)
          .map(_publicJob)
          .toList(growable: false),
      hasMore: hasMore,
      nextCursor: nextCursor,
      syncAfter: (snapshots.readTime ?? syncFloor).toDate().toUtc(),
    );
  }
}

const _githubTerminalStatuses = {'completed', 'failed', 'cancelled'};

bool githubJobNeedsReconciliation(
  Map<String, Object?> job, {
  bool retentionExpired = false,
}) {
  if (job['provider'] != 'github_actions' || retentionExpired) return false;
  if (!_githubTerminalStatuses.contains(job['status'])) return true;
  return job['status'] == 'failed' &&
      job['errorCode'] == 'github_workflow_run_not_observed' &&
      job['githubRunId'] == null;
}

Map<String, Object?> _generationMetadata({
  required String? prompt,
  required String model,
  required String workflowKey,
}) => {'prompt': prompt ?? '', 'model': model, 'workflowKey': workflowKey};

Timestamp _retentionTimestamp(int days) {
  final bounded = days.clamp(1, 30);
  return Timestamp.fromDate(
    DateTime.now().toUtc().add(Duration(days: bounded)),
  );
}
