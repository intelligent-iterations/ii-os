import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:shelf/shelf.dart';

import 'agent_activation_store.dart';
import 'agent_dispatch_result.dart';
import 'agent_finalization_receipt.dart';
import 'agent_finalization_store.dart';
import 'agent_permission_approval_store.dart';
import 'agent_permission_profile.dart';
import 'agent_repository_topology.dart';
import 'agent_ticket_dispatcher.dart';
import 'api_error.dart';
import 'audit_sink.dart';
import 'auth_service.dart';
import 'codex_auth_store.dart';
import 'codex_credential_policy.dart';
import 'domain.dart';
import 'github_actions_oidc.dart';
import 'github_client.dart';
import 'http_support.dart';
import 'providers/agent_runtime/agent_execution.dart';
import 'providers/firebase/codex_credential_store.dart';
import 'retention_policy.dart';
import 'source_asset_service.dart';
import 'workflow_catalog_store.dart';
import 'workflow_run_broker.dart';
import 'workflow_token_store.dart';
import 'workspace_store.dart';

part 'workflow_agent_dispatch.dart';
part 'workflow_agent_execution_state.dart';
part 'workflow_audit.dart';
part 'workflow_permission_approval.dart';
part 'workflow_codex_verification.dart';
part 'workflow_codex_credential.dart';
part 'workflow_source_asset_read.dart';

final class WorkflowApi {
  const WorkflowApi({
    required this.store,
    required this.tokens,
    required this.runs,
    required this.audit,
    required this.sourceAssets,
    required this.codexAuth,
    required this.githubForWorkspace,
    required this.githubOidc,
    required this.agentRepositories,
    required this.agentEngines,
  });

  final WorkspaceStore store;
  final WorkflowTokenService tokens;
  final WorkflowRunBroker runs;
  final AuditSink audit;
  final SourceAssetService sourceAssets;
  final CodexAuthStore codexAuth;
  final GitHubClientProvider githubForWorkspace;
  final GitHubActionsOidcVerifier githubOidc;
  final AgentRepositoryTopology agentRepositories;
  final AgentEngineCatalog agentEngines;

  bool isWorkflowRoute(List<String> path) =>
      path.length >= 3 &&
      path[0] == 'v1' &&
      (path[1] == 'workflow-runs' ||
          path[1] == 'codex-auth-sessions' ||
          path[1] == 'agent-dispatches' ||
          path[1] == 'agent-permission-approvals');

  Future<Response> handleWorkflow(
    Request request,
    String requestId,
    List<String> path,
  ) async {
    if (path[1] == 'agent-dispatches') {
      final principal = await githubOidc.authenticate(request);
      principal.requireAgentWorkflowIdentity();
      return _handleAgentDispatch(request, requestId, path, principal);
    }
    if (path[1] == 'codex-auth-sessions') {
      final principal = await githubOidc.authenticate(request);
      principal.requireAgentWorkflowIdentity();
      return _handleCodexAuthWorkflow(request, requestId, path, principal);
    }
    if (path[1] == 'agent-permission-approvals') {
      final principal = await githubOidc.authenticate(request);
      principal.requireAgentWorkflowIdentity();
      return _handlePermissionApproval(request, requestId, path, principal);
    }
    final principal = await tokens.authenticate(request);
    if (request.method == 'POST' && path.length == 3 && path[2] == 'claim') {
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: principal.auditActor,
        workspaceId: principal.scope.workspaceId,
        action: 'workflow_run.claim',
        targetType: 'github_workflow_run',
        targetId: body['requestId'] is String
            ? body['requestId'] as String
            : null,
        metadata: {
          'repository': principal.scope.repository,
          'runId': body['runId'],
        },
        execute: () => runs.claim(principal, body),
      );
    }
    if (request.method == 'POST' && path.length == 4 && path[3] == 'complete') {
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: principal.auditActor,
        workspaceId: principal.scope.workspaceId,
        action: 'workflow_run.complete',
        targetType: 'github_workflow_run',
        targetId: path[2],
        metadata: {
          'repository': principal.scope.repository,
          'runId': body['runId'],
          'status': body['status'],
        },
        execute: () => runs.complete(principal, path[2], body),
      );
    }
    throw const ApiError(404, 'not_found', 'Workflow route not found.');
  }

  Future<Response> _handleCodexAuthWorkflow(
    Request request,
    String requestId,
    List<String> path,
    GitHubActionsPrincipal principal,
  ) async {
    final session = await codexAuth.workflowSession(path[2]);
    final workspaceId = session['workspaceId'] as String;
    final repository = session['repository'] as String;
    final verification = principal.jobUses(iiOsCodexAuthFinalizeWorkflow);
    if (request.method == 'POST' &&
        path.length == 4 &&
        credentialOperations.contains(path[3])) {
      return _codexSessionCredential(
        request,
        requestId,
        path[2],
        path[3],
        principal,
        session,
      );
    }
    final workspace = await store.getWorkspace(workspaceId);
    if (request.method == 'POST' &&
        path.length == 4 &&
        path[3] == 'authorize-allocation') {
      final body = await readJsonObject(request);
      final suppliedNonce = requiredString(body, 'nonce', maxLength: 100);
      final expectedNonce =
          session[verification ? 'verificationNonce' : 'dispatchNonce']
              as String? ??
          '';
      if (!_constantTimeTextEquals(suppliedNonce, expectedNonce)) {
        throw const ApiError(
          404,
          'codex_auth_session_not_found',
          'Codex verification session not found.',
        );
      }
      final github = await githubForWorkspace(workspace);
      final run = await _requireCodexAuthRunIdentity(
        github: github,
        workspace: workspace,
        session: session,
        workspaceId: workspaceId,
        repository: repository,
        sessionId: path[2],
        principal: principal,
        requireBound: false,
      );
      return _audited(
        requestId: requestId,
        actor: principal.auditActor,
        workspaceId: workspaceId,
        action: 'codex_auth.fleet_allocation.authorize',
        targetType: 'codex_auth_session',
        targetId: path[2],
        metadata: {
          'repository': repository,
          'runId': principal.runId,
          'runAttempt': principal.runAttempt,
        },
        execute: () async {
          await codexAuth.attachWorkflowRun(
            workspaceId: workspaceId,
            sessionId: path[2],
            runId: principal.runId,
            runAttempt: principal.runAttempt,
            runUrl: run['html_url'] as String? ?? '',
            workflowSha: principal.sha,
            verification: verification,
          );
          return {
            'authorized': true,
            'runId': principal.runId,
            'runAttempt': principal.runAttempt,
          };
        },
      );
    }
    final github = await githubForWorkspace(workspace);
    await _requireCodexAuthRunIdentity(
      github: github,
      workspace: workspace,
      session: session,
      workspaceId: workspaceId,
      repository: repository,
      sessionId: path[2],
      principal: principal,
      requireBound: true,
    );
    if (request.method == 'POST' && path.length == 4 && path[3] == 'events') {
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: principal.auditActor,
        workspaceId: workspaceId,
        action: 'codex_auth.status.update',
        targetType: 'codex_auth_session',
        targetId: path[2],
        metadata: {
          'repository': repository,
          'status': body['status'],
          'runId': body['runId'],
        },
        execute: () async {
          final updated = await codexAuth.recordWorkflowEvent(
            principal: principal,
            sessionId: path[2],
            event: body,
          );
          if (body['status'] == 'awaiting_cleanup') {
            await _startStoredSecretVerification(
              github: github,
              workspace: workspace,
              session: session,
              workspaceId: workspaceId,
              repository: repository,
              sessionId: path[2],
              principal: principal,
            );
          }
          return updated;
        },
      );
    }
    throw const ApiError(404, 'not_found', 'Workflow route not found.');
  }

  Future<Map<String, Object?>> _requireCodexAuthRunIdentity({
    required GitHubClient github,
    required Workspace workspace,
    required Map<String, Object?> session,
    required String workspaceId,
    required String repository,
    required String sessionId,
    required GitHubActionsPrincipal principal,
    required bool requireBound,
  }) async {
    if (principal.repository != repository) {
      throw const ApiError(
        404,
        'codex_auth_session_not_found',
        'Codex verification session not found.',
      );
    }
    final run = await github.getCodexAuthWorkflowRun(
      workspace,
      repository: repository,
      runId: principal.runId,
    );
    final verification = principal.jobUses(iiOsCodexAuthFinalizeWorkflow);
    final boundRunId = verification
        ? session['verificationRunId']
        : session['runId'];
    final boundRunAttempt = verification
        ? session['verificationRunAttempt']
        : session['runAttempt'];
    final boundWorkflowSha = verification
        ? session['verificationWorkflowSha']
        : session['workflowSha'];
    if (requireBound &&
        (boundRunId == null ||
            boundRunAttempt == null ||
            boundWorkflowSha == null)) {
      throw const ApiError(
        409,
        'codex_auth_workflow_run_unbound',
        'ii-os has not bound this exact Codex workflow run yet.',
      );
    }
    final title = verification
        ? 'ii-os codex verify / $repository'
        : 'ii-os codex auth / $repository';
    final runPath = run['path'] as String? ?? '';
    final expectedSha = session['trustedSourceSha'] as String? ?? '';
    final expectedRef = session['trustedSourceRef'] as String? ?? '';
    final actor = run['actor'];
    final runActor = actor is Map ? actor['login'] as String? ?? '' : '';
    final expectedActor = await github.agentBrokerBotLogin();
    if (run['id'] != principal.runId ||
        run['run_attempt'] != principal.runAttempt ||
        principal.runAttempt != 1 ||
        (requireBound && boundRunId != principal.runId) ||
        (requireBound && boundRunAttempt != principal.runAttempt) ||
        (requireBound && boundWorkflowSha != principal.sha) ||
        run['display_title'] != title ||
        run['event'] != 'workflow_dispatch' ||
        runActor != expectedActor ||
        run['head_branch'] != expectedRef ||
        run['head_sha'] != expectedSha ||
        principal.sha != expectedSha ||
        principal.trustedRef != expectedRef ||
        runPath != '.github/workflows/$iiOsAgentTaskWorkflow') {
      throw const ApiError(
        401,
        'codex_auth_workflow_run_invalid',
        'The Codex verification callback is not from its dispatched run.',
      );
    }
    return run;
  }

  Future<Response> handleAdmin(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    await store.requireAccess(actor, workspaceId, Capability.workspaceManage);
    if (path.length == 4 && request.method == 'GET') {
      return jsonResponse(200, {
        'credentials': await tokens.list(workspaceId),
      }, requestId: requestId);
    }
    if (path.length == 4 && request.method == 'POST') {
      final body = await readJsonObject(request);
      final repository = requiredString(body, 'repository', maxLength: 200);
      final workspace = await store.getWorkspace(workspaceId);
      final installationId = workspace.githubInstallationId;
      if (installationId == null || !workspace.containsRepository(repository)) {
        throw const ApiError(
          409,
          'github_installation_required',
          'Configure the GitHub App installation and repository first.',
        );
      }
      if (!workspace.workflows.any(
        (workflow) => workflow.startsWith('$repository#'),
      )) {
        throw const ApiError(
          409,
          'workflow_not_enabled',
          'Enable a discovered workflow for this repository first.',
        );
      }
      final catalog = await store.getWorkflowCatalog(workspaceId, repository);
      if (catalog.repositoryId <= 0) {
        throw const ApiError(
          409,
          'workflow_catalog_refresh_required',
          'Refresh workflow discovery before creating a credential.',
        );
      }
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'workflow_token.create',
        targetType: 'workflow_token',
        metadata: {'repository': repository},
        execute: () => tokens.issue(
          scope: WorkflowTokenScope(
            workspaceId: workspaceId,
            organizationId: workspace.organizationId,
            installationId: installationId,
            repository: repository,
            repositoryId: catalog.repositoryId,
            environment: workspace.environment,
          ),
          createdBy: actor.uid,
          expiresInDays: _expiresInDays(body),
        ),
      );
    }
    if (path.length == 6 && path[5] == 'rotate' && request.method == 'POST') {
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'workflow_token.rotate',
        targetType: 'workflow_token',
        targetId: path[4],
        execute: () => tokens.rotate(
          workspaceId: workspaceId,
          tokenId: path[4],
          createdBy: actor.uid,
          expiresInDays: _expiresInDays(body),
        ),
      );
    }
    if (path.length == 5 && request.method == 'DELETE') {
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'workflow_token.revoke',
        targetType: 'workflow_token',
        targetId: path[4],
        execute: () => tokens.revoke(
          workspaceId: workspaceId,
          tokenId: path[4],
          revokedBy: actor.uid,
        ),
      );
    }
    throw const ApiError(
      404,
      'not_found',
      'Workflow credential route not found.',
    );
  }

  Future<Response> handleSourceAsset(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    // Reading is the family floor; the upload routes escalate below.
    await store.requireAccess(actor, workspaceId, Capability.jobsRead);
    final read = await _sourceAssetReadUrl(
      request,
      requestId,
      workspaceId,
      path,
    );
    if (read != null) return read;
    await store.requireAccess(actor, workspaceId, Capability.jobsTrigger);
    if (path.length == 4 && request.method == 'POST') {
      final body = await readJsonObject(request);
      final ghostMode = _sourceAssetGhostMode(body['ghostMode']);
      final workspace = await store.getWorkspace(workspaceId);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'source_asset.upload.create',
        targetType: 'gcs_source_asset',
        targetId: requestId,
        execute: () => sourceAssets.createUpload(
          workspaceId: workspaceId,
          actorUid: actor.uid,
          request: body,
          retentionDays: artifactRetentionDays(
            workspace.artifactStorage?.retentionDays,
          ),
          ghostMode: ghostMode,
        ),
      );
    }
    if (path.length == 6 && path[5] == 'complete' && request.method == 'POST') {
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'source_asset.upload.complete',
        targetType: 'gcs_source_asset',
        targetId: path[4],
        execute: () => sourceAssets.completeUpload(
          workspaceId: workspaceId,
          actorUid: actor.uid,
          assetId: path[4],
        ),
      );
    }
    throw const ApiError(404, 'not_found', 'Source asset route not found.');
  }
}

bool _sourceAssetGhostMode(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  throw const ApiError(
    400,
    'invalid_ghost_mode',
    'Ghost mode must be true or false.',
  );
}

bool _constantTimeTextEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  var difference = leftBytes.length ^ rightBytes.length;
  final length = leftBytes.length > rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  for (var index = 0; index < length; index++) {
    final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
    final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}

int _expiresInDays(Map<String, Object?> body) {
  final value = body['expiresInDays'];
  if (value == null) return 90;
  if (value is! num || value.toInt() != value) {
    throw const ApiError(
      400,
      'invalid_workflow_token_expiry',
      'Workflow credential expiry must be a whole number of days.',
    );
  }
  return value.toInt();
}
