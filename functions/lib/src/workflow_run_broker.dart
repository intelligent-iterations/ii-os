import 'api_error.dart';
import 'asset_retention_service.dart';
import 'domain.dart';
import 'github_client.dart';
import 'http_support.dart';
import 'notification_dispatcher.dart';
import 'source_asset_service.dart';
import 'workflow_artifact_verifier.dart';
import 'workflow_run_store.dart';
import 'workflow_source_references.dart';
import 'workflow_token_store.dart';
import 'workspace_store.dart';

final class WorkflowRunBroker {
  const WorkflowRunBroker({
    required this.store,
    required this.githubForWorkspace,
    required this.artifacts,
    this.retention,
    this.sourceAssets,
    this.notifications,
  });

  final WorkspaceStore store;
  final GitHubClientProvider githubForWorkspace;
  final WorkflowArtifactVerifier artifacts;
  final AssetRetentionService? retention;
  final SourceAssetService? sourceAssets;
  final GenerationNotificationDispatcher? notifications;

  Future<Map<String, Object?>> claim(
    WorkflowTokenPrincipal principal,
    Map<String, Object?> body,
  ) async {
    final claim = WorkflowRunClaim(
      requestId: _requestId(body),
      repository: requiredString(body, 'repository', maxLength: 200),
      repositoryId: _positiveInt(body, 'repositoryId'),
      workflowRef: requiredString(body, 'workflowRef', maxLength: 400),
      commitSha: requiredString(body, 'commitSha', maxLength: 64),
      runId: _positiveInt(body, 'runId'),
      runAttempt: _positiveInt(body, 'runAttempt'),
    );
    _requirePrincipalScope(principal, claim);
    final job = await store.getWorkflowJobRaw(principal, claim.requestId);
    final targetWorkspaceId = job['workspaceId']! as String;
    final workspace = await store.getWorkspace(targetWorkspaceId);
    _requireTargetWorkspaceScope(
      principal: principal,
      job: job,
      workspace: workspace,
    );
    final github = await githubForWorkspace(workspace);
    final run = await github.getWorkflowRun(
      workspace,
      repository: claim.repository,
      runId: claim.runId,
    );
    validateClaimedGitHubRun(claim: claim, job: job, githubRun: run);
    final rawInputs = _map(job['inputs']) ?? const <String, Object?>{};
    if (rawInputs.values.any((value) => value is! String)) {
      throw const ApiError(
        500,
        'job_record_invalid',
        'The workflow job input record is invalid.',
      );
    }
    final inputPayload = rawInputs.cast<String, String>();
    final sourceContracts = await _sourceAssetContracts(
      inputPayload,
      targetWorkspaceId,
    );
    final recorded = await store.claimWorkflowRun(
      principal: principal,
      claim: claim,
    );
    final ghostMode = job['ghostMode'] == true;
    return {
      ...recorded,
      'inputs': inputPayload,
      'gcpUpload': {
        ...await artifacts.uploadContract(targetWorkspaceId),
        'objectPrefix':
            'workspaces/$targetWorkspaceId/'
            '${ghostMode ? 'ghost' : 'runs'}/${claim.requestId}/',
      },
      if (sourceContracts.isNotEmpty) ...{
        'sourceAsset': sourceContracts.first,
        'sourceAssets': sourceContracts,
      },
    };
  }

  Future<Map<String, Object?>> complete(
    WorkflowTokenPrincipal principal,
    String requestId,
    Map<String, Object?> body,
  ) async {
    if (!_validRequestId(requestId)) {
      throw const ApiError(
        400,
        'invalid_request_id',
        'The workflow request ID is invalid.',
      );
    }
    final status = requiredString(body, 'status', maxLength: 20);
    if (!const {'completed', 'failed', 'cancelled'}.contains(status)) {
      throw const ApiError(
        400,
        'invalid_workflow_status',
        'Workflow status must be completed, failed, or cancelled.',
      );
    }
    final rawErrorCode = body['errorCode'];
    if (rawErrorCode != null &&
        (rawErrorCode is! String ||
            rawErrorCode.isEmpty ||
            rawErrorCode.length > 100 ||
            !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(rawErrorCode))) {
      throw const ApiError(
        400,
        'invalid_error_code',
        'Workflow error code is invalid.',
      );
    }
    final pendingJob = await store.getWorkflowJobRaw(principal, requestId);
    final targetWorkspaceId = pendingJob['workspaceId']! as String;
    final ghostMode = pendingJob['ghostMode'] == true;
    final verifiedArtifacts = status == 'completed'
        ? await artifacts.verify(
            workspaceId: targetWorkspaceId,
            requestId: requestId,
            value: body['artifacts'],
            ghostMode: ghostMode,
          )
        : <Map<String, Object?>>[];
    final job = await store.completeWorkflowRun(
      principal: principal,
      completion: WorkflowRunCompletion(
        requestId: requestId,
        runId: _positiveInt(body, 'runId'),
        runAttempt: _positiveInt(body, 'runAttempt'),
        status: status,
        errorCode: rawErrorCode as String?,
        artifacts: verifiedArtifacts,
      ),
    );
    if (status == 'completed' && !ghostMode) {
      final target = _map(
        pendingJob['retentionAttachment'] ?? pendingJob['generationSelection'],
      );
      if (target != null) {
        await retention?.protectCompletedTarget(
          workspaceId: targetWorkspaceId,
          jobId: requestId,
          target: target,
        );
      }
      await notifications?.deliver(requestId);
    }
    return job;
  }

  Future<List<Map<String, Object?>>> _sourceAssetContracts(
    Map<String, Object?> inputs,
    String workspaceId,
  ) async {
    final contracts = <Map<String, Object?>>[];
    for (final reference in workflowSourceReferences(inputs)) {
      if (sourceAssets == null) {
        throw const ApiError(
          409,
          'source_asset_not_ready',
          'The source asset is not ready for this workflow.',
        );
      }
      final contract = await sourceAssets!.workflowReadContract(
        workspaceId: workspaceId,
        assetId: reference.assetId,
      );
      contracts.add(workflowSourceContract(contract, reference));
    }
    return contracts;
  }
}

void _requireTargetWorkspaceScope({
  required WorkflowTokenPrincipal principal,
  required Map<String, Object?> job,
  required Workspace workspace,
}) {
  final sameWorkspace = workspace.id == principal.scope.workspaceId;
  final sameOrganization =
      principal.scope.organizationId.isNotEmpty &&
      workspace.organizationId == principal.scope.organizationId &&
      job['organizationId'] == principal.scope.organizationId;
  if ((!sameWorkspace && !sameOrganization) ||
      workspace.githubInstallationId != principal.scope.installationId ||
      workspace.environment != principal.scope.environment ||
      !workspace.containsRepository(principal.scope.repository)) {
    throw const ApiError(
      403,
      'workflow_token_scope_mismatch',
      'The workflow credential is not scoped to this run.',
    );
  }
}

Map<String, Object?> workflowSourceContract(
  Map<String, Object?> contract,
  WorkflowSourceReference reference,
) {
  final contentType = contract['contentType'];
  if (reference.kind != null &&
      (contentType is! String ||
          !contentType.startsWith('${reference.kind}/'))) {
    throw const ApiError(
      409,
      'source_asset_kind_mismatch',
      'A source asset does not match its declared reference kind.',
    );
  }
  return {
    ...contract,
    if (reference.kind != null) 'kind': reference.kind,
    if (reference.role != null) 'role': reference.role,
    if (reference.ordinal != null) 'ordinal': reference.ordinal,
  };
}

void validateClaimedGitHubRun({
  required WorkflowRunClaim claim,
  required Map<String, Object?> job,
  required Map<String, Object?> githubRun,
}) {
  final repository = _map(githubRun['repository']);
  final workflowPath = job['workflowPath'];
  final runPath = githubRun['path'];
  final headBranch = githubRun['head_branch'];
  final displayTitle = githubRun['display_title'] as String? ?? '';
  if (workflowPath is! String ||
      githubRun['id'] != claim.runId ||
      githubRun['run_attempt'] != claim.runAttempt ||
      githubRun['event'] != 'workflow_dispatch' ||
      githubRun['head_sha'] != claim.commitSha ||
      repository?['id'] != claim.repositoryId ||
      repository?['full_name'] != claim.repository ||
      runPath is! String ||
      headBranch is! String ||
      !(displayTitle == claim.requestId ||
          displayTitle.endsWith(' ${claim.requestId}')) ||
      !_workflowReferenceMatches(
        claim.workflowRef,
        repository: claim.repository,
        workflowPath: workflowPath,
        runPath: runPath,
        headBranch: headBranch,
      )) {
    throw const ApiError(
      409,
      'workflow_run_verification_failed',
      'The GitHub workflow run does not match the pending request.',
    );
  }
}

bool _workflowReferenceMatches(
  String workflowRef, {
  required String repository,
  required String workflowPath,
  required String runPath,
  required String headBranch,
}) {
  final prefix = '$repository/';
  if (!workflowRef.startsWith(prefix)) return false;
  final claimedPath = workflowRef.substring(prefix.length);
  final claimedSeparator = claimedPath.lastIndexOf('@');
  final runSeparator = runPath.lastIndexOf('@');
  if (claimedSeparator <= 0 || headBranch.isEmpty) return false;
  if (claimedPath.substring(0, claimedSeparator) != workflowPath) {
    return false;
  }
  final recordedPath = runSeparator > 0
      ? runPath.substring(0, runSeparator)
      : runPath;
  if (recordedPath != workflowPath) return false;

  final claimedRef = claimedPath.substring(claimedSeparator + 1);
  if (!_gitReferenceMatches(claimedRef, headBranch)) return false;
  if (runSeparator <= 0) return true;
  return _gitReferenceMatches(claimedRef, runPath.substring(runSeparator + 1));
}

bool _gitReferenceMatches(String left, String right) =>
    _shortGitReference(left) == _shortGitReference(right);

String _shortGitReference(String value) {
  for (final prefix in const ['refs/heads/', 'refs/tags/']) {
    if (value.startsWith(prefix)) return value.substring(prefix.length);
  }
  return value;
}

void _requirePrincipalScope(
  WorkflowTokenPrincipal principal,
  WorkflowRunClaim claim,
) {
  if (claim.repository != principal.scope.repository ||
      claim.repositoryId != principal.scope.repositoryId ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(claim.commitSha)) {
    throw const ApiError(
      403,
      'workflow_token_scope_mismatch',
      'The workflow credential is not scoped to this run.',
    );
  }
}

String _requestId(Map<String, Object?> body) {
  final value = requiredString(body, 'requestId', maxLength: 64);
  if (!_validRequestId(value)) {
    throw const ApiError(
      400,
      'invalid_request_id',
      'The workflow request ID is invalid.',
    );
  }
  return value;
}

bool _validRequestId(String value) =>
    RegExp(r'^[A-Za-z0-9_.:-]{8,64}$').hasMatch(value);

int _positiveInt(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value is! num || value.toInt() <= 0 || value.toInt() != value) {
    throw ApiError(400, 'invalid_$field', '$field must be a positive integer.');
  }
  return value.toInt();
}

Map<String, Object?>? _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}
