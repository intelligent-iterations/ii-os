import 'dart:convert';

import 'package:googleapis/cloudresourcemanager/v3.dart' as resource_manager;
import 'package:googleapis/iam/v1.dart' as iam;
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';

import 'api_error.dart';
import 'data_plane_connection.dart';
import 'gcp_github_discovery.dart';

const maxGcpBootstrapCredentialBytes = 64 * 1024;

/// A validated, request-scoped Google service-account credential.
///
/// The raw fields never leave the bootstrap service and are never included in
/// [toString]. Callers must drop this object before building their response.
final class GcpBootstrapCredentials {
  GcpBootstrapCredentials._(this._json, this.projectId, this.email);

  factory GcpBootstrapCredentials.parse(Map<String, Object?> json) {
    if (utf8.encode(jsonEncode(json)).length > maxGcpBootstrapCredentialBytes ||
        json.keys.toSet().difference(_serviceAccountFields).isNotEmpty ||
        json['type'] != 'service_account') {
      throw _invalidServiceAccount;
    }
    String required(String key, int maxLength) {
      final value = json[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > maxLength) {
        throw _invalidServiceAccount;
      }
      return value.trim();
    }

    final projectId = required('project_id', 63);
    final email = required('client_email', 254);
    required('private_key_id', 200);
    final privateKey = required('private_key', 48 * 1024);
    final trimmedPrivateKey = privateKey.trim();
    required('client_id', 100);
    final tokenUri = required('token_uri', 500);
    if (!_projectId.hasMatch(projectId) ||
        !_serviceAccountEmail.hasMatch(email) ||
        !email.endsWith('@$projectId.iam.gserviceaccount.com') ||
        !trimmedPrivateKey.startsWith('-----BEGIN PRIVATE KEY-----') ||
        !trimmedPrivateKey.endsWith('-----END PRIVATE KEY-----') ||
        tokenUri != 'https://oauth2.googleapis.com/token') {
      throw _invalidServiceAccount;
    }
    return GcpBootstrapCredentials._(
      Map<String, Object?>.unmodifiable(json),
      projectId,
      email,
    );
  }

  final Map<String, Object?> _json;
  final String projectId;
  final String email;

  ServiceAccountCredentials googleCredentials() {
    try {
      return ServiceAccountCredentials.fromJson(_json);
    } on Object {
      throw _invalidServiceAccount;
    }
  }

  @override
  String toString() => 'GcpBootstrapCredentials(projectId: $projectId)';
}

final class GcpBootstrapSelection {
  const GcpBootstrapSelection({
    this.bucket = '',
    this.uploadServiceAccount = '',
    this.workloadIdentityProvider = '',
  });

  final String bucket;
  final String uploadServiceAccount;
  final String workloadIdentityProvider;
}

final class GcpBootstrapDiscovery {
  const GcpBootstrapDiscovery({
    required this.connection,
    required this.checks,
    this.githubResources = const [],
  });

  final DataPlaneConnection? connection;
  final List<ConnectionCheck> checks;
  final List<DiscoveredGitHubResource> githubResources;
}

/// Discovers the bounded nonsecret identifiers needed for one GCP resource.
///
/// Authentication exists only for this call. Every list is single-page and
/// fail-closed; more than the bound is reported as an actionable check rather
/// than silently truncating the resource boundary.
final class GcpBootstrapService {
  const GcpBootstrapService({
    required this.organizationId,
    required this.brokerServiceAccount,
    required this.controlProjectId,
    required this.controlDatabaseId,
    required this.webOrigin,
    this.emulated = false,
  });

  final String organizationId;
  final String brokerServiceAccount;
  final String controlProjectId;
  final String controlDatabaseId;
  final String webOrigin;
  final bool emulated;

  Future<GcpBootstrapDiscovery> discover({
    required GcpBootstrapCredentials credentials,
    required GcpBootstrapSelection selection,
  }) async {
    if (emulated) {
      return GcpBootstrapDiscovery(
        connection: DataPlaneConnection(
          workspaceId: '',
          organizationId: organizationId,
          projectId: credentials.projectId,
          projectNumber: '123456789012',
          databaseId: controlDatabaseId,
          region: 'local',
          bucket: selection.bucket.isEmpty
              ? '${credentials.projectId}-assets'
              : selection.bucket,
          dataServiceAccount: brokerServiceAccount,
          uploadServiceAccount: selection.uploadServiceAccount.isEmpty
              ? 'workflow-upload@${credentials.projectId}.iam.gserviceaccount.com'
              : selection.uploadServiceAccount,
          workloadIdentityProvider: selection.workloadIdentityProvider.isEmpty
              ? 'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows'
              : selection.workloadIdentityProvider,
          authProjectId: controlProjectId,
          webOrigin: webOrigin,
          gcpOnly: true,
          emulated: true,
        ),
        checks: const [
          ConnectionCheck(
            id: 'bootstrap_identity',
            label: 'Google service account',
            status: 'passed',
            detail: 'Emulator bootstrap identity accepted.',
          ),
        ],
      );
    }
    late AuthClient client;
    try {
      client = await clientViaServiceAccount(
        credentials.googleCredentials(),
        const ['https://www.googleapis.com/auth/cloud-platform'],
      );
    } on ApiError {
      rethrow;
    } on Object {
      return const GcpBootstrapDiscovery(
        connection: null,
        checks: [
          ConnectionCheck(
            id: 'bootstrap_identity',
            label: 'Google service account',
            status: 'action_required',
            detail: 'Google did not accept this service account.',
          ),
        ],
      );
    }
    try {
      return await _discoverWithClient(client, credentials, selection);
    } finally {
      client.close();
    }
  }

  Future<GcpBootstrapDiscovery> _discoverWithClient(
    AuthClient client,
    GcpBootstrapCredentials credentials,
    GcpBootstrapSelection selection,
  ) async {
    try {
      final projectFuture = resource_manager.CloudResourceManagerApi(
        client,
      ).projects.get('projects/${credentials.projectId}');
      final bucketsFuture = storage.StorageApi(client).buckets.list(
        credentials.projectId,
        maxResults: 21,
        projection: 'noAcl',
      );
      final accountsFuture = iam.IamApi(client).projects.serviceAccounts.list(
        'projects/${credentials.projectId}',
        pageSize: 101,
      );
      final githubFuture = GcpGitHubDiscoveryService(
        client: client,
        projectId: credentials.projectId,
        organizationId: organizationId,
      ).discover();
      final values = await Future.wait<Object>([
        projectFuture,
        bucketsFuture,
        accountsFuture,
        githubFuture,
      ]);
      final project = values[0] as resource_manager.Project;
      final buckets = values[1] as storage.Buckets;
      final accounts = values[2] as iam.ListServiceAccountsResponse;
      final github = values[3] as GcpGitHubDiscovery;
      final projectNumber = project.name?.split('/').last ?? '';
      if (!_projectNumber.hasMatch(projectNumber)) {
        return _failed(
          'bootstrap_project',
          'The project number is unavailable.',
        );
      }
      final providerResponse = await iam.IamApi(client)
          .projects
          .locations
          .workloadIdentityPools
          .providers
          .list(
            'projects/$projectNumber/locations/global/workloadIdentityPools/ii-os-github',
            pageSize: 21,
          );
      return _select(
        credentials: credentials,
        projectNumber: projectNumber,
        buckets: buckets.items ?? const [],
        accounts: accounts.accounts ?? const [],
        providers: providerResponse.workloadIdentityPoolProviders ?? const [],
        selection: selection,
        github: github,
      );
    } on Object {
      return _failed(
        'bootstrap_discovery',
        'Grant this service account read access to the project resources.',
      );
    }
  }

  GcpBootstrapDiscovery _select({
    required GcpBootstrapCredentials credentials,
    required String projectNumber,
    required List<storage.Bucket> buckets,
    required List<iam.ServiceAccount> accounts,
    required List<iam.WorkloadIdentityPoolProvider> providers,
    required GcpBootstrapSelection selection,
    required GcpGitHubDiscovery github,
  }) {
    if (buckets.length > 20 || accounts.length > 100 || providers.length > 20) {
      return _failed(
        'bootstrap_resource_limit',
        'Name the bucket, upload service account, and identity provider to narrow discovery.',
      );
    }
    final boundBuckets = buckets
        .where(
          (bucket) => bucket.labels?['ii_os_organization_id'] == organizationId,
        )
        .toList();
    final bucket = _namedOrSingle(
      boundBuckets,
      selection.bucket,
      (value) => value.name ?? '',
    );
    final uploadAccounts = accounts
        .where(
          (account) =>
              (account.email ?? '').contains('@${credentials.projectId}.') &&
              ((account.displayName ?? '').toLowerCase().contains('workflow') ||
                  (account.email ?? '').startsWith('workflow-upload@')),
        )
        .toList();
    final upload = _namedOrSingle(
      uploadAccounts,
      selection.uploadServiceAccount,
      (value) => value.email ?? '',
    );
    final activeProviders = providers
        .where((provider) => provider.state == 'ACTIVE')
        .toList();
    final provider = _namedOrSingle(
      activeProviders,
      selection.workloadIdentityProvider,
      (value) => value.name ?? '',
    );
    final checks = [
      _selectionCheck(
        'bootstrap_identity',
        true,
        'Google accepted the service account.',
      ),
      _selectionCheck(
        'bootstrap_bucket',
        bucket != null,
        'Label exactly one accessible bucket for this organization or name it here.',
      ),
      _selectionCheck(
        'bootstrap_upload_identity',
        upload != null,
        'Name an accessible workflow upload service account.',
      ),
      _selectionCheck(
        'bootstrap_wif',
        provider != null,
        'Name an active provider in the ii-os-github identity pool.',
      ),
      ...github.checks,
    ];
    if (checks.any((check) => !check.passed)) {
      return GcpBootstrapDiscovery(connection: null, checks: checks);
    }
    return GcpBootstrapDiscovery(
      connection: DataPlaneConnection(
        workspaceId: '',
        organizationId: organizationId,
        projectId: credentials.projectId,
        projectNumber: projectNumber,
        databaseId: controlDatabaseId,
        region: bucket!.location?.toLowerCase() ?? 'us-central1',
        bucket: bucket.name!,
        dataServiceAccount: brokerServiceAccount,
        uploadServiceAccount: upload!.email!,
        workloadIdentityProvider: provider!.name!,
        authProjectId: controlProjectId,
        webOrigin: webOrigin,
        gcpOnly: true,
        emulated: false,
      ),
      checks: checks,
      githubResources: github.resources,
    );
  }
}

T? _namedOrSingle<T>(List<T> values, String selected, String Function(T) name) {
  final trimmed = selected.trim();
  if (trimmed.isNotEmpty) {
    final matches = values.where((value) => name(value) == trimmed);
    return matches.length == 1 ? matches.single : null;
  }
  return values.length == 1 ? values.single : null;
}

GcpBootstrapDiscovery _failed(String id, String detail) =>
    GcpBootstrapDiscovery(
      connection: null,
      checks: [_selectionCheck(id, false, detail)],
    );

ConnectionCheck _selectionCheck(String id, bool passed, String detail) =>
    ConnectionCheck(
      id: id,
      label: 'GCP bootstrap',
      status: passed ? 'passed' : 'action_required',
      detail: detail,
    );

const _serviceAccountFields = {
  'type',
  'project_id',
  'private_key_id',
  'private_key',
  'client_email',
  'client_id',
  'auth_uri',
  'token_uri',
  'auth_provider_x509_cert_url',
  'client_x509_cert_url',
  'universe_domain',
  'quota_project_id',
};
const _invalidServiceAccount = ApiError(
  400,
  'invalid_service_account',
  'Use a valid Google service-account JSON file under 64 KiB.',
);
final _projectId = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');
final _projectNumber = RegExp(r'^[1-9][0-9]{5,29}$');
final _serviceAccountEmail = RegExp(
  r'^[a-z0-9][a-z0-9-]{2,62}@[a-z][a-z0-9-]{4,28}[a-z0-9]\.iam\.gserviceaccount\.com$',
);
