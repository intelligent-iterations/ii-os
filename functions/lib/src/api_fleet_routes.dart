part of 'api.dart';

extension _FleetRoutes on IiOsApi {
  bool _isFleetIngestRoute(List<String> path) =>
      path.length == 5 &&
      path[0] == 'v1' &&
      path[1] == 'organizations' &&
      path[3] == 'fleet' &&
      path[4] == 'snapshot';

  /// A tenant's own fleet reporting in, authenticated by a reporting
  /// credential rather than a signed-in person.
  ///
  /// Matched before Firebase authentication because a publisher is a daemon on
  /// the tenant's hardware and never holds a session.
  Future<Response> _fleetIngestRoute(
    Request request,
    String requestId,
    List<String> path,
  ) async {
    if (request.method != 'POST') {
      throw const ApiError(
        405,
        'method_not_allowed',
        'Use POST to report fleet state.',
      );
    }
    final principal = await fleetReportingKeys.authenticate(request);
    final organizationId = path[2];
    if (principal.organizationId != organizationId) {
      throw const ApiError(
        403,
        'fleet_key_organization_mismatch',
        'The reporting credential is not authorized for this organization.',
      );
    }
    final snapshot = FleetSnapshot.fromJson(await readJsonObject(request));
    return _audited(
      requestId: requestId,
      actor: principal.auditActor,
      action: 'fleet.snapshot.record',
      targetType: 'fleet_snapshot',
      targetId: organizationId,
      metadata: {
        'machineCount': snapshot.hosts.length,
        'auth': 'fleet_reporting_key',
      },
      execute: () => fleetSnapshots.record(
        organizationId: organizationId,
        snapshot: snapshot,
        reporterId: 'key:${principal.keyId}',
      ),
    );
  }

  /// Everything a signed-in person may ask about an organization's fleet.
  ///
  /// Returns null when the path belongs to some other surface so the caller can
  /// keep matching.
  Future<Response?> _fleetRoute(
    Request request,
    String requestId,
    AuthenticatedUser actor,
    List<String> path,
  ) async {
    if (path.length < 4 ||
        path[0] != 'v1' ||
        path[1] != 'organizations' ||
        path[3] != 'fleet') {
      return null;
    }
    final organizationId = path[2];

    if (path.length == 4 && request.method == 'GET') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.auditRead,
      );
      return jsonResponse(200, {
        'fleet': await fleetSnapshots.read(organizationId),
      }, requestId: requestId);
    }

    if (path.length == 5 && path[4] == 'keys') {
      // Reporting credentials are credentials: an Admin holds this only when an
      // Owner has handed it over on purpose, the same way the GitHub App key is
      // handled.
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.credentialsManage,
      );
      if (request.method == 'GET') {
        return jsonResponse(200, {
          'credentials': await fleetReportingKeys.list(organizationId),
        }, requestId: requestId);
      }
      if (request.method == 'POST') {
        final body = await readJsonObject(request);
        return _audited(
          requestId: requestId,
          actor: actor,
          action: 'fleet.credential.issue',
          targetType: 'fleet_reporting_key',
          targetId: organizationId,
          execute: () => fleetReportingKeys.issue(
            organizationId: organizationId,
            label: '${body['label'] ?? ''}',
            createdBy: actor.uid,
          ),
        );
      }
    }

    if (path.length == 6 && path[4] == 'keys' && request.method == 'DELETE') {
      await _requireOrganization(
        actor,
        organizationId,
        OrganizationCapability.credentialsManage,
      );
      return _audited(
        requestId: requestId,
        actor: actor,
        action: 'fleet.credential.revoke',
        targetType: 'fleet_reporting_key',
        targetId: path[5],
        execute: () => fleetReportingKeys.revoke(
          organizationId: organizationId,
          keyId: path[5],
          revokedBy: actor.uid,
        ),
      );
    }

    return null;
  }
}
