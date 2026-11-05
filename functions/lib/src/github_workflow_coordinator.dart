import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'classification_runtime.dart';
import 'domain.dart';
import 'github_client.dart';
import 'job_run_store.dart';
import 'prompt_enhancer.dart';
import 'retention_policy.dart';
import 'workflow_catalog.dart';
import 'workflow_catalog_selection.dart';
import 'workflow_catalog_store.dart';
import 'workflow_source_references.dart';
import 'workspace_resource_resolver.dart';
import 'workspace_store.dart';

part 'github_connected_workflow.dart';

final class GitHubWorkflowCoordinator {
  GitHubWorkflowCoordinator({
    required this.githubForWorkspace,
    required this.store,
    required this.classificationRuntime,
    ConnectedWorkflowDiscoveryCache? connectedWorkflowCache,
  }) : connectedWorkflowCache =
           connectedWorkflowCache ?? ConnectedWorkflowDiscoveryCache();

  final GitHubClientProvider githubForWorkspace;
  final WorkspaceStore store;
  final ConnectedWorkflowDiscoveryCache connectedWorkflowCache;

  /// Decides whether the open JEV classification runtime may run: from the
  /// organization's runner capacity report, read at most once a minute, or
  /// `notReported` when the deployment receives no capacity reports. The
  /// composition root chooses which, so there is no default.
  final ClassificationRuntimeGate classificationRuntime;

  Future<Map<String, Object?>> refreshCatalogs(Workspace workspace) async {
    final catalogs = <WorkflowCatalog>[];
    final errors = <Map<String, Object?>>[];
    for (final repository in workspace.repositories) {
      try {
        final catalog = await _readCatalog(workspace, repository);
        await store.saveWorkflowCatalog(workspace.id, catalog);
        catalogs.add(catalog);
      } on ApiError catch (error) {
        if (error.code != 'github_resource_not_found' &&
            error.code != 'workflow_catalog_invalid') {
          rethrow;
        }
        await store.deleteWorkflowCatalog(workspace.id, repository);
        errors.add({
          'repository': repository,
          'code': error.code,
          'message': error.message,
        });
      }
    }
    await store.removeWorkflowCatalogsOutside(
      workspace.id,
      workspace.repositories.toSet(),
    );
    return {
      'templates': await _templates(workspace, catalogs),
      'errors': errors,
    };
  }

  Future<List<Map<String, Object?>>> listTemplates(Workspace workspace) async {
    final catalogs = await store.listWorkflowCatalogs(workspace.id);
    return _templates(workspace, catalogs);
  }

  Future<List<Map<String, Object?>>> _templates(
    Workspace workspace,
    List<WorkflowCatalog> catalogs,
  ) async {
    final needsRuntime = catalogs.any(
      (catalog) => catalog.workflows.any(
        (workflow) => isClassificationWorkflow(workflow.id),
      ),
    );
    return buildWorkflowTemplates(
      workspace,
      catalogs,
      classificationRuntime: needsRuntime
          ? await classificationRuntime.status(workspace.organizationId)
          : null,
    );
  }

  Future<Map<String, Object?>> dispatch({
    required Workspace workspace,
    required String actorUid,
    required String requestId,
    required String workflowKeyValue,
    required Map<String, Object?> input,
    Map<String, Object?>? generationSelection,
    Map<String, Object?>? retentionAttachment,
    Map<String, Object?>? generationReview,
    PromptEnhancementBypass? promptEnhancementBypass,
    PromptEnhancementPurpose promptEnhancementPurpose =
        PromptEnhancementPurpose.general,
    String? promptSuffix,
    String? notificationDeepLink,
    bool allowConnectedWorkflow = false,
    bool ghostMode = false,
  }) async {
    final parsed = parseWorkflowKey(workflowKeyValue);
    if (!workspace.containsRepository(parsed.repository)) {
      throw const ApiError(
        409,
        'workflow_not_enabled',
        'This workflow is not enabled for the workspace.',
      );
    }

    final catalog = await _readCatalog(workspace, parsed.repository);
    final workflow = catalog.find(parsed.workflowId);
    if (workflow == null) {
      throw const ApiError(
        404,
        'workflow_not_found',
        'The enabled workflow is no longer present in its catalog.',
      );
    }
    if (!allowConnectedWorkflow &&
        !workspaceWorkflowSelectionIncludes(
          catalog: catalog,
          selectedWorkflowKeys: workspace.workflows.toSet(),
          workflow: workflow,
        )) {
      throw const ApiError(
        409,
        'workflow_not_enabled',
        'This workflow is not enabled for the workspace.',
      );
    }
    if (isClassificationWorkflow(workflow.id)) {
      requireClassificationRuntime(
        await classificationRuntime.status(workspace.organizationId),
      );
    }
    final inputs = workflow.validateInputs(input);
    validateWorkflowSourceReferences(inputs);
    PromptEnhancementResult? enhancement;
    final originalPrompt = inputs['prompt'];
    if (originalPrompt != null) {
      final effectiveBypass = resolvePromptEnhancementBypass(
        ghostMode: ghostMode,
        requested: promptEnhancementBypass,
      );
      final context = PromptEnhancementContext.fromWorkflow(
        workflowId: workflow.id,
        targetModel: workflow.model,
        input: inputs,
        outputKinds: workflow.outputs.map((output) => output.kind),
        purpose: promptEnhancementPurpose,
      );
      enhancement = bypassPromptEnhancement(
        originalPrompt: originalPrompt,
        context: context,
        reason: effectiveBypass,
      );
      inputs['prompt'] = appendPromptSuffix(
        enhancement.prompt,
        suffix: promptSuffix,
        maxLength: workflow.inputs['prompt']?.maxLength ?? 60000,
      );
    }
    await store.saveWorkflowCatalog(workspace.id, catalog);
    Map<String, Object?>? runnerGrant;
    if (workspace.resourceGrantsExplicit) {
      final resolved = await WorkspaceResourceResolver(
        store,
      ).requirePrimaryRunner(workspace);
      runnerGrant = {
        'resourceId': resolved.pool.id,
        'provider': resolved.pool.provider,
        if (resolved.pool.providerPoolId.isNotEmpty)
          'providerPoolId': resolved.pool.providerPoolId,
        'capabilities': resolved.grant.capabilities.toList()..sort(),
        'maxCpu': resolved.grant.maxCpu,
        'maxRamMiB': resolved.grant.maxRamMiB,
        'maxConcurrent': resolved.grant.maxConcurrent,
      };
    }
    final queued = await store.queueGitHubJob(
      workspaceId: workspace.id,
      organizationId: workspace.organizationId,
      jobId: requestId,
      catalog: catalog,
      workflow: workflow,
      inputs: inputs,
      promptEnhancement: enhancement?.toMetadata(),
      generationSelection: ghostMode ? null : generationSelection,
      retentionAttachment: ghostMode
          ? null
          : retentionAttachment ?? generationSelection,
      generationReview: ghostMode ? null : generationReview,
      notificationDeepLink: notificationDeepLink,
      createdBy: actorUid,
      retentionDays: artifactRetentionDays(
        workspace.artifactStorage?.retentionDays,
      ),
      ghostMode: ghostMode,
      runnerGrant: runnerGrant,
    );
    if (!queued.created) return queued.job;

    try {
      final github = await githubForWorkspace(workspace);
      await github.dispatchWorkflow(
        workspace,
        repository: catalog.repository,
        workflowPath: workflow.dispatchWorkflow,
        ref: catalog.ref,
        inputs: githubWorkflowDispatchInputs(
          inputs: inputs,
          requestId: requestId,
          ghostMode: ghostMode,
        ),
      );
      return store.markGitHubJobDispatched(workspace.id, requestId);
    } on Object catch (error) {
      final code = error is ApiError
          ? error.code
          : error.runtimeType.toString();
      await store.markGitHubJobDispatchFailed(workspace.id, requestId, code);
      rethrow;
    }
  }

  /// Ghost dispatches carry only an opaque request identity. The authenticated
  /// workflow claim returns the validated payload once, after GitHub run
  /// identity has been verified. This keeps prompts and source IDs out of the
  /// durable workflow_dispatch event and GitHub run metadata.
  static Map<String, String> githubWorkflowDispatchInputs({
    required Map<String, String> inputs,
    required String requestId,
    required bool ghostMode,
  }) => ghostMode
      ? {'ii_request_id': requestId, 'ii_payload_mode': 'claim'}
      : {...inputs, 'ii_request_id': requestId};

  Future<Map<String, Object?>> listJobs(
    Workspace workspace, {
    int limit = 50,
    JobListCursor? cursor,
    bool reconcile = true,
  }) async {
    var stale = false;
    if (reconcile && cursor == null) {
      final pending = await store.listGitHubJobsToReconcile(workspace.id);
      final runLists = <String, List<Map<String, Object?>>>{};
      for (final job in pending) {
        try {
          await _reconcile(workspace, job, runLists);
        } on ApiError {
          stale = true;
        }
      }
    }
    final page = await store.listRecordedJobsPage(
      workspace.id,
      limit: limit,
      cursor: cursor,
    );
    return page.toJson(stale: stale);
  }

  Future<Map<String, Object?>> listJobChanges(
    Workspace workspace, {
    required DateTime changesSince,
    int limit = 50,
    JobListCursor? cursor,
  }) async {
    final page = await store.listRecordedJobChanges(
      workspace.id,
      changesSince: changesSince,
      limit: limit,
      cursor: cursor,
    );
    return page.toJson();
  }

  Future<Map<String, Object?>> getJob(Workspace workspace, String jobId) async {
    final job = await store.getRecordedJob(workspace.id, jobId);
    if (job['provider'] == 'github_actions' &&
        !_terminalStatuses.contains(job['status'])) {
      try {
        final raw = await _rawJob(workspace.id, jobId);
        await _reconcile(
          workspace,
          raw,
          <String, List<Map<String, Object?>>>{},
        );
      } on ApiError {
        // Preserve the last durable state when GitHub is temporarily stale.
      }
    }
    return store.getRecordedJob(workspace.id, jobId);
  }

  Future<Map<String, Object?>> cancelJob(
    Workspace workspace,
    String jobId,
  ) async {
    await store.requestGitHubJobCancellation(workspace.id, jobId);
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final found = await _reconcile(
          workspace,
          await _rawJob(workspace.id, jobId),
          <String, List<Map<String, Object?>>>{},
        );
        if (found) break;
      } on ApiError {
        // The durable cancellation request will retry during reconciliation.
        break;
      }
      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
    }
    return store.getRecordedJob(workspace.id, jobId);
  }

  Future<bool> _reconcile(
    Workspace workspace,
    Map<String, Object?> job,
    Map<String, List<Map<String, Object?>>> runLists,
  ) async {
    final github = await githubForWorkspace(workspace);
    final repository = job['repository'];
    final workflowPath = job['workflowPath'];
    final jobId = job['jobId'];
    if (repository is! String || workflowPath is! String || jobId is! String) {
      throw const ApiError(
        500,
        'job_record_invalid',
        'The workflow job record is invalid.',
      );
    }
    Map<String, Object?>? run;
    final runId = job['githubRunId'];
    if (runId is num && runId.toInt() > 0) {
      run = await github.getWorkflowRun(
        workspace,
        repository: repository,
        runId: runId.toInt(),
      );
    } else {
      final submittedAt = _timestamp(job['submittedAt']);
      final lookupSince = githubWorkflowRunLookupSince(submittedAt);
      final lookupUntil = githubWorkflowRunLookupUntil(submittedAt);
      final cacheKey = '$repository#$workflowPath#$lookupSince#$lookupUntil';
      final runs = runLists[cacheKey] ??= await github.listWorkflowRuns(
        workspace,
        repository: repository,
        workflowPath: workflowPath,
        createdSince: lookupSince,
        createdUntil: lookupUntil,
      );
      for (final candidate in runs) {
        if (matchesDispatchedRun(
          candidate,
          jobId: jobId,
          workflowPath: workflowPath,
          submittedAt: submittedAt,
        )) {
          run = candidate;
          break;
        }
      }
    }
    if (run == null) {
      if (shouldExpireUnobservedGitHubJob(job, now: DateTime.now().toUtc())) {
        await store.expireUnobservedGitHubJob(
          workspaceId: workspace.id,
          jobId: jobId,
          errorCode: 'github_workflow_run_not_observed',
        );
        return true;
      }
      return false;
    }

    final id = run['id'];
    final githubStatus = run['status'];
    if (id is! num || githubStatus is! String) {
      throw const ApiError(
        502,
        'github_response_invalid',
        'GitHub returned an invalid workflow run.',
      );
    }
    final conclusion = run['conclusion'] as String?;
    final cancellationRequested = job['cancelRequestedAt'] != null;
    if (cancellationRequested && githubStatus != 'completed') {
      await github.cancelWorkflowRun(
        workspace,
        repository: repository,
        runId: id.toInt(),
      );
    }
    await store.updateGitHubJobRun(
      workspace.id,
      jobId,
      runId: id.toInt(),
      runAttempt: (run['run_attempt'] as num?)?.toInt() ?? 1,
      status: githubRunStatus(
        githubStatus,
        conclusion,
        cancellationRequested: cancellationRequested,
      ),
      githubStatus: githubStatus,
      conclusion: conclusion,
      url: run['html_url'] as String? ?? '',
    );
    return true;
  }

  Future<Map<String, Object?>> _rawJob(String workspaceId, String jobId) async {
    final snapshot = await store.firestore
        .collection('jobRuns')
        .doc(jobId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['workspaceId'] != workspaceId) {
      throw const ApiError(404, 'job_not_found', 'Job not found.');
    }
    return data;
  }

  Future<WorkflowCatalog> _readCatalog(
    Workspace workspace,
    String repository,
  ) async {
    final github = await githubForWorkspace(workspace);
    final file = await github.readWorkflowCatalogFile(workspace, repository);
    final catalog = WorkflowCatalog.parse(
      repository: file['repository'] as String? ?? '',
      repositoryId: (file['repositoryId'] as num?)?.toInt() ?? 0,
      ref: file['ref'] as String? ?? '',
      sha: file['sha'] as String? ?? '',
      content: file['content'] as String? ?? '',
    );
    final repositoryWorkflows = await github.listRepositoryWorkflows(
      workspace,
      repository,
    );
    final activePaths = repositoryWorkflows
        .where((item) => item['state'] == 'active')
        .map((item) => item['path'])
        .whereType<String>()
        .toSet();
    if (catalog.workflows.any(
      (workflow) => !activePaths.contains(workflow.dispatchWorkflow),
    )) {
      throw const ApiError(
        422,
        'workflow_catalog_invalid',
        'A catalog entry does not reference an active repository workflow.',
      );
    }
    return catalog;
  }
}

/// The template list a workspace sees, in a stable order.
///
/// [classificationRuntime] is the organization's open JEV runtime status; it
/// is required only when a catalog carries a classification workflow, and it
/// narrows those templates without touching any other.
List<Map<String, Object?>> buildWorkflowTemplates(
  Workspace workspace,
  List<WorkflowCatalog> catalogs, {
  ClassificationRuntimeStatus? classificationRuntime,
}) {
  final result = <Map<String, Object?>>[];
  final selectedWorkflowKeys = workspace.workflows.toSet();
  for (final catalog in catalogs) {
    for (final workflow in catalog.workflows) {
      final key = workflowKey(catalog.repository, workflow.id);
      final enabled = workspaceWorkflowSelectionIncludes(
        catalog: catalog,
        selectedWorkflowKeys: selectedWorkflowKeys,
        workflow: workflow,
      );
      final template = <String, Object?>{
        'id': key,
        'workflowId': workflow.id,
        'version': workflow.contractVersion.toString(),
        'displayName': workflow.name,
        'model': workflow.model,
        'repository': catalog.repository,
        'repositoryId': catalog.repositoryId,
        'ref': catalog.ref,
        'catalogSha': catalog.sha,
        'dispatchWorkflow': workflow.dispatchWorkflow,
        'inputs': workflow.inputs.map(
          (name, definition) => MapEntry(name, definition.toJson()),
        ),
        'outputs': workflow.outputs.map((item) => item.toJson()).toList(),
        'runtimeEstimates': workflow.runtimeEstimates
            .map((item) => item.toJson())
            .toList(),
        'enabled': enabled,
        'disabledReason': enabled ? '' : 'Not enabled for this workspace.',
      };
      result.add(
        isClassificationWorkflow(workflow.id)
            ? applyClassificationRuntime(
                template,
                classificationRuntime ?? ClassificationRuntimeStatus.unknown,
              )
            : template,
      );
    }
  }
  result.sort(
    (left, right) => (left['id'] as String).compareTo(right['id'] as String),
  );
  return result;
}

PromptEnhancementBypass resolvePromptEnhancementBypass({
  required bool ghostMode,
  PromptEnhancementBypass? requested,
}) => ghostMode
    ? PromptEnhancementBypass.ghostMode
    : requested ?? PromptEnhancementBypass.userAuthored;

String appendPromptSuffix(
  String prompt, {
  String? suffix,
  required int maxLength,
}) {
  final normalizedPrompt = prompt.trim();
  final normalizedSuffix = suffix?.trim() ?? '';
  final combined = normalizedSuffix.isEmpty
      ? normalizedPrompt
      : '$normalizedPrompt\n\n$normalizedSuffix';
  if (combined.length > maxLength) {
    throw const ApiError(
      400,
      'invalid_job_input',
      'The prompt and reference map exceed the workflow limit.',
    );
  }
  return combined;
}

const _terminalStatuses = {'completed', 'failed', 'cancelled'};
const _workflowRunLookupSkew = Duration(minutes: 2);
const workflowRunObservationTimeout = Duration(minutes: 30);

DateTime? githubWorkflowRunLookupSince(DateTime submittedAt) {
  if (submittedAt == DateTime(0)) return null;
  return submittedAt.toUtc().subtract(_workflowRunLookupSkew);
}

DateTime? githubWorkflowRunLookupUntil(DateTime submittedAt) {
  if (submittedAt == DateTime(0)) return null;
  return submittedAt.toUtc().add(workflowRunObservationTimeout);
}

bool shouldExpireUnobservedGitHubJob(
  Map<String, Object?> job, {
  required DateTime now,
  Duration timeout = workflowRunObservationTimeout,
}) {
  if (job['provider'] != 'github_actions' ||
      _terminalStatuses.contains(job['status'])) {
    return false;
  }
  final submittedAt = _timestamp(job['submittedAt']);
  if (submittedAt == DateTime(0)) return false;
  return !now.toUtc().isBefore(submittedAt.add(timeout));
}

String githubRunStatus(
  String status,
  String? conclusion, {
  bool cancellationRequested = false,
}) {
  if (status != 'completed') {
    if (cancellationRequested) return 'cancelling';
    return status == 'in_progress' ? 'running' : 'queued';
  }
  return switch (conclusion) {
    'success' || 'neutral' || 'skipped' => 'completed',
    'cancelled' => 'cancelled',
    _ => 'failed',
  };
}

bool matchesDispatchedRun(
  Map<String, Object?> run, {
  required String jobId,
  required String workflowPath,
  required DateTime submittedAt,
}) {
  final runPath = run['path'] as String? ?? '';
  if (run['event'] != 'workflow_dispatch' ||
      !(run['display_title'] as String? ?? '').endsWith(jobId) ||
      !(runPath == workflowPath || runPath.startsWith('$workflowPath@'))) {
    return false;
  }
  final createdAt = DateTime.tryParse(run['created_at'] as String? ?? '');
  return createdAt != null &&
      !createdAt.isBefore(submittedAt.subtract(const Duration(minutes: 2)));
}

DateTime _timestamp(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc() ?? DateTime(0);
  return DateTime(0);
}
