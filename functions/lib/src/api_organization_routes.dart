part of 'api.dart';

extension _OrganizationRoutes on IiOsApi {
  /// Everything under `/v1/organizations`, plus accepting an invitation.
  ///
  /// Returns null when the path belongs to some other surface, so the caller
  /// can keep matching.
  Future<Response?> _organizationRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    List<String> path,
  ) async {
    if (path.length == 4 &&
        path[0] == 'v1' &&
        path[1] == 'organization-invitations' &&
        path[3] == 'accept' &&
        request.method == 'POST') {
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.invitation.accept',
        targetType: 'organization_invitation',
        targetId: path[2],
        execute: () async =>
            (await organizationInvitations.accept(path[2], actor)).toJson(),
      );
    }

    if (path.length == 2 &&
        path[0] == 'v1' &&
        path[1] == 'organization-invitations' &&
        request.method == 'GET') {
      return jsonResponse(200, {
        'invitations': await organizationInvitations.availableTo(actor),
      }, requestId: requestId);
    }

    if (path.length == 2 &&
        path[0] == 'v1' &&
        path[1] == 'organizations' &&
        request.method == 'POST') {
      final body = await readJsonObject(request);
      final name = requiredString(body, 'name', maxLength: 100);
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.create',
        targetType: 'organization',
        metadata: {'name': name},
        execute: () async => (await organizations.createOrganization(
          name: name,
          actor: actor,
        )).toJson(),
      );
    }

    if (path.length < 3 || path[0] != 'v1' || path[1] != 'organizations') {
      return null;
    }
    final organizationId = path[2];

    final resourceResponse = await _organizationResourceRoute(
      request,
      requestId,
      actor,
      organizationId,
      path,
    );
    if (resourceResponse != null) return resourceResponse;

    final promptGuideResponse = await _organizationPromptGuideRoute(
      request,
      requestId,
      actor,
      organizationId,
      path,
    );
    if (promptGuideResponse != null) return promptGuideResponse;

    if (path.length == 3 && request.method == 'GET') {
      final membership = await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.read,
      );
      return jsonResponse(200, {
        'organization': (await organizations.getOrganization(
          organizationId,
        )).toJson(),
        'membership': membership.toJson(),
      }, requestId: requestId);
    }

    if (path.length == 3 && request.method == 'DELETE') {
      final membership = await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.membersManage,
      );
      if (membership.role != OrganizationRole.owner) {
        throw const ApiError(
          403,
          'organization_owner_required',
          'Only an organization owner can delete this organization.',
        );
      }
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.delete',
        targetType: 'organization',
        targetId: organizationId,
        execute: () => organizations.deleteOrganization(
          organizationId: organizationId,
          actor: membership,
        ),
      );
    }

    if (path.length == 4 && path[3] == 'people' && request.method == 'GET') {
      final membership = await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.workspacesAccessManage,
      );
      final results = await Future.wait<List<Map<String, Object?>>>([
        organizations.listPeople(organizationId),
        organizations.listWorkspacesForPeople(organizationId),
        membership.allows(OrganizationCapability.membersManage)
            ? organizationInvitations.listForOrganization(organizationId)
            : Future.value(const <Map<String, Object?>>[]),
      ]);
      return jsonResponse(200, {
        'members': results[0],
        'workspaces': results[1],
        'invitations': results[2],
        'workspaceRoles': workspacePermissionRoleCatalog(),
      }, requestId: requestId);
    }

    if (path.length == 5 && path[3] == 'members' && request.method == 'PATCH') {
      final membership = await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.membersManage,
      );
      final body = await readJsonObject(request);
      final role = OrganizationRole.parse(body['role']);
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.member.update',
        targetType: 'organization_member',
        targetId: path[4],
        metadata: {'role': role.value},
        execute: () async => (await organizations.updateOrganizationMember(
          organizationId: organizationId,
          actorUid: membership.uid,
          uid: path[4],
          role: role,
          featureClaims: stringList(body, 'featureClaims').toSet(),
        )).toJson(),
      );
    }

    if (path.length == 5 &&
        path[3] == 'members' &&
        request.method == 'DELETE') {
      final membership = await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.membersManage,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.member.remove',
        targetType: 'organization_member',
        targetId: path[4],
        execute: () async => {
          'uid': path[4],
          'workspaceAssignmentsRemoved': await organizations
              .removeOrganizationMember(
                organizationId: organizationId,
                actorUid: membership.uid,
                uid: path[4],
              ),
        },
      );
    }

    if (path.length == 6 &&
        path[3] == 'members' &&
        path[5] == 'workspaces' &&
        request.method == 'GET') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.workspacesAccessManage,
      );
      return jsonResponse(200, {
        'access': await organizations.listMemberWorkspaceAccess(
          organizationId: organizationId,
          uid: path[4],
        ),
      }, requestId: requestId);
    }

    if (path.length == 4 &&
        path[3] == 'workspaces' &&
        request.method == 'POST') {
      final membership = await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.workspacesCreate,
      );
      final body = await readJsonObject(request);
      final name = requiredString(body, 'name', maxLength: 100);
      final environment = body['environment'] as String? ?? 'dev';
      final inheritFromWorkspaceId =
          body['inheritFromWorkspaceId']?.toString().trim() ?? '';
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.workspace.create',
        targetType: 'workspace',
        metadata: {
          'organizationId': organizationId,
          'environment': environment,
        },
        execute: () async {
          if (inheritFromWorkspaceId.isNotEmpty) {
            await _promoteLegacyWorkspaceResources(
              this,
              organizationId: organizationId,
              sourceWorkspaceId: inheritFromWorkspaceId,
            );
          }
          return (await store.createWorkspace(
            organizationId: organizationId,
            organizationActor: membership,
            name: name,
            environment: environment,
          )).toJson();
        },
      );
    }

    if (path.length == 4 &&
        path[3] == 'invitations' &&
        request.method == 'POST') {
      final membership = await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.membersManage,
      );
      final organization = await organizations.getOrganization(organizationId);
      final body = await readJsonObject(request);
      final email = requiredString(body, 'email', maxLength: 320);
      final role = OrganizationRole.parse(body['role']);
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.invitation.create',
        targetType: 'organization_invitation',
        metadata: {'email': email.toLowerCase(), 'role': role.value},
        execute: () => organizationInvitations.invite(
          organizationId: organizationId,
          organizationName: organization.name,
          email: email,
          role: role,
          featureClaims: stringList(body, 'featureClaims').toSet(),
          workspaceGrants: stringList(body, 'workspaceGrants'),
          actor: membership,
          clientIp: _clientIp(request),
          requestId: requestId,
        ),
      );
    }

    if (path.length == 5 &&
        path[3] == 'invitations' &&
        request.method == 'DELETE') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.membersManage,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.invitation.revoke',
        targetType: 'organization_invitation',
        targetId: path[4],
        execute: () async {
          await organizationInvitations.revoke(
            organizationId: organizationId,
            invitationId: path[4],
          );
          return {'invitationId': path[4]};
        },
      );
    }

    // Turning a person's access to one project on or off. Deliberately a
    // separate verb from inviting: the person is already in the tenant, so
    // there is nothing to accept and no mail that grants anything.
    if (path.length == 6 &&
        path[3] == 'workspace-access' &&
        request.method == 'PATCH') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.workspacesAccessManage,
      );
      final body = await readJsonObject(request);
      final suspended = body['suspended'] == true;
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: path[4],
        action: suspended
            ? 'organization.workspace_access.suspend'
            : 'organization.workspace_access.restore',
        targetType: 'workspace_member',
        targetId: path[5],
        execute: () async {
          final result = await organizations.setWorkspaceAccess(
            organizationId: organizationId,
            workspaceId: path[4],
            uid: path[5],
            suspended: suspended,
          );
          if (result['granted'] == true) {
            final delivered = await organizationInvitations
                .notifyWorkspaceAccess(
                  email: result['email'] as String? ?? '',
                  organizationName:
                      result['organizationName'] as String? ?? 'Organization',
                  workspaceId: result['workspaceId'] as String? ?? '',
                  workspaceName:
                      result['workspaceName'] as String? ?? 'Workspace',
                );
            return {...result, 'notificationDelivered': delivered};
          }
          return result;
        },
      );
    }

    return null;
  }

  /// Resolves organization membership from the database, never from the
  /// request, and refuses when it does not carry [capability].
  Future<OrganizationMembership> _requireOrganization(
    AuthenticatedUser actor,
    String organizationId,
    OrganizationCapability capability,
  ) async {
    final membership = await organizations.getMembership(
      organizationId,
      actor.uid,
    );
    if (membership == null || !membership.allows(capability)) {
      // The same message whether the organization does not exist or the caller
      // is not in it: a distinct "not found" would let anyone enumerate which
      // tenants exist.
      throw const ApiError(
        403,
        'forbidden',
        'Your organization role does not allow this action.',
      );
    }
    return membership;
  }
}
