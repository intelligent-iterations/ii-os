part of 'workflow_api.dart';

extension WorkflowCodexVerification on WorkflowApi {
  Future<void> _startStoredSecretVerification({
    required GitHubClient github,
    required Workspace workspace,
    required Map<String, Object?> session,
    required String workspaceId,
    required String repository,
    required String sessionId,
    required GitHubActionsPrincipal principal,
  }) async {
    final reserved = await codexAuth.reserveVerificationDispatch(
      sessionId: sessionId,
      principal: principal,
    );
    if (!reserved) return;
    final nonce = session['verificationNonce'] as String? ?? '';
    final trustedSourceRef = session['trustedSourceRef'] as String? ?? '';
    try {
      await github.dispatchWorkflow(
        workspace,
        repository: repository,
        workflowPath: '.github/workflows/$iiOsAgentTaskWorkflow',
        ref: trustedSourceRef,
        inputs: {
          'operation': 'codex_auth_verify',
          'repository': repository,
          'codex_auth_session_id': sessionId,
          'codex_auth_nonce': nonce,
        },
      );
    } on Object {
      await codexAuth.failSession(
        workspaceId: workspaceId,
        sessionId: sessionId,
        errorCode: 'codex_auth_stored_verification_failed',
        detail:
            'The repository-stored Codex credential could not start its isolated verification run.',
      );
      rethrow;
    }
  }
}
