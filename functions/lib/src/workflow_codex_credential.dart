part of 'workflow_api.dart';

const credentialOperations = {
  'credential-acquire',
  'credential-writer',
  'credential-commit',
};

extension WorkflowCodexCredential on WorkflowApi {
  Future<Response> _ticketCredential(
    Request request,
    String requestId,
    String workspaceId,
    String projectItemId,
    String operation,
    GitHubActionsPrincipal principal,
  ) async {
    final body = await readJsonObject(request);
    final dispatchId = requiredString(body, 'dispatchId', maxLength: 200);
    final issue = body['issueNumber'];
    if (issue is! int || issue <= 0) throw credentialConflict;
    final profile = await AgentActivationStore(store).profileForConsumedRun(
      principal: principal,
      workspaceId: workspaceId,
      projectItemId: projectItemId,
      claimId: dispatchId,
      issueNumber: issue,
      allowCleanupRecovery: body['cleanupOnly'] == true,
    );
    if (profile.engine != codexAgentEngine ||
        profile.runtime == null ||
        (body['permissionProfile'] != null &&
            body['permissionProfile'] != profile.id) ||
        (body['permissionDigest'] != null &&
            body['permissionDigest'] !=
                agentPermissionProfileDigest(profile))) {
      throw credentialConflict;
    }
    if (operation == 'credential-acquire') {
      if (principal.runAttempt != 1 && body['cleanupOnly'] != true) {
        throw credentialConflict;
      }
      requireCodexCredentialConfiguration(
        profile: profile,
        configuration: codexCredentialConfiguration(body),
        repository: principal.repository,
      );
    }
    return _credentialOperation(
      requestId,
      operation,
      body,
      CodexCredentialOwner(
        workspaceId: workspaceId,
        subjectId: '$projectItemId:$dispatchId',
        purpose: 'work-ticket',
        principal: principal,
        projectItemId: projectItemId,
        dispatchId: dispatchId,
      ),
    );
  }

  Future<Response> _codexSessionCredential(
    Request request,
    String requestId,
    String sessionId,
    String operation,
    GitHubActionsPrincipal principal,
    Map<String, Object?> session,
  ) async {
    final body = await readJsonObject(request);
    final cleanupOnly = body['cleanupOnly'] == true;
    final verification = principal.jobUses(iiOsCodexAuthFinalizeWorkflow);
    if ((!verification && !principal.jobUses(iiOsCodexAuthWorkflow)) ||
        (principal.runAttempt != 1 && !cleanupOnly) ||
        session['repository'] != principal.repository ||
        session['repositoryId'] != principal.repositoryId ||
        session[verification ? 'verificationRunId' : 'runId'] !=
            principal.runId ||
        (session[verification ? 'verificationRunAttempt' : 'runAttempt'] !=
                principal.runAttempt &&
            (!cleanupOnly ||
                session[verification ? 'verificationRunAttempt' : 'runAttempt']
                    is! int ||
                principal.runAttempt <=
                    (session[verification
                            ? 'verificationRunAttempt'
                            : 'runAttempt']!
                        as int))) ||
        session[verification ? 'verificationWorkflowSha' : 'workflowSha'] !=
            principal.sha ||
        session['trustedSourceSha'] != principal.sha ||
        session['trustedSourceRef'] != principal.trustedRef) {
      throw credentialConflict;
    }
    final status = session['status'];
    if (operation == 'credential-acquire' &&
        !cleanupOnly &&
        (verification
            ? status != 'awaiting_cleanup'
            : status != 'dispatching')) {
      throw credentialConflict;
    }
    if (operation == 'credential-acquire' &&
        !cleanupOnly &&
        (session['expiresAt'] is! Timestamp ||
            (session['expiresAt']! as Timestamp).toDate().isBefore(
              DateTime.now().toUtc(),
            ))) {
      throw credentialConflict;
    }
    return _credentialOperation(
      requestId,
      operation,
      body,
      CodexCredentialOwner(
        workspaceId: session['workspaceId']! as String,
        subjectId: sessionId,
        purpose: verification ? 'codex-auth-verify' : 'codex-auth',
        principal: principal,
      ),
    );
  }

  Future<Response> _credentialOperation(
    String requestId,
    String operation,
    Map<String, Object?> body,
    CodexCredentialOwner owner,
  ) async {
    return _audited(
      requestId: requestId,
      actor: owner.principal.auditActor,
      workspaceId: owner.workspaceId,
      action: 'codex_auth.$operation',
      targetType: 'credential_binding',
      targetId: codexCredentialBindingId(owner.principal.repositoryId),
      metadata: {
        'repository': owner.principal.repository,
        'purpose': owner.purpose,
      },
      execute: () async {
        final credentials = CodexCredentialStore(store);
        if (operation == 'credential-acquire') {
          final workspace = await store.getWorkspace(owner.workspaceId);
          if (!workspace.containsRepository(owner.principal.repository)) {
            throw credentialConflict;
          }
          Map<String, Object?>? metadata;
          if (owner.initialAuth && body['cleanupOnly'] != true) {
            final github = await githubForWorkspace(workspace);
            metadata = await github.codexAuthSecretVersion(
              workspace,
              repository: owner.principal.repository,
            );
          }
          return credentials.acquire(owner, body, providerMetadata: metadata);
        }
        if (operation == 'credential-commit') {
          return credentials.commit(owner, body);
        }
        // Current grant is rechecked before issuing a provider writer. Never
        // expose the token to runtime inputs, the native harness or workers.
        final workspace = await store.getWorkspace(owner.workspaceId);
        final github = await githubForWorkspace(workspace);
        await credentials.reserveWriter(owner, body);
        final token = await github.issueCodexSecretWriterToken(
          workspace,
          repository: owner.principal.repository,
          repositoryId: owner.principal.repositoryId,
        );
        // Do not reset on mint/persistence failure: its outcome may be unknown.
        await credentials.recordWriterIssued(owner, body, token.expiresAt);
        return {
          'token': token.token,
          'expiresAt': token.expiresAt.toIso8601String(),
        };
      },
    );
  }
}
