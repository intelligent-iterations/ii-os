import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'job_run_store.dart';
import 'notification_store.dart';
import 'retention.dart';
import 'workflow_token_store.dart';
import 'workspace_store.dart';

final class WorkflowRunClaim {
  const WorkflowRunClaim({
    required this.requestId,
    required this.repository,
    required this.repositoryId,
    required this.workflowRef,
    required this.commitSha,
    required this.runId,
    required this.runAttempt,
  });

  final String requestId;
  final String repository;
  final int repositoryId;
  final String workflowRef;
  final String commitSha;
  final int runId;
  final int runAttempt;
}

final class WorkflowRunCompletion {
  const WorkflowRunCompletion({
    required this.requestId,
    required this.runId,
    required this.runAttempt,
    required this.status,
    required this.errorCode,
    this.artifacts = const [],
  });

  final String requestId;
  final int runId;
  final int runAttempt;
  final String status;
  final String? errorCode;
  final List<Map<String, Object?>> artifacts;
}

extension WorkflowRunState on WorkspaceStore {
  Future<Map<String, Object?>> getWorkflowJobRaw(
    WorkflowTokenPrincipal principal,
    String requestId,
  ) async {
    final snapshot = await firestore.collection('jobRuns').doc(requestId).get();
    final data = snapshot.data();
    if (!snapshot.exists) throw _jobNotFound;
    _requireScopedJob(data, principal, requestId);
    return data!;
  }

  Future<Map<String, Object?>> claimWorkflowRun({
    required WorkflowTokenPrincipal principal,
    required WorkflowRunClaim claim,
  }) async {
    final ref = firestore.collection('jobRuns').doc(claim.requestId);
    late String targetWorkspaceId;
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      _requireScopedJob(data, principal, claim.requestId);
      targetWorkspaceId = data!['workspaceId']! as String;
      final existing = _map(data['workflowClaim']);
      if (existing != null) {
        if (_sameClaim(existing, claim)) {
          if (data['ghostMode'] == true) {
            throw const ApiError(
              409,
              'ghost_payload_consumed',
              'The Ghost-mode generation payload has already been claimed.',
            );
          }
          return;
        }
        throw const ApiError(
          409,
          'workflow_run_already_claimed',
          'The workflow request was claimed by a different run.',
        );
      }
      const claimable = {'dispatching', 'dispatched', 'queued', 'running'};
      if (!claimable.contains(data['status'])) {
        throw const ApiError(
          409,
          'workflow_run_not_claimable',
          'The workflow request cannot be claimed in its current state.',
        );
      }
      final now = Timestamp.now();
      final events = _events(data)
        ..add({'kind': 'workflow_claimed', 'at': now});
      transaction.update(ref, {
        'status': 'running',
        'githubStatus': 'in_progress',
        'githubRunId': claim.runId,
        'githubRunAttempt': claim.runAttempt,
        'workflowClaim': {
          'tokenId': principal.tokenId,
          'installationId': principal.scope.installationId,
          'repository': claim.repository,
          'repositoryId': claim.repositoryId,
          'workflowRef': claim.workflowRef,
          'commitSha': claim.commitSha,
          'runId': claim.runId,
          'runAttempt': claim.runAttempt,
          'claimedAt': now,
        },
        'events': events,
        'updatedAt': now,
        if (data['ghostMode'] == true) ...{
          'inputs': FieldValue.delete,
          'generationMetadata': FieldValue.delete,
          'promptEnhancement': FieldValue.delete,
          'runtimeEstimate': FieldValue.delete,
          'generationSelection': FieldValue.delete,
          'retentionAttachment': FieldValue.delete,
          'generationReview': FieldValue.delete,
          'notificationDeepLink': FieldValue.delete,
          'ghostPayloadClaimedAt': now,
        },
      });
    });
    return getRecordedJob(targetWorkspaceId, claim.requestId);
  }

  Future<Map<String, Object?>> completeWorkflowRun({
    required WorkflowTokenPrincipal principal,
    required WorkflowRunCompletion completion,
  }) async {
    final ref = firestore.collection('jobRuns').doc(completion.requestId);
    Map<String, Object?>? selection;
    String? selectedBy;
    late String targetWorkspaceId;
    var ghostMode = false;
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      _requireScopedJob(data, principal, completion.requestId);
      targetWorkspaceId = data!['workspaceId']! as String;
      final claim = _map(data['workflowClaim']);
      if (claim == null ||
          claim['runId'] != completion.runId ||
          claim['runAttempt'] != completion.runAttempt ||
          claim['repository'] != principal.scope.repository ||
          claim['repositoryId'] != principal.scope.repositoryId ||
          claim['installationId'] != principal.scope.installationId) {
        throw const ApiError(
          409,
          'workflow_run_identity_mismatch',
          'The workflow run identity does not match its claim.',
        );
      }
      const terminal = {'completed', 'failed', 'cancelled'};
      selection = _map(data['generationSelection']);
      selectedBy = data['createdBy'] as String?;
      ghostMode = data['ghostMode'] == true;
      if (terminal.contains(data['status'])) {
        if (data['status'] == completion.status) return;
        throw const ApiError(
          409,
          'workflow_run_already_completed',
          'The workflow run already has a different terminal status.',
        );
      }
      final now = Timestamp.now();
      final events = _events(data)..add({'kind': completion.status, 'at': now});
      final notification = completion.status == 'completed' && !ghostMode
          ? buildGenerationNotification(
              job: data,
              artifacts: completion.artifacts,
              createdAt: now,
            )
          : null;
      transaction.update(ref, {
        'status': completion.status,
        'githubStatus': 'completed',
        'githubConclusion': switch (completion.status) {
          'completed' => 'success',
          'cancelled' => 'cancelled',
          _ => 'failure',
        },
        'workflowResult': {
          'reportedByTokenId': principal.tokenId,
          'status': completion.status,
          'errorCode': completion.errorCode,
          'completedAt': now,
        },
        'artifacts': completion.artifacts,
        'events': events,
        'completedAt': now,
        'updatedAt': now,
      });
      if (notification != null) {
        transaction.create(
          firestore.collection('notifications').doc(completion.requestId),
          notification,
        );
      }
    });
    if (completion.status == 'completed' &&
        selection != null &&
        selectedBy != null &&
        !ghostMode) {
      await _selectCompletedGeneration(
        workspaceId: targetWorkspaceId,
        jobId: completion.requestId,
        target: selection!,
        artifacts: completion.artifacts,
        selectedBy: selectedBy!,
      );
    }
    return getRecordedJob(targetWorkspaceId, completion.requestId);
  }

  Future<void> _selectCompletedGeneration({
    required String workspaceId,
    required String jobId,
    required Map<String, Object?> target,
    required List<Map<String, Object?>> artifacts,
    required String selectedBy,
  }) async {
    final artifact = firstGeneratedImageArtifact(artifacts);
    if (artifact == null) return;
    switch (target['kind']) {
      case 'character_image':
        final characterId = target['characterId'];
        if (characterId is! String || characterId.isEmpty) return;
        final ref = firestore.collection('characters').doc(characterId);
        await firestore.runTransaction<void>((transaction) async {
          final snapshot = await transaction.get(ref);
          final data = snapshot.data();
          final body = target['body'] == true;
          final lastJobField = body
              ? 'lastBodyGenerationJobId'
              : 'lastGenerationJobId';
          if (!snapshot.exists ||
              data == null ||
              data['workspaceId'] != workspaceId ||
              data[lastJobField] != jobId) {
            return;
          }
          transaction.update(ref, {
            'selectedImage': _selectedImage(jobId, artifact),
            'updatedBy': selectedBy,
            'updatedAt': Timestamp.now(),
          });
        });
      case 'storyboard_panel_image':
        final storyboardId = target['storyboardId'];
        final panelId = target['panelId'];
        if (storyboardId is! String ||
            storyboardId.isEmpty ||
            panelId is! String ||
            panelId.isEmpty) {
          return;
        }
        final ref = firestore.collection('storyboards').doc(storyboardId);
        await firestore.runTransaction<void>((transaction) async {
          final snapshot = await transaction.get(ref);
          final data = snapshot.data();
          if (!snapshot.exists ||
              data == null ||
              data['workspaceId'] != workspaceId) {
            return;
          }
          final panels = _generationMaps(data['panels']);
          final index = panels.indexWhere(
            (panel) => panel['id'] == panelId && panel['jobId'] == jobId,
          );
          if (index < 0) return;
          panels[index] = {
            ...panels[index],
            'selectedImage': _selectedImage(jobId, artifact),
          };
          transaction.update(ref, {
            'panels': panels,
            'updatedBy': selectedBy,
            'updatedAt': Timestamp.now(),
          });
        });
    }
  }
}

Map<String, Object?>? firstGeneratedImageArtifact(
  Iterable<Map<String, Object?>> artifacts,
) {
  for (final artifact in artifacts) {
    final contentType = artifact['content_type'];
    final path = artifact['path'];
    final generation = artifact['generation'];
    if (contentType is String &&
        contentType.startsWith('image/') &&
        path is String &&
        path.isNotEmpty &&
        generation is String &&
        generation.isNotEmpty) {
      return artifact;
    }
  }
  return null;
}

Map<String, Object?> _selectedImage(
  String jobId,
  Map<String, Object?> artifact,
) => {
  'jobId': jobId,
  'path': artifact['path'],
  'generation': artifact['generation'],
  'contentType': artifact['content_type'],
  'content_type': artifact['content_type'],
};

List<Map<String, Object?>> _generationMaps(Object? value) => value is List
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.cast<String, Object?>())
          .toList()
    : <Map<String, Object?>>[];

void _requireScopedJob(
  Map<String, Object?>? data,
  WorkflowTokenPrincipal principal,
  String requestId,
) {
  if (data == null ||
      data['jobId'] != requestId ||
      data['workspaceId'] is! String ||
      (data['workspaceId'] != principal.scope.workspaceId &&
          (principal.scope.organizationId.isEmpty ||
              data['organizationId'] != principal.scope.organizationId)) ||
      data['repository'] != principal.scope.repository ||
      recordRetentionExpired(data) ||
      data['provider'] != 'github_actions') {
    throw _jobNotFound;
  }
}

const _jobNotFound = ApiError(404, 'job_not_found', 'Job not found.');

bool _sameClaim(Map<String, Object?> existing, WorkflowRunClaim claim) =>
    existing['repository'] == claim.repository &&
    existing['repositoryId'] == claim.repositoryId &&
    existing['workflowRef'] == claim.workflowRef &&
    existing['commitSha'] == claim.commitSha &&
    existing['runId'] == claim.runId &&
    existing['runAttempt'] == claim.runAttempt;

List<Map<String, Object?>> _events(Map<String, Object?> data) =>
    (data['events'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();

Map<String, Object?>? _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}
