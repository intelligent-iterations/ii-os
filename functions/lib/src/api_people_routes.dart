part of 'api.dart';

extension _PeopleRoutes on IiOsApi {
  Future<Response?> _peopleRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length == 4 && path[3] == 'members' && request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.workspaceRead);
      return jsonResponse(200, {
        'members': await store.listMembers(workspaceId),
      }, requestId: requestId);
    }
    if (path.length == 5 && path[3] == 'members' && request.method == 'PATCH') {
      await store.requireAccess(actor, workspaceId, Capability.membersManage);
      final body = await readJsonObject(request);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'member.update',
        targetType: 'workspace_member',
        targetId: path[4],
        metadata: {'role': body['role']},
        execute: () async {
          final member = await store.updateMember(
            workspaceId: workspaceId,
            actorUid: actor.uid,
            uid: path[4],
            role: WorkspaceRole.parse(body['role']),
            featureClaims: stringList(body, 'featureClaims').toSet(),
          );
          return member.toJson();
        },
      );
    }
    if (path.length == 5 &&
        path[3] == 'members' &&
        path[4] == 'me' &&
        request.method == 'DELETE') {
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'member.leave',
        targetType: 'workspace_member',
        targetId: actor.uid,
        execute: () async {
          await store.leaveWorkspace(workspaceId: workspaceId, actor: actor);
          return {'workspaceId': workspaceId};
        },
      );
    }
    if (path.length == 4 &&
        path[3] == 'invitations' &&
        request.method == 'GET') {
      await store.requireAccess(actor, workspaceId, Capability.membersManage);
      return jsonResponse(200, {
        'invitations': await store.listInvites(workspaceId),
      }, requestId: requestId);
    }
    if (path.length == 4 &&
        path[3] == 'invitations' &&
        request.method == 'POST') {
      final access = await store.requireAccessContext(
        actor,
        workspaceId,
        Capability.membersManage,
      );
      if (access.workspace.organizationId.isNotEmpty) {
        throw const ApiError(
          409,
          'organization_invitation_required',
          'Invite this person to the organization and grant this workspace.',
        );
      }
      final body = await readJsonObject(request);
      final email = requiredString(body, 'email', maxLength: 320).toLowerCase();
      final role = WorkspaceRole.parse(body['role']);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'invitation.create',
        targetType: 'workspace_invitation',
        metadata: {'email': email, 'role': role.value},
        execute: () => store.createInvite(
          workspaceId: workspaceId,
          email: email,
          role: role,
          featureClaims: stringList(body, 'featureClaims').toSet(),
          actor: access.membership,
        ),
      );
    }
    if (path.length == 5 &&
        path[3] == 'invitations' &&
        request.method == 'DELETE') {
      await store.requireAccess(actor, workspaceId, Capability.membersManage);
      final inviteId = _validatedInviteId(path[4]);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: workspaceId,
        action: 'invitation.revoke',
        targetType: 'workspace_invitation',
        targetId: inviteId,
        execute: () =>
            store.revokeInvite(workspaceId: workspaceId, inviteId: inviteId),
      );
    }
    return null;
  }
}

String _validatedInviteId(String value) {
  if (!isValidInvitationId(value)) {
    throw const ApiError(400, 'invalid_invite_id', 'Invitation ID is invalid.');
  }
  return value;
}
