part of 'workflow_api.dart';

extension WorkflowPermissionApproval on WorkflowApi {
  /// Authorizes the permission installer against a recorded human approval.
  ///
  /// The run reaches this route twice: once before it installs anything, and
  /// once after it has published its result. Both calls prove the same
  /// approval, and neither trusts the run's own account of what it is doing --
  /// every field is compared against what was approved.
  Future<Response> _handlePermissionApproval(
    Request request,
    String requestId,
    List<String> path,
    GitHubActionsPrincipal principal,
  ) async {
    if (request.method != 'POST' ||
        path.length != 4 ||
        !principal.jobUses(iiOsAgentPermissionInstallerWorkflow)) {
      throw const ApiError(404, 'not_found', 'Workflow route not found.');
    }
    final approvalId = path[2];
    final stage = path[3];
    if (stage != 'consume' && stage != 'complete') {
      throw const ApiError(404, 'not_found', 'Workflow route not found.');
    }
    final callback = parseAgentPermissionCallback(
      await readJsonObject(request),
    );
    final approvals = AgentPermissionApprovalStore(store);
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      workspaceId: callback.workspaceId,
      action: 'agent_permission.approval.$stage',
      targetType: 'github_workflow_run',
      targetId: '${principal.runId}:${principal.runAttempt}',
      metadata: {
        'repository': principal.repository,
        'approvalId': approvalId,
        'dispatchId': callback.dispatchId,
        'dispatchFence': callback.dispatchFence,
        'profileId': callback.profileId,
        'profileVersion': callback.profileVersion,
      },
      execute: () async {
        if (stage == 'consume') {
          await approvals.consume(
            principal: principal,
            workspaceId: callback.workspaceId,
            approvalId: approvalId,
            callback: callback,
          );
          return {'authorized': true};
        }
        await approvals.complete(
          principal: principal,
          workspaceId: callback.workspaceId,
          approvalId: approvalId,
          callback: callback,
        );
        return {'completed': true};
      },
    );
  }
}
