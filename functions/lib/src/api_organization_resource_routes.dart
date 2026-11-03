part of 'api.dart';

extension _OrganizationResourceRoutes on IiOsApi {
  Future<Response?> _organizationResourceRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    String organizationId,
    List<String> path,
  ) async {
    if (path.length < 4 || path[3] != 'resources') return null;
    final resources = OrganizationResourceStore(
      store.firestore,
      emulated: store.emulated,
    );

    if (path.length == 4 && request.method == 'GET') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.read,
      );
      return jsonResponse(200, {
        'resources': (await resources.get(organizationId)).toJson(),
      }, requestId: requestId);
    }

    if (path.length == 5 && path[4] == 'promote' && request.method == 'POST') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.integrationsManage,
      );
      final body = await readJsonObject(request);
      final sourceWorkspaceId = requiredString(
        body,
        'sourceWorkspaceId',
        maxLength: 100,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.legacy_resources.promote',
        targetType: 'organization',
        targetId: organizationId,
        metadata: {'sourceWorkspaceId': sourceWorkspaceId},
        execute: () async => (await _promoteLegacyWorkspaceResources(
          this,
          organizationId: organizationId,
          sourceWorkspaceId: sourceWorkspaceId,
        )).toJson(),
      );
    }

    if (path.length == 7 &&
        path[4] == 'gcp' &&
        path[6] == 'validate' &&
        request.method == 'POST') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.integrationsManage,
      );
      final body = await readJsonObject(request);
      final credentials = GcpBootstrapCredentials.parse(
        _requiredResourceMap(body, 'serviceAccount'),
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.gcp_resource.validate_and_save',
        targetType: 'organization_gcp_resource',
        targetId: path[5],
        metadata: {'organizationId': organizationId},
        execute: () async {
          final discovery =
              await GcpBootstrapService(
                organizationId: organizationId,
                brokerServiceAccount: connectedDataApi.brokerServiceAccount,
                controlProjectId: connectedDataApi.controlProjectId,
                controlDatabaseId: connectedDataApi.controlDatabaseId,
                webOrigin: connectedDataApi.webOrigin,
                emulated: store.emulated,
              ).discover(
                credentials: credentials,
                selection: GcpBootstrapSelection(
                  bucket: _optionalResourceString(body, 'bucket'),
                  uploadServiceAccount: _optionalResourceString(
                    body,
                    'uploadServiceAccount',
                  ),
                  workloadIdentityProvider: _optionalResourceString(
                    body,
                    'workloadIdentityProvider',
                  ),
                ),
              );
          final connection = discovery.connection;
          if (connection == null) {
            return {
              'status': 'action_required',
              'checks': discovery.checks
                  .map((check) => check.toJson())
                  .toList(),
              'validatedAt': DateTime.now().toUtc().toIso8601String(),
            };
          }
          _requireOrganizationResourceBoundary(connection);
          final runtime = await DataPlaneConnectionValidator(
            connection: connection,
            firestore: store.firestore,
          ).validate();
          final runtimeChecks = runtime['checks'] as List<Object?>? ?? const [];
          final checks = <Object?>[
            ...discovery.checks.map((check) => check.toJson()),
            ...runtimeChecks,
          ];
          final ready = checks.every(
            (value) => value is Map && value['status'] == 'passed',
          );
          final validation = {
            ...runtime,
            'status': ready ? 'ready' : 'action_required',
            'checks': checks,
          };
          if (validation['status'] == 'ready') {
            await resources.saveBootstrapResources(
              organizationId: organizationId,
              resourceId: path[5],
              name: requiredString(body, 'name', maxLength: 100),
              connection: connection,
              permissions: _resourcePermissions(
                body,
                'permissions',
                gcpResourcePermissions,
              ),
              githubResources: discovery.githubResources
                  .map(
                    (resource) => OrganizationGitHubResource(
                      id: 'github_${resource.appId}_${resource.installationId}',
                      name:
                          'GitHub App ${resource.appId} · installation '
                          '${resource.installationId}',
                      secretGcpResourceId: path[5],
                      appId: resource.appId,
                      privateKeySecret: resource.privateKeySecret,
                      installationId: resource.installationId,
                      repositories: resource.repositories,
                      permissionEnvelope: resource.permissions,
                    ),
                  )
                  .toList(),
            );
          }
          return validation;
        },
      );
    }

    if (path.length == 6 &&
        path[4] == 'runners' &&
        path[5] == 'sync' &&
        request.method == 'POST') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.runnersManage,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.runner_pool.sync',
        targetType: 'organization_runner_pool',
        targetId: 'runner_fleet',
        metadata: {'organizationId': organizationId, 'source': 'fleet_report'},
        execute: () async {
          final runners = discoverFleetRunnerPools(
            await fleetSnapshots.read(organizationId),
          );
          return (await resources.saveRunnerPools(
            organizationId: organizationId,
            runnerPools: runners,
          )).toJson();
        },
      );
    }

    if (path.length == 6 && path[4] == 'runners' && request.method == 'PUT') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.runnersManage,
      );
      final body = await readJsonObject(request);
      final runner = OrganizationRunnerPool(
        id: path[5],
        name: requiredString(body, 'name', maxLength: 100),
        provider: requiredString(body, 'provider', maxLength: 20),
        providerPoolId: requiredString(body, 'providerPoolId', maxLength: 128),
        capabilities: stringList(
          body,
          'capabilities',
          maxItems: 100,
          maxItemLength: 100,
        ).toSet(),
        maxCpu: (body['maxCpu'] as num?)?.toInt() ?? 0,
        maxRamMiB: (body['maxRamMiB'] as num?)?.toInt() ?? 0,
        maxConcurrent: (body['maxConcurrent'] as num?)?.toInt() ?? 0,
        active: body['active'] != false,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'organization.runner_pool.save',
        targetType: 'organization_runner_pool',
        targetId: path[5],
        metadata: {'organizationId': organizationId},
        execute: () async => (await resources.saveRunnerPool(
          organizationId: organizationId,
          runnerPool: runner,
        )).toJson(),
      );
    }

    return null;
  }

  void _requireOrganizationResourceBoundary(DataPlaneConnection candidate) {
    if (!store.emulated &&
        candidate.dataServiceAccount != connectedDataApi.brokerServiceAccount) {
      throw const ApiError(
        400,
        'invalid_broker_identity',
        'The tenant must grant the configured ii-os broker identity.',
      );
    }
    if (candidate.authProjectId != connectedDataApi.controlProjectId ||
        candidate.databaseId != connectedDataApi.controlDatabaseId ||
        candidate.webOrigin != connectedDataApi.webOrigin) {
      throw const ApiError(
        400,
        'invalid_control_plane_boundary',
        'Auth, database, and web origin are fixed by ii-os.',
      );
    }
  }
}

Future<OrganizationResourceCatalog> _promoteLegacyWorkspaceResources(
  IiOsApi api, {
  required String organizationId,
  required String sourceWorkspaceId,
}) async {
  final source = await api.store.getWorkspace(sourceWorkspaceId);
  if (source.organizationId != organizationId) {
    throw const ApiError(
      404,
      'legacy_workspace_not_found',
      'The existing workspace is not available in this organization.',
    );
  }
  final installationId = source.githubInstallationId;
  if (installationId == null || installationId <= 0) {
    throw const ApiError(
      409,
      'legacy_workspace_not_connected',
      'The existing workspace has no GitHub installation to inherit.',
    );
  }
  final github = await api.githubForWorkspace(source);
  final accepted = await github.grantedInstallationResources(source);
  return OrganizationResourceStore(
    api.store.firestore,
    emulated: api.store.emulated,
  ).promoteLegacyWorkspace(
    organizationId: organizationId,
    sourceWorkspaceId: sourceWorkspaceId,
    expectedInstallationId: installationId,
    githubPermissions: accepted.permissions,
    githubRepositories: accepted.repositories,
  );
}

String _optionalResourceString(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value == null) return '';
  if (value is! String || value.length > 500) {
    throw ApiError(400, 'invalid_$key', '$key is invalid.');
  }
  return value.trim();
}

Map<String, Object?> _requiredResourceMap(
  Map<String, Object?> body,
  String key,
) {
  final value = body[key];
  if (value is! Map) {
    throw ApiError(400, 'invalid_$key', '$key must be an object.');
  }
  return value.cast<String, Object?>();
}

Set<String> _resourcePermissions(
  Map<String, Object?> body,
  String key,
  Set<String> defaults,
) {
  if (!body.containsKey(key)) return defaults;
  return stringList(body, key, maxItems: 20, maxItemLength: 100).toSet();
}
