import 'dart:convert';

import 'package:ii_os_functions/src/data_plane_connection.dart';
import 'package:ii_os_functions/src/github_app_secret.dart';
import 'package:test/test.dart';

const _organizationId = '3f1c2b7a-1111-4111-8111-111111111111';
const _workspaceId = '00000000-2222-4222-8222-222222222222';

Map<String, Object?> _shared() => {
  'projectId': 'tenant-project',
  'projectNumber': '123456789012',
  'databaseId': '(default)',
  'region': 'us-central1',
  'bucket': 'tenant-private-media',
  'dataServiceAccount': 'ii-os-broker@ii-project.iam.gserviceaccount.com',
  'uploadServiceAccount':
      'workflow-upload@tenant-project.iam.gserviceaccount.com',
  'workloadIdentityProvider':
      'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
  'authProjectId': 'ii-control-project',
  'webOrigin': 'https://ii-os.example.com',
  'githubAppId': '123456',
  'githubAppSecret': 'projects/tenant-project/secrets/github-app-private-key',
};

Map<String, Object?> organizationConnection() => {
  'schemaVersion': 3,
  'organizationId': _organizationId,
  ..._shared(),
};

Map<String, Object?> workspaceConnection() => {
  'schemaVersion': 2,
  'workspaceId': _workspaceId,
  ..._shared(),
};

String secretPayload({String? organizationId, String? workspaceId}) =>
    jsonEncode({
      'schemaVersion': organizationId != null ? 2 : 1,
      'organizationId': ?organizationId,
      'workspaceId': ?workspaceId,
      'privateKey':
          '-----BEGIN RSA PRIVATE KEY-----\nx\n-----END RSA PRIVATE KEY-----',
    });

void main() {
  test('schema 4 is an organization-bound GCP resource without GitHub', () {
    final record = {...organizationConnection(), 'schemaVersion': 4}
      ..remove('githubAppId')
      ..remove('githubAppSecret');

    final connection = DataPlaneConnection.fromJson(record, emulated: true);

    expect(connection.isOrganizationBound, isTrue);
    expect(connection.gcpOnly, isTrue);
    expect(connection.githubAppId, isEmpty);
    expect(
      connection.configurationChecks().every((check) => check.passed),
      isTrue,
    );
    expect(connection.toJson(), record);
  });

  group('connection binding', () {
    test('an organization connection binds to its tenant', () {
      final connection = DataPlaneConnection.fromJson(organizationConnection());

      expect(connection.isOrganizationBound, isTrue);
      expect(connection.bindingId, _organizationId);
      expect(connection.bindingLabel, 'ii_os_organization_id');
      expect(connection.workspaceId, isEmpty);
      expect(connection.configurationChecks().every((c) => c.passed), isTrue);
    });

    test('a workspace connection still binds to its workspace', () {
      final connection = DataPlaneConnection.fromJson(workspaceConnection());

      expect(connection.isOrganizationBound, isFalse);
      expect(connection.bindingId, _workspaceId);
      expect(connection.bindingLabel, 'ii_os_workspace_id');
      expect(connection.configurationChecks().every((c) => c.passed), isTrue);
    });

    test('a connection round-trips at the version it was read as', () {
      expect(
        DataPlaneConnection.fromJson(organizationConnection()).toJson(),
        organizationConnection(),
      );
      expect(
        DataPlaneConnection.fromJson(workspaceConnection()).toJson(),
        workspaceConnection(),
      );
    });

    test('a connection cannot carry both bindings or neither', () {
      // Bumping the version without changing the field is exactly the mistake
      // this rejects, because it would otherwise silently rebind a tenant.
      expect(
        () => DataPlaneConnection.fromJson({
          ...organizationConnection(),
          'workspaceId': _workspaceId,
        }),
        throwsFormatException,
      );
      expect(
        () => DataPlaneConnection.fromJson({
          ...workspaceConnection(),
          'schemaVersion': 3,
        }),
        throwsFormatException,
      );
      expect(
        () => DataPlaneConnection.fromJson({
          ...organizationConnection(),
          'schemaVersion': 4,
        }),
        throwsFormatException,
      );
    });
  });

  group('GitHub App secret binding', () {
    test('reads both tiers and reports which one it names', () {
      final org = GitHubAppSecret.parse(
        secretPayload(organizationId: _organizationId),
      );
      final workspace = GitHubAppSecret.parse(
        secretPayload(workspaceId: _workspaceId),
      );

      expect(org.isOrganizationBound, isTrue);
      expect(org.bindingId, _organizationId);
      expect(workspace.isOrganizationBound, isFalse);
      expect(workspace.bindingId, _workspaceId);
    });

    test('discoverable organization secret carries its GitHub App id', () {
      final secret = GitHubAppSecret.parse(
        jsonEncode({
          'schemaVersion': 3,
          'organizationId': _organizationId,
          'appId': '123456',
          'privateKey':
              '-----BEGIN RSA PRIVATE KEY-----\nx\n-----END RSA PRIVATE KEY-----',
        }),
      );

      expect(secret.organizationId, _organizationId);
      expect(secret.appId, '123456');
      expect(secret.isDiscoverable, isTrue);
    });

    test('a payload naming the wrong field for its version is refused', () {
      expect(
        () => GitHubAppSecret.parse(
          jsonEncode({
            'schemaVersion': 2,
            'workspaceId': _workspaceId,
            'privateKey':
                '-----BEGIN RSA PRIVATE KEY-----\nx\n-----END RSA PRIVATE KEY-----', // gitleaks:allow
          }),
        ),
        throwsFormatException,
      );
    });

    test('an oversized private-key payload is refused before use', () {
      expect(
        () => GitHubAppSecret.parse(
          jsonEncode({
            'schemaVersion': 3,
            'organizationId': _organizationId,
            'appId': '123456',
            'privateKey':
                '-----BEGIN PRIVATE KEY-----\n${'x' * (64 * 1024)}\n'
                '-----END PRIVATE KEY-----',
          }),
        ),
        throwsFormatException,
      );
    });

    test('private-key payload cannot carry text outside its PEM block', () {
      expect(
        () => GitHubAppSecret.parse(
          jsonEncode({
            'schemaVersion': 3,
            'organizationId': _organizationId,
            'appId': '123456',
            'privateKey':
                'copied from somewhere\n-----BEGIN PRIVATE KEY-----\nx\n'
                '-----END PRIVATE KEY-----',
          }),
        ),
        throwsFormatException,
      );
    });

    test('a key without a binding is refused', () {
      expect(
        () => GitHubAppSecret.parse(secretPayload(organizationId: '')),
        throwsFormatException,
      );
    });

    test('tier is compared as well as identifier', () {
      // The two ids are deliberately equal here. Matching on identifier alone
      // would accept a workspace key for an organization connection, which is
      // the substitution the wrapper exists to prevent.
      final connection = DataPlaneConnection.fromJson({
        ...organizationConnection(),
        'organizationId': _organizationId,
      });
      final wrongTier = GitHubAppSecret.parse(
        secretPayload(workspaceId: _organizationId),
      );
      final rightTier = GitHubAppSecret.parse(
        secretPayload(organizationId: _organizationId),
      );

      expect(wrongTier.bindingId, connection.bindingId);
      expect(
        wrongTier.isOrganizationBound == connection.isOrganizationBound,
        isFalse,
      );
      expect(
        rightTier.isOrganizationBound == connection.isOrganizationBound &&
            rightTier.bindingId == connection.bindingId,
        isTrue,
      );
    });
  });
}
