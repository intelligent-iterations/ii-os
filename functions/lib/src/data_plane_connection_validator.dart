import 'dart:async';
import 'dart:convert';

import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:googleapis/iamcredentials/v1.dart' as credentials;
import 'package:googleapis/secretmanager/v1.dart' as secretmanager;
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:uuid/uuid.dart';

import 'data_plane_connection.dart';
import 'github_app_secret.dart';

final class DataPlaneConnectionValidator {
  DataPlaneConnectionValidator({
    required this.connection,
    required this.firestore,
  });

  final DataPlaneConnection connection;
  final Firestore firestore;
  static const _uuid = Uuid();

  Future<Map<String, Object?>> validate() async {
    final checks = connection.configurationChecks()
      ..add(await _firestoreCrud());
    if (connection.emulated) {
      checks.addAll(_emulatorChecks(connection));
    } else {
      try {
        await _withCloudClient((client) async {
          checks.addAll(await _bucketChecks(client));
          checks.add(await _bucketAdministrationDenied(client));
          checks.add(await _objectCrud(client));
          checks.add(await _readSigning(client));
          if (!connection.gcpOnly) checks.add(await _githubSecret(client));
        });
      } catch (_) {
        checks.add(
          const ConnectionCheck(
            id: 'cloud_identity',
            label: 'Connector cloud identity',
            status: 'action_required',
            detail: 'Application Default Credentials are unavailable',
          ),
        );
      }
    }
    checks.add(_firebaseBoundary);
    return {
      'connection': connection.toJson(),
      'status': checks.every((check) => check.passed)
          ? 'ready'
          : 'action_required',
      'checks': checks.map((check) => check.toJson()).toList(),
      'validatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<ConnectionCheck> _firestoreCrud() async {
    final ref = firestore.collection('connectionCanaries').doc(_uuid.v4());
    try {
      await ref.set({'state': 'created', 'createdAt': Timestamp.now()});
      final created = await ref.get();
      await ref.update({'state': 'updated'});
      final updated = await ref.get();
      await ref.delete();
      final deleted = await ref.get();
      final passed =
          created.exists &&
          created.data()?['state'] == 'created' &&
          updated.data()?['state'] == 'updated' &&
          !deleted.exists;
      return ConnectionCheck(
        id: 'firestore_crud',
        label: 'ii-os control-plane database',
        status: passed ? 'passed' : 'failed',
        detail: passed
            ? '${connection.authProjectId}/${connection.databaseId}'
            : 'Canary mismatch',
      );
    } catch (_) {
      try {
        await ref.delete();
      } catch (_) {}
      return const ConnectionCheck(
        id: 'firestore_crud',
        label: 'ii-os control-plane database',
        status: 'action_required',
        detail: 'The control-plane database is unavailable',
      );
    }
  }

  Future<List<ConnectionCheck>> _bucketChecks(AuthClient client) async {
    try {
      final bucket = await storage.StorageApi(
        client,
      ).buckets.get(connection.bucket, projection: 'noAcl');
      final uniform =
          bucket.iamConfiguration?.uniformBucketLevelAccess?.enabled == true;
      final private =
          bucket.iamConfiguration?.publicAccessPrevention == 'enforced';
      final policyPassed =
          uniform &&
          private &&
          bucket.projectNumber == connection.projectNumber;
      final bindingPassed =
          bucket.labels?[connection.bindingLabel] == connection.bindingId;
      final lifecyclePassed = bucketMediaLifecycleIsValid(
        bucket,
        workspaceId: connection.workspaceId,
        organizationId: connection.organizationId,
      );
      final corsRules = bucket.cors ?? const [];
      final corsPassed =
          corsRules.every((cors) => !(cors.origin ?? const []).contains('*')) &&
          corsRules.any((cors) {
            final methods = (cors.method ?? const []).toSet();
            final headers = (cors.responseHeader ?? const [])
                .map((value) => value.toLowerCase())
                .toSet();
            final origins = cors.origin ?? const [];
            return origins.contains(connection.webOrigin) &&
                !origins.contains('*') &&
                methods.containsAll(const {'GET', 'HEAD', 'PUT'}) &&
                headers.containsAll(const {
                  'content-type',
                  'range',
                  'x-goog-hash',
                  'x-goog-if-generation-match',
                  'x-goog-meta-ii-os-sha256',
                });
          });
      return [
        ConnectionCheck(
          id: 'bucket_workspace_binding',
          label: connection.isOrganizationBound
              ? 'Bucket organization binding'
              : 'Bucket workspace binding',
          status: bindingPassed ? 'passed' : 'action_required',
          detail: bindingPassed
              ? 'Bucket is explicitly bound to this ii-os '
                    '${connection.isOrganizationBound ? 'organization' : 'workspace'}'
              : 'Set the exact ${connection.bindingLabel} bucket label',
        ),
        ConnectionCheck(
          id: 'bucket_policy',
          label: 'GCS bucket policy',
          status: policyPassed ? 'passed' : 'action_required',
          detail: policyPassed
              ? 'Uniform access and public access prevention enforced'
              : 'Require owner project, uniform access, and public access prevention',
        ),
        ConnectionCheck(
          id: 'bucket_retention',
          label: 'GCS media retention',
          status: lifecyclePassed ? 'passed' : 'action_required',
          detail: lifecyclePassed
              ? 'Unattached media expires within 30 days; attached media is held, and abandoned Ghost media expires within 1 day'
              : 'Require attachment holds, 30-day media and 1-day Ghost delete rules, versioning off, and soft delete disabled',
        ),
        ConnectionCheck(
          id: 'bucket_cors',
          label: 'Browser media transfer',
          status: corsPassed ? 'passed' : 'action_required',
          detail: corsPassed
              ? 'Exact-origin GCS reads and signed uploads enabled'
              : 'Require exact-origin GET, HEAD, and PUT bucket CORS',
        ),
      ];
    } catch (_) {
      return [
        ConnectionCheck(
          id: 'bucket_workspace_binding',
          label: connection.isOrganizationBound
              ? 'Bucket organization binding'
              : 'Bucket workspace binding',
          status: 'action_required',
          detail: 'Bucket tenant binding is unavailable',
        ),
        ConnectionCheck(
          id: 'bucket_policy',
          label: 'GCS bucket policy',
          status: 'action_required',
          detail: 'Bucket metadata is unavailable to the data-plane identity',
        ),
        ConnectionCheck(
          id: 'bucket_retention',
          label: 'GCS media retention',
          status: 'action_required',
          detail: 'Bucket lifecycle is unavailable to the data-plane identity',
        ),
        ConnectionCheck(
          id: 'bucket_cors',
          label: 'Browser media transfer',
          status: 'action_required',
          detail: 'Bucket CORS is unavailable to the data-plane identity',
        ),
      ];
    }
  }

  Future<ConnectionCheck> _objectCrud(AuthClient client) async {
    final api = storage.StorageApi(client);
    final name = '_ii-os/connection-canaries/${_uuid.v4()}';
    String? generation;
    try {
      final created = await api.objects.insert(
        storage.Object(
          name: name,
          contentType: 'application/octet-stream',
          metadata: {'ii-os-state': 'created'},
        ),
        connection.bucket,
        ifGenerationMatch: '0',
        uploadMedia: storage.Media(const Stream<List<int>>.empty(), 0),
      );
      generation = created.generation;
      final read =
          await api.objects.get(connection.bucket, name) as storage.Object;
      final updated = await api.objects.patch(
        storage.Object(metadata: {'ii-os-state': 'updated'}),
        connection.bucket,
        name,
        generation: generation,
      );
      final passed =
          read.generation == generation &&
          updated.metadata?['ii-os-state'] == 'updated';
      await api.objects.delete(connection.bucket, name, generation: generation);
      return ConnectionCheck(
        id: 'object_crud',
        label: 'GCS object canary',
        status: passed ? 'passed' : 'failed',
        detail: passed
            ? 'Create, read, update, and delete passed'
            : 'Canary mismatch',
      );
    } catch (_) {
      if (generation != null) {
        try {
          await api.objects.delete(
            connection.bucket,
            name,
            generation: generation,
          );
        } catch (_) {}
      }
      return const ConnectionCheck(
        id: 'object_crud',
        label: 'GCS object canary',
        status: 'action_required',
        detail: 'Grant bounded object CRUD to the data-plane identity',
      );
    }
  }

  Future<ConnectionCheck> _bucketAdministrationDenied(AuthClient client) async {
    try {
      final response = await storage.StorageApi(client).buckets
          .testIamPermissions(connection.bucket, const [
            'storage.buckets.delete',
            'storage.buckets.setIamPolicy',
            'storage.buckets.update',
          ]);
      final denied = response.permissions?.isEmpty ?? true;
      return ConnectionCheck(
        id: 'bucket_admin_denied',
        label: 'Bucket administration denied',
        status: denied ? 'passed' : 'action_required',
        detail: denied
            ? 'Data-plane identity has no bucket administration permission'
            : 'Remove bucket update, delete, and IAM administration permissions',
      );
    } catch (_) {
      return const ConnectionCheck(
        id: 'bucket_admin_denied',
        label: 'Bucket administration denied',
        status: 'action_required',
        detail: 'Bucket permission boundary could not be inspected',
      );
    }
  }

  Future<ConnectionCheck> _readSigning(AuthClient client) async {
    try {
      final response = await credentials.IAMCredentialsApi(client)
          .projects
          .serviceAccounts
          .signBlob(
            credentials.SignBlobRequest(payload: 'aWktb3MtY2FuYXJ5'),
            'projects/-/serviceAccounts/${connection.dataServiceAccount}',
          );
      final passed = response.signedBlob?.isNotEmpty == true;
      return ConnectionCheck(
        id: 'read_signing',
        label: 'Short-lived asset reads',
        status: passed ? 'passed' : 'action_required',
        detail: passed
            ? 'ii-os broker can sign bounded GCS reads'
            : 'IAM Credentials returned an empty signature',
      );
    } catch (_) {
      return const ConnectionCheck(
        id: 'read_signing',
        label: 'Short-lived asset reads',
        status: 'action_required',
        detail: 'Grant the ii-os broker permission to sign as itself',
      );
    }
  }

  Future<ConnectionCheck> _githubSecret(AuthClient client) async {
    if (connection.githubAppSecret.isEmpty) {
      return const ConnectionCheck(
        id: 'github_app_secret',
        label: 'Customer GitHub App secret',
        status: 'action_required',
        detail: 'Declare the customer Secret Manager secret reference',
      );
    }
    final api = secretmanager.SecretManagerApi(client);
    final version = connection.githubAppSecret.endsWith('/versions/latest')
        ? connection.githubAppSecret
        : '${connection.githubAppSecret}/versions/latest';
    String value;
    try {
      final response = await api.projects.secrets.versions.access(version);
      final encoded = response.payload?.data;
      value = encoded == null
          ? ''
          : utf8.decode(base64.decode(encoded), allowMalformed: true);
    } catch (_) {
      return const ConnectionCheck(
        id: 'github_app_secret',
        label: 'Customer GitHub App secret access',
        status: 'action_required',
        detail: 'Grant the data-plane identity Secret Manager accessor access',
      );
    }
    try {
      final secret = GitHubAppSecret.parse(value);
      // Tier as well as identifier. Accepting a workspace-bound key for an
      // organization-bound connection because the two ids happened to match
      // would turn the anti-substitution control into a coincidence check.
      final tier =
          'ii-os ${connection.isOrganizationBound ? 'organization' : 'workspace'}';
      final valid = secret.isBoundTo(
        bindingId: connection.bindingId,
        organizationBound: connection.isOrganizationBound,
      );
      return ConnectionCheck(
        id: 'github_app_secret',
        label: 'Customer GitHub App secret binding',
        status: valid ? 'passed' : 'action_required',
        detail: valid
            ? 'Secret is readable and bound to this $tier'
            : 'Secret is bound to a different $tier',
      );
    } on FormatException {
      return const ConnectionCheck(
        id: 'github_app_secret',
        label: 'Customer GitHub App secret binding',
        status: 'action_required',
        detail:
            'Replace the secret with a supported workspace-bound or '
            'organization-bound payload',
      );
    }
  }

  Future<void> _withCloudClient(
    Future<void> Function(AuthClient client) action,
  ) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const ['https://www.googleapis.com/auth/cloud-platform'],
    );
    try {
      await action(client);
    } finally {
      client.close();
    }
  }
}

bool bucketMediaLifecycleIsValid(
  storage.Bucket bucket, {
  required String workspaceId,
  String organizationId = '',
}) {
  if (bucket.versioning?.enabled == true ||
      (int.tryParse(bucket.softDeletePolicy?.retentionDurationSeconds ?? '0') ??
              -1) !=
          0) {
    return false;
  }
  final rules = bucket.lifecycle?.rule ?? const [];
  final durable = rules.any((rule) {
    final condition = rule.condition;
    return rule.action?.type == 'Delete' &&
        rule.action?.storageClass == null &&
        condition?.age != null &&
        condition!.age! <= 30 &&
        _hasOnlyAgeCondition(condition);
  });
  final ghostPrefixes = organizationId.isNotEmpty
      ? {
          'organizations/$organizationId/ghost/',
          'organizations/$organizationId/ghost-source-assets/',
        }
      : {
          'workspaces/$workspaceId/ghost/',
          'workspaces/$workspaceId/ghost-source-assets/',
        };
  final ephemeral = rules.any((rule) {
    final condition = rule.condition;
    final prefixes = condition?.matchesPrefix?.toSet() ?? const <String>{};
    return rule.action?.type == 'Delete' &&
        rule.action?.storageClass == null &&
        condition?.age == 1 &&
        prefixes.length == ghostPrefixes.length &&
        prefixes.containsAll(ghostPrefixes) &&
        _hasOnlyAgeCondition(condition!, allowPrefixes: true);
  });
  return durable && ephemeral;
}

bool _hasOnlyAgeCondition(
  storage.BucketLifecycleRuleCondition condition, {
  bool allowPrefixes = false,
}) =>
    condition.createdBefore == null &&
    condition.customTimeBefore == null &&
    condition.daysSinceCustomTime == null &&
    condition.daysSinceNoncurrentTime == null &&
    condition.isLive == null &&
    condition.matchesPattern == null &&
    (allowPrefixes || condition.matchesPrefix == null) &&
    condition.matchesStorageClass == null &&
    condition.matchesSuffix == null &&
    condition.noncurrentTimeBefore == null &&
    condition.numNewerVersions == null;

List<ConnectionCheck> _emulatorChecks(DataPlaneConnection connection) => [
  ConnectionCheck(
    id: 'bucket_workspace_binding',
    label: connection.isOrganizationBound
        ? 'Bucket organization binding'
        : 'Bucket workspace binding',
    status: 'passed',
    detail: 'Emulator boundary',
  ),
  ConnectionCheck(
    id: 'bucket_policy',
    label: 'GCS bucket policy',
    status: 'passed',
    detail: 'Emulator boundary',
  ),
  ConnectionCheck(
    id: 'bucket_retention',
    label: 'GCS media retention',
    status: 'passed',
    detail: 'Emulator boundary',
  ),
  ConnectionCheck(
    id: 'bucket_cors',
    label: 'Browser media transfer',
    status: 'passed',
    detail: 'Emulator boundary',
  ),
  ConnectionCheck(
    id: 'bucket_admin_denied',
    label: 'Bucket administration denied',
    status: 'passed',
    detail: 'Emulator boundary',
  ),
  ConnectionCheck(
    id: 'object_crud',
    label: 'GCS object canary',
    status: 'passed',
    detail: 'Emulator boundary',
  ),
  ConnectionCheck(
    id: 'read_signing',
    label: 'Short-lived asset reads',
    status: 'passed',
    detail: 'Emulator boundary',
  ),
  if (!connection.gcpOnly)
    const ConnectionCheck(
      id: 'github_app_secret',
      label: 'Customer GitHub App secret access',
      status: 'passed',
      detail: 'Emulator boundary',
    ),
];

const _firebaseBoundary = ConnectionCheck(
  id: 'firebase_asset_boundary',
  label: 'Firebase asset boundary',
  status: 'passed',
  detail: 'Metadata only; no Firebase Storage target',
);
