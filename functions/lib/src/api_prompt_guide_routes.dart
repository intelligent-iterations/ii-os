part of 'api.dart';

/// `/v1/workspaces/{id}/prompt-guides` and `/v1/organizations/{id}/prompt-guides`.
///
/// One extension serving both tiers, because the two differ only in who is
/// allowed to write and which scope the edit lands in. Splitting them would
/// mean maintaining the same five shapes twice and letting them drift.
extension _PromptGuideRoutes on IiOsApi {
  Future<Response?> _workspacePromptGuideRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String workspaceId,
    List<String> path,
  ) async {
    if (path.length < 4 || path[3] != 'prompt-guides') return null;
    final workspace = await store.getWorkspace(workspaceId);
    return _promptGuideRoute(
      request: request,
      requestId: requestId,
      actor: actor,
      path: path.sublist(4),
      scope: PromptGuideScope.workspace,
      scopeId: workspaceId,
      organizationId: workspace.organizationId,
      workspaceId: workspaceId,
      auditWorkspaceId: workspaceId,
      requireRead: () =>
          store.requireAccess(actor, workspaceId, Capability.workspaceRead),
      requireWrite: () =>
          store.requireAccess(actor, workspaceId, Capability.workspaceManage),
    );
  }

  Future<Response?> _organizationPromptGuideRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String organizationId,
    List<String> path,
  ) async {
    if (path.length < 4 || path[3] != 'prompt-guides') return null;
    return _promptGuideRoute(
      request: request,
      requestId: requestId,
      actor: actor,
      path: path.sublist(4),
      scope: PromptGuideScope.organization,
      scopeId: organizationId,
      organizationId: organizationId,
      workspaceId: '',
      auditWorkspaceId: '',
      requireRead: () => _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.read,
      ),
      requireWrite: () => _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.manage,
      ),
    );
  }

  Future<Response?> _promptGuideRoute({
    required Request request,
    required String requestId,
    required AuthenticatedUser actor,
    required List<String> path,
    required PromptGuideScope scope,
    required String scopeId,
    required String organizationId,
    required String workspaceId,
    required String auditWorkspaceId,
    required Future<Object?> Function() requireRead,
    required Future<Object?> Function() requireWrite,
  }) async {
    // The list and one guide's detail.
    if (path.isEmpty && request.method == 'GET') {
      await requireRead();
      return jsonResponse(200, {
        'guides': await _promptGuideSummaries(
          scope: scope,
          scopeId: scopeId,
          organizationId: organizationId,
          workspaceId: workspaceId,
        ),
      }, requestId: requestId);
    }
    if (path.isEmpty) return null;
    final guideId = Uri.decodeComponent(path.first);
    final definition = promptGuidesById[guideId];
    if (definition == null) {
      throw const ApiError(
        404,
        'prompt_guide_not_found',
        'That prompting guide is not one ii-os uses.',
      );
    }

    if (path.length == 1 && request.method == 'GET') {
      await requireRead();
      return jsonResponse(
        200,
        await _promptGuideDetail(
          definition: definition,
          scope: scope,
          scopeId: scopeId,
          organizationId: organizationId,
          workspaceId: workspaceId,
        ),
        requestId: requestId,
      );
    }

    if (path.length == 2 && path[1] == 'versions' && request.method == 'GET') {
      await requireRead();
      final revisions = await promptGuides.history(
        scope: scope,
        scopeId: scopeId,
        guideId: guideId,
      );
      return jsonResponse(200, {
        'versions': revisions.map((item) => item.toJson()).toList(),
      }, requestId: requestId);
    }

    if (path.length == 1 && request.method == 'PUT') {
      await requireWrite();
      final body = await readJsonObject(request);
      final text = requiredString(
        body,
        'body',
        maxLength: promptGuideMaxLength,
      );
      final note = switch (body['note']) {
        final String value when value.trim().length <= 200 => value.trim(),
        null => '',
        _ => throw const ApiError(
          400,
          'invalid_prompt_guide_note',
          'Keep the note under 200 characters.',
        ),
      };
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: auditWorkspaceId,
        action: 'prompt_guide.save',
        targetType: 'prompt_guide',
        targetId: '${scope.value}:$scopeId:$guideId',
        metadata: {'guideId': guideId, 'scope': scope.value},
        execute: () async => (await promptGuides.save(
          scope: scope,
          scopeId: scopeId,
          guideId: guideId,
          body: text,
          actorUid: actor.uid,
          note: note,
        )).toJson(),
      );
    }

    if (path.length == 1 && request.method == 'DELETE') {
      await requireWrite();
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: auditWorkspaceId,
        action: 'prompt_guide.reset',
        targetType: 'prompt_guide',
        targetId: '${scope.value}:$scopeId:$guideId',
        metadata: {'guideId': guideId, 'scope': scope.value},
        execute: () async {
          await promptGuides.reset(
            scope: scope,
            scopeId: scopeId,
            guideId: guideId,
            actorUid: actor.uid,
          );
          return {'guideId': guideId, 'reset': true};
        },
      );
    }

    if (path.length == 2 && path[1] == 'restore' && request.method == 'POST') {
      await requireWrite();
      final body = await readJsonObject(request);
      final revisionId = requiredString(body, 'versionId', maxLength: 64);
      return _audited(
        requestId: requestId,
        actor: actor,
        workspaceId: auditWorkspaceId,
        action: 'prompt_guide.restore',
        targetType: 'prompt_guide',
        targetId: '${scope.value}:$scopeId:$guideId',
        metadata: {'guideId': guideId, 'scope': scope.value},
        execute: () async => (await promptGuides.restore(
          scope: scope,
          scopeId: scopeId,
          guideId: guideId,
          revisionId: revisionId,
          actorUid: actor.uid,
        )).toJson(),
      );
    }
    return null;
  }

  /// The list view: every guide, and where its current text comes from.
  ///
  /// Deliberately carries no bodies. The shipped guides run to several thousand
  /// characters each, and a settings screen that has to download every one of
  /// them to draw a list is a settings screen nobody opens twice.
  Future<List<Map<String, Object?>>> _promptGuideSummaries({
    required PromptGuideScope scope,
    required String scopeId,
    required String organizationId,
    required String workspaceId,
  }) async {
    final organization = organizationId.isEmpty
        ? const <String, PromptGuideOverride>{}
        : await promptGuides.read(
            PromptGuideScope.organization,
            organizationId,
          );
    final workspace = workspaceId.isEmpty
        ? const <String, PromptGuideOverride>{}
        : await promptGuides.read(PromptGuideScope.workspace, workspaceId);
    return [
      for (final definition in promptGuideCatalog)
        _summary(
          definition: definition,
          scope: scope,
          organization: organization[definition.id],
          workspace: workspace[definition.id],
        ),
    ];
  }

  Future<Map<String, Object?>> _promptGuideDetail({
    required PromptGuideDefinition definition,
    required PromptGuideScope scope,
    required String scopeId,
    required String organizationId,
    required String workspaceId,
  }) async {
    final organization = organizationId.isEmpty
        ? null
        : (await promptGuides.read(
            PromptGuideScope.organization,
            organizationId,
          ))[definition.id];
    final workspace = workspaceId.isEmpty
        ? null
        : (await promptGuides.read(
            PromptGuideScope.workspace,
            workspaceId,
          ))[definition.id];
    return {
      ..._summary(
        definition: definition,
        scope: scope,
        organization: organization,
        workspace: workspace,
      ),
      'defaultBody': definition.body,
      'organizationBody': organization?.body,
      'workspaceBody': workspace?.body,
      'effectiveBody': workspace?.body ?? organization?.body ?? definition.body,
      // The text this scope is editing, which is not always the one in force:
      // an organization admin editing a guide a workspace has overridden is
      // changing what every *other* project sees.
      'scopeBody': scope == PromptGuideScope.workspace
          ? workspace?.body
          : organization?.body,
    };
  }

  Map<String, Object?> _summary({
    required PromptGuideDefinition definition,
    required PromptGuideScope scope,
    required PromptGuideOverride? organization,
    required PromptGuideOverride? workspace,
  }) {
    final effective = workspace ?? organization;
    return {
      'id': definition.id,
      'label': definition.label,
      'summary': definition.summary,
      'modality': definition.modality.value,
      'authoredByIiOs': definition.authoredByIiOs,
      'defaultLength': definition.body.trim().length,
      'source': switch (effective) {
        _ when workspace != null => 'workspace',
        _ when organization != null => 'organization',
        _ => 'default',
      },
      'editedInThisScope':
          (scope == PromptGuideScope.workspace ? workspace : organization) !=
          null,
      'version': effective?.version ?? 0,
      'updatedBy': effective?.updatedBy ?? '',
      'updatedAt': effective?.updatedAt.toUtc().toIso8601String(),
    };
  }
}
