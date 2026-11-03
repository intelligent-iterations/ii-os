part of 'api.dart';

extension on IiOsApi {
  Future<Response?> _codexAuthRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length < 4 || path[3] != 'codex-auth-sessions') return null;
    await store.requireAccess(actor, workspaceId, Capability.workspaceManage);

    if (path.length == 4 && request.method == 'POST') {
      final body = await readJsonObject(request);
      final repository = requiredString(body, 'repository', maxLength: 200);
      final reauthenticate = body.containsKey('reauthenticate')
          ? body['reauthenticate']
          : false;
      if (reauthenticate is! bool) {
        throw const ApiError(
          400,
          'invalid_reauthenticate',
          'reauthenticate must be a boolean.',
        );
      }
      final workspace = await store.getWorkspace(workspaceId);
      if (!workspace.containsRepository(repository)) {
        throw const ApiError(
          400,
          'repository_not_allowed',
          'Repository is not configured for this workspace.',
        );
      }
      if (!workspace.workflows.contains('$repository#$iiOsAgentTaskWorkflow')) {
        throw const ApiError(
          409,
          'agent_workflow_not_enabled',
          'Explicitly enable the ii-os agent workflow before verifying Codex.',
        );
      }
      final github = await githubForWorkspace(workspace);
      final inspection = await github.inspectAgentRepositoryReadiness(
        workspace,
        repository: repository,
        codexAuthState: await workflowApi.codexAuth.repositoryState(
          workspaceId,
          repository,
        ),
        requiredEngine: codexAgentEngine,
      );
      final onboardingBlockers = inspection.checks
          .where(
            (check) =>
                check['id'] != 'codex_auth_secret' &&
                check['status'] != 'passed',
          )
          .toList();
      if (onboardingBlockers.isNotEmpty ||
          inspection.sourceRef != 'ii-os-agent-v4-${inspection.sourceSha}') {
        throw ApiError(
          409,
          'codex_auth_source_untrusted',
          'Codex can connect only through the immutable reviewed agent source.',
          details: {'checks': onboardingBlockers},
        );
      }
      await github.requireCodexAuthDispatchReady(
        workspace,
        repository: repository,
        trustedSourceRef: inspection.sourceRef,
      );
      final identity = await github.codexAuthRepositoryIdentity(
        workspace,
        repository: repository,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'codex_auth.session.start',
        targetType: 'github_repository',
        targetId: repository,
        metadata: {'repository': repository},
        execute: () async {
          final session = await workflowApi.codexAuth.createSession(
            workspaceId: workspaceId,
            repository: repository,
            repositoryId: identity['repositoryId']! as int,
            requestedBy: actor.uid,
            trustedSourceSha: inspection.sourceSha,
            trustedSourceRef: inspection.sourceRef,
            reauthenticate: reauthenticate,
          );
          final sessionId = session['id']! as String;
          if (session['created'] != true) return {'session': session};
          final internal = await workflowApi.codexAuth.workflowSession(
            sessionId,
          );
          try {
            await github.dispatchWorkflow(
              workspace,
              repository: repository,
              workflowPath: '.github/workflows/$iiOsAgentTaskWorkflow',
              ref: inspection.sourceRef,
              inputs: {
                'operation': 'codex_auth',
                'repository': repository,
                'codex_auth_session_id': sessionId,
                'codex_auth_nonce': internal['dispatchNonce']! as String,
                'codex_auth_reauthenticate': reauthenticate.toString(),
              },
            );
          } on Object {
            await workflowApi.codexAuth.failSession(
              workspaceId: workspaceId,
              sessionId: sessionId,
              errorCode: 'codex_auth_dispatch_failed',
              detail:
                  'GitHub could not start the Codex verification workflow. Check the workflow and App permissions.',
            );
            rethrow;
          }
          return {'session': session};
        },
      );
    }

    if (path.length == 5 && request.method == 'GET') {
      var session = await workflowApi.codexAuth.getSession(
        workspaceId: workspaceId,
        sessionId: path[4],
      );
      if (session['status'] == 'dispatching') {
        session = await _reconcileBoundCodexAuthRun(
          workspaceId,
          path[4],
          session,
        );
      } else if (session['status'] == 'awaiting_cleanup') {
        session = await _reconcileStoredCodexVerification(
          workspaceId,
          path[4],
          session,
        );
      }
      return jsonResponse(200, {'session': session}, requestId: requestId);
    }

    throw const ApiError(404, 'not_found', 'API route not found.');
  }

  Future<Map<String, Object?>> _reconcileBoundCodexAuthRun(
    String workspaceId,
    String sessionId,
    Map<String, Object?> session,
  ) async {
    final repository = session['repository'] as String? ?? '';
    final runId = (session['runId'] as num?)?.toInt() ?? 0;
    if (repository.isEmpty || runId <= 0) return session;
    final workspace = await store.getWorkspace(workspaceId);
    final github = await githubForWorkspace(workspace);
    final run = await github.getCodexAuthWorkflowRun(
      workspace,
      repository: repository,
      runId: runId,
    );
    if (run['status'] == 'completed' && run['conclusion'] != 'success') {
      await workflowApi.codexAuth.failSession(
        workspaceId: workspaceId,
        sessionId: sessionId,
        errorCode: 'codex_auth_workflow_failed',
        detail:
            'The bound Codex authentication run failed before sign-in completed.',
      );
      return workflowApi.codexAuth.getSession(
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
    }
    return session;
  }

  Future<Map<String, Object?>> _reconcileStoredCodexVerification(
    String workspaceId,
    String sessionId,
    Map<String, Object?> session,
  ) async {
    final repository = session['repository'] as String? ?? '';
    final runId = (session['verificationRunId'] as num?)?.toInt() ?? 0;
    if (repository.isEmpty || runId <= 0) return session;
    final workspace = await store.getWorkspace(workspaceId);
    final github = await githubForWorkspace(workspace);
    final run = await github.getCodexAuthWorkflowRun(
      workspace,
      repository: repository,
      runId: runId,
    );
    if (run['status'] == 'completed' && run['conclusion'] != 'success') {
      await workflowApi.codexAuth.failSession(
        workspaceId: workspaceId,
        sessionId: sessionId,
        errorCode: 'codex_auth_stored_verification_failed',
        detail:
            'The separately dispatched repository-secret smoke or its runtime cleanup proof failed.',
      );
      return workflowApi.codexAuth.getSession(
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
    }
    return session;
  }
}
