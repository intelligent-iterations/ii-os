part of 'api.dart';

extension AgentPermissionRoutes on IiOsApi {
  Future<Response> _agentPermissionRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length == 4 && request.method == 'GET') {
      await store.requireAccess(
        actor,
        workspaceId,
        Capability.agentPermissionsRead,
      );
      final repository = request.url.queryParameters['repository'];
      final ref = request.url.queryParameters['ref'] ?? 'dev';
      if (repository == null) {
        throw const ApiError(
          400,
          'repository_required',
          'Select a repository.',
        );
      }
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      return jsonResponse(200, {
        'profiles': await github.listAgentPermissionProfiles(
          workspace,
          repository: repository,
          ref: ref,
        ),
      }, requestId: requestId);
    }
    if (path.length == 5 && path[4] == 'install' && request.method == 'POST') {
      await store.requireAccess(
        actor,
        workspaceId,
        Capability.agentPermissionsManage,
      );
      final body = await readJsonObject(request);
      final repository = requiredString(body, 'repository', maxLength: 200);
      final ref = requiredString(body, 'ref', maxLength: 200);
      final profile = AgentPermissionProfile.parse(body['profile']);
      requireAgentPermissionRef(ref);
      requireExecutableAgentProfile(profile);
      final workspace = await store.getWorkspace(workspaceId);
      final github = await githubForWorkspace(workspace);
      final bootstrapRef = await github.resolveBootstrapTag(
        workspace,
        repository: repository,
      );
      final approval = await AgentPermissionApprovalStore(store).approve(
        workspaceId: workspaceId,
        repository: repository,
        ref: ref,
        profile: profile,
        actor: actor,
      );
      return await _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'agent_permission.install',
        targetType: 'github_workflow_dispatch',
        targetId: '${profile.id}@${profile.version}',
        metadata: {
          'repository': repository,
          'ref': ref,
          'profileId': profile.id,
          'profileVersion': profile.version,
          'approvalId': approval.approvalId,
          'dispatchId': approval.dispatchId,
          'dispatchFence': approval.dispatchFence,
        },
        execute: () => github.dispatchAgentPermissionInstaller(
          workspace,
          repository: repository,
          ref: bootstrapRef,
          inputs: {
            'profile_id': profile.id,
            'profile_version': profile.version,
            'profile_digest': approval.profileDigest,
            'profile_json': jsonEncode(profile.toJson()),
            'workspace_id': workspaceId,
            'approval_id': approval.approvalId,
            'dispatch_id': approval.dispatchId,
            'dispatch_fence': '${approval.dispatchFence}',
          },
        ),
      );
    }
    throw const ApiError(404, 'not_found', 'Agent permission route not found.');
  }
}
