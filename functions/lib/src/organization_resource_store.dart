import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'api_error.dart';
import 'data_plane_connection.dart';
import 'organization_resources.dart';
import 'organization_store.dart';

/// Mutates the bounded resource catalog embedded on an organization document.
///
/// Keeping the catalog here means session and workspace resolution reuse the
/// organization document they already read. Mutations are explicit and
/// transactional; there is no resource listener or collection fan-out.
final class OrganizationResourceStore {
  const OrganizationResourceStore(this.firestore, {this.emulated = false});

  final Firestore firestore;
  final bool emulated;

  Future<OrganizationResourceCatalog> get(String organizationId) async {
    final snapshot = await firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const ApiError(
        404,
        'organization_not_found',
        'Organization not found.',
      );
    }
    return OrganizationResourceCatalog.fromOrganizationData(
      organizationId,
      data,
      emulated: emulated,
    );
  }

  Future<OrganizationResourceCatalog> saveConnectionPair({
    required String organizationId,
    required String gcpResourceId,
    required String githubResourceId,
    required String gcpName,
    required String githubName,
    required DataPlaneConnection connection,
    required int installationId,
    required Set<String> repositories,
    Set<String> gcpPermissions = gcpResourcePermissions,
    Set<String> githubPermissions = const {
      'actions:write',
      'contents:write',
      'deployments:read',
      'pull_requests:write',
    },
  }) {
    if (!connection.isOrganizationBound ||
        connection.organizationId != organizationId) {
      throw const ApiError(
        400,
        'organization_resource_mismatch',
        'The connection belongs to a different organization.',
      );
    }
    return _mutate(organizationId, (catalog, _) {
      return catalog
          .upsertGcp(
            OrganizationGcpResource(
              id: gcpResourceId,
              name: gcpName,
              connection: connection,
              permissionEnvelope: gcpPermissions,
            ),
          )
          .upsertGitHub(
            OrganizationGitHubResource(
              id: githubResourceId,
              name: githubName,
              secretGcpResourceId: gcpResourceId,
              appId: connection.githubAppId,
              privateKeySecret: connection.githubAppSecret,
              installationId: installationId,
              repositories: repositories,
              permissionEnvelope: githubPermissions,
            ),
          );
    });
  }

  Future<OrganizationResourceCatalog> saveGcpResource({
    required String organizationId,
    required String resourceId,
    required String name,
    required DataPlaneConnection connection,
    required Set<String> permissions,
  }) {
    if (!connection.isOrganizationBound ||
        connection.organizationId != organizationId) {
      throw const ApiError(
        400,
        'organization_resource_mismatch',
        'The GCP resource belongs to a different organization.',
      );
    }
    return _mutate(
      organizationId,
      (catalog, _) => catalog.upsertGcp(
        OrganizationGcpResource(
          id: resourceId,
          name: name,
          connection: connection,
          permissionEnvelope: permissions,
        ),
      ),
    );
  }

  Future<OrganizationResourceCatalog> saveBootstrapResources({
    required String organizationId,
    required String resourceId,
    required String name,
    required DataPlaneConnection connection,
    required Set<String> permissions,
    required List<OrganizationGitHubResource> githubResources,
  }) {
    if (!connection.isOrganizationBound ||
        connection.organizationId != organizationId) {
      throw const ApiError(
        400,
        'organization_resource_mismatch',
        'The GCP resource belongs to a different organization.',
      );
    }
    return _mutate(organizationId, (catalog, _) {
      var updated = catalog.upsertGcp(
        OrganizationGcpResource(
          id: resourceId,
          name: name,
          connection: connection,
          permissionEnvelope: permissions,
        ),
      );
      for (final resource in githubResources) {
        updated = updated.upsertGitHub(resource);
      }
      return updated;
    });
  }

  Future<OrganizationResourceCatalog> saveRunnerPool({
    required String organizationId,
    required OrganizationRunnerPool runnerPool,
  }) =>
      _mutate(organizationId, (catalog, _) => catalog.upsertRunner(runnerPool));

  Future<OrganizationResourceCatalog> saveRunnerPools({
    required String organizationId,
    required List<OrganizationRunnerPool> runnerPools,
  }) => _mutate(
    organizationId,
    (catalog, _) => catalog.upsertRunners(runnerPools),
  );

  /// Exposes one already-working V1 workspace connection to sibling projects.
  ///
  /// This is reference promotion, not credential migration. The source
  /// workspace is read and authenticated inside the same transaction and is
  /// never modified. The legacy binding remains authoritative until an
  /// Organization Admin rotates the resource through the current bootstrap.
  Future<OrganizationResourceCatalog> promoteLegacyWorkspace({
    required String organizationId,
    required String sourceWorkspaceId,
    required int expectedInstallationId,
    required Set<String> githubPermissions,
    required Set<String> githubRepositories,
  }) async {
    final organizationRef = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    final workspaceRef = firestore
        .collection('workspaces')
        .doc(sourceWorkspaceId);
    late OrganizationResourceCatalog saved;
    await firestore.runTransaction<void>((transaction) async {
      final organizationSnapshot = await transaction.get(organizationRef);
      final workspaceSnapshot = await transaction.get(workspaceRef);
      final organization = organizationSnapshot.data();
      final workspace = workspaceSnapshot.data();
      if (!organizationSnapshot.exists || organization == null) {
        throw const ApiError(
          404,
          'organization_not_found',
          'Organization not found.',
        );
      }
      if (!workspaceSnapshot.exists ||
          workspace == null ||
          workspace['organizationId'] != organizationId) {
        throw const ApiError(
          404,
          'legacy_workspace_not_found',
          'The existing workspace is not available in this organization.',
        );
      }
      final rawConnection = workspace['connection'];
      if (rawConnection is! Map) {
        throw const ApiError(
          409,
          'legacy_workspace_not_connected',
          'The existing workspace has no connection to inherit.',
        );
      }
      late DataPlaneConnection connection;
      try {
        connection = DataPlaneConnection.fromJson(
          rawConnection.cast<String, Object?>(),
          emulated: emulated,
        );
        final current = OrganizationResourceCatalog.fromOrganizationData(
          organizationId,
          organization,
          emulated: emulated,
        );
        final installationId =
            (workspace['githubInstallationId'] as num?)?.toInt() ??
            (organization['githubInstallationId'] as num?)?.toInt() ??
            current.github(legacyGithubResourceId)?.installationId;
        if (installationId != expectedInstallationId) {
          throw const ApiError(
            409,
            'legacy_workspace_connection_changed',
            'The GitHub installation changed while it was being verified.',
          );
        }
        saved = promoteLegacyWorkspaceResources(
          current: current,
          organizationId: organizationId,
          sourceWorkspaceId: sourceWorkspaceId,
          connection: connection,
          installationId: installationId,
          repositories: githubRepositories,
          githubPermissions: githubPermissions,
        );
      } on FormatException {
        throw const ApiError(
          409,
          'legacy_workspace_connection_invalid',
          'The existing workspace connection cannot be inherited safely.',
        );
      }
      final errors = saved.validateForOrganization(organizationId);
      if (errors.isNotEmpty) {
        throw ApiError(
          409,
          'legacy_workspace_connection_invalid',
          'The existing workspace connection cannot be inherited safely.',
          details: {'errors': errors.toList()..sort()},
        );
      }
      transaction.update(organizationRef, {
        for (final entry in saved.toJson().entries)
          FieldPath([entry.key]): entry.value,
        FieldPath(const ['updatedAt']): Timestamp.now(),
      });
    });
    return saved;
  }

  /// Compatibility entrypoint for the singular connection route.
  Future<OrganizationResourceCatalog> savePrimaryConnection({
    required String organizationId,
    required DataPlaneConnection connection,
  }) => _mutate(organizationId, (catalog, _) {
    final existing =
        catalog.gcp(defaultGcpResourceId) ?? catalog.gcp(legacyGcpResourceId);
    return catalog.upsertGcp(
      OrganizationGcpResource(
        id: existing?.id ?? defaultGcpResourceId,
        name: existing?.name ?? 'Primary GCP project',
        connection: connection,
        permissionEnvelope:
            existing?.permissionEnvelope ?? gcpResourcePermissions,
      ),
    );
  }, compatibilityFields: {'connection': connection.toJson()});

  Future<OrganizationResourceCatalog> savePrimaryGitHubConfiguration({
    required String organizationId,
    required int? installationId,
  }) => _mutate(organizationId, (catalog, data) {
    final existing =
        catalog.github(defaultGithubResourceId) ??
        catalog.github(legacyGithubResourceId);
    if (installationId == null) {
      if (existing == null) return catalog;
      return catalog.upsertGitHub(
        OrganizationGitHubResource(
          id: existing.id,
          name: existing.name,
          secretGcpResourceId: existing.secretGcpResourceId,
          appId: existing.appId,
          privateKeySecret: existing.privateKeySecret,
          installationId: existing.installationId,
          repositories: existing.repositories,
          permissionEnvelope: existing.permissionEnvelope,
          active: false,
        ),
      );
    }
    final gcp =
        catalog.gcp(defaultGcpResourceId) ??
        catalog.gcp(legacyGcpResourceId) ??
        catalog.gcpResources.where((item) => item.active).firstOrNull;
    if (gcp == null) {
      throw const ApiError(
        409,
        'organization_gcp_resource_required',
        'Connect a GCP resource before adding a GitHub App.',
      );
    }
    return catalog.upsertGitHub(
      OrganizationGitHubResource(
        id: existing?.id ?? defaultGithubResourceId,
        name: existing?.name ?? 'Primary GitHub App',
        secretGcpResourceId: gcp.id,
        appId: gcp.connection.githubAppId,
        privateKeySecret: gcp.connection.githubAppSecret,
        installationId: installationId,
        repositories: existing?.repositories ?? _strings(data['repositories']),
        permissionEnvelope:
            existing?.permissionEnvelope ??
            const {
              'actions:write',
              'contents:write',
              'deployments:read',
              'pull_requests:write',
            },
      ),
    );
  }, compatibilityFields: {'githubInstallationId': installationId});

  Future<OrganizationResourceCatalog> addPrimaryRepositories({
    required String organizationId,
    required Set<String> repositories,
  }) {
    final compatibilityFields = <String, Object?>{};
    return _mutate(organizationId, (catalog, data) {
      final legacyRepositories = _strings(data['repositories']);
      compatibilityFields['repositories'] = ({
        ...legacyRepositories,
        ...repositories,
      }.toList()..sort());
      final existing =
          catalog.github(defaultGithubResourceId) ??
          catalog.github(legacyGithubResourceId);
      if (existing == null) return catalog;
      return catalog.upsertGitHub(
        OrganizationGitHubResource(
          id: existing.id,
          name: existing.name,
          secretGcpResourceId: existing.secretGcpResourceId,
          appId: existing.appId,
          privateKeySecret: existing.privateKeySecret,
          installationId: existing.installationId,
          repositories: {...existing.repositories, ...repositories},
          permissionEnvelope: existing.permissionEnvelope,
          active: existing.active,
        ),
      );
    }, compatibilityFields: compatibilityFields);
  }

  Future<OrganizationResourceCatalog> _mutate(
    String organizationId,
    OrganizationResourceCatalog Function(
      OrganizationResourceCatalog current,
      Map<String, Object?> data,
    )
    change, {
    Map<String, Object?> compatibilityFields = const {},
  }) async {
    final ref = firestore
        .collection(OrganizationStore.organizations)
        .doc(organizationId);
    late OrganizationResourceCatalog saved;
    await firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw const ApiError(
          404,
          'organization_not_found',
          'Organization not found.',
        );
      }
      saved = change(
        OrganizationResourceCatalog.fromOrganizationData(
          organizationId,
          data,
          emulated: emulated,
        ),
        data,
      );
      final errors = saved.validateForOrganization(organizationId);
      if (errors.isNotEmpty) {
        throw ApiError(
          400,
          'invalid_organization_resources',
          'The organization resource catalog is invalid.',
          details: {'errors': errors.toList()..sort()},
        );
      }
      transaction.update(ref, {
        for (final entry in saved.toJson().entries)
          FieldPath([entry.key]): entry.value,
        for (final entry in compatibilityFields.entries)
          FieldPath([entry.key]): entry.value,
        FieldPath(const ['updatedAt']): Timestamp.now(),
      });
    });
    return saved;
  }
}

Set<String> _strings(Object? value) => value is List<Object?>
    ? value.whereType<String>().map((item) => item.trim()).toSet()
    : const {};

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
