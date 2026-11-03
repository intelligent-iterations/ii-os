import 'dart:convert';

import 'package:ii_os_functions/src/data_plane_connection.dart';
import 'package:ii_os_functions/src/github_app_secret.dart';
import 'package:test/test.dart';

void main() {
  test('rejects legacy and connector-bearing connection records', () {
    expect(
      () => DataPlaneConnection.fromJson({
        'schemaVersion': 1,
        'apiBaseUrl': 'https://connector.example',
      }),
      throwsFormatException,
    );
    expect(
      () => DataPlaneConnection.fromJson({
        'schemaVersion': 2,
        'projectId': 'customer-media-123',
      }),
      throwsFormatException,
    );
  });

  test('exports a nonsecret customer-owned connection record', () {
    const connection = DataPlaneConnection(
      workspaceId: '123e4567-e89b-42d3-a456-426614174000',
      projectId: 'customer-media-123',
      projectNumber: '123456789012',
      databaseId: 'ii-os-data',
      region: 'us-central1',
      bucket: 'customer-media-123-ii-os',
      dataServiceAccount: 'broker@example-platform.iam.gserviceaccount.com',
      uploadServiceAccount:
          'ii-os-upload@customer-media-123.iam.gserviceaccount.com',
      workloadIdentityProvider:
          'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
      authProjectId: 'example-platform',
      webOrigin: 'https://ii-os.example.com',
      githubAppId: '1234567',
      githubAppSecret:
          'projects/123456789012/secrets/ii-os-github-app-private-key',
      emulated: false,
    );

    expect(
      connection.configurationChecks().every((check) => check.passed),
      isTrue,
    );
    expect(connection.toJson(), isNot(contains('credential')));
    expect(connection.toJson(), isNot(contains('privateKey')));
    expect(connection.toJson()['projectId'], 'customer-media-123');
    expect(connection.toJson()['authProjectId'], 'example-platform');
    expect(connection.toJson()['schemaVersion'], 2);
  });

  test('fails closed when a required cloud identity is malformed', () {
    const connection = DataPlaneConnection(
      workspaceId: '123e4567-e89b-42d3-a456-426614174000',
      projectId: 'customer-media-123',
      projectNumber: '123456789012',
      databaseId: 'ii-os-data',
      region: 'us-central1',
      bucket: 'customer-media-123-ii-os',
      dataServiceAccount: 'uploaded-key.json',
      uploadServiceAccount:
          'ii-os-upload@customer-media-123.iam.gserviceaccount.com',
      workloadIdentityProvider:
          'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
      authProjectId: 'example-platform',
      webOrigin: 'https://ii-os.example.com',
      emulated: false,
    );

    final identity = connection.configurationChecks().singleWhere(
      (check) => check.id == 'data_identity',
    );
    expect(identity.passed, isFalse);
  });

  test('fails closed when assets target the platform project', () {
    const connection = DataPlaneConnection(
      workspaceId: '123e4567-e89b-42d3-a456-426614174000',
      projectId: 'example-platform',
      projectNumber: '123456789012',
      databaseId: 'ii-os-data',
      region: 'us-central1',
      bucket: 'example-platform-media',
      dataServiceAccount: 'broker@example-platform.iam.gserviceaccount.com',
      uploadServiceAccount: 'upload@example-platform.iam.gserviceaccount.com',
      workloadIdentityProvider:
          'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
      authProjectId: 'example-platform',
      webOrigin: 'https://ii-os.example.com',
      githubAppId: '1234567',
      githubAppSecret:
          'projects/123456789012/secrets/ii-os-github-app-private-key',
      emulated: false,
    );

    final boundary = connection.configurationChecks().singleWhere(
      (check) => check.id == 'asset_project_boundary',
    );
    expect(boundary.passed, isFalse);
  });

  test('requires a workspace-bound GitHub App secret payload', () {
    const workspaceId =
        '123e4567-e89b-'
        '42d3-a456-426614174000';
    const keyLabel = 'PRIVATE KEY';
    final privateKey =
        '-----BEGIN $keyLabel-----\nkey\n-----END $keyLabel-----';
    final secret = GitHubAppSecret.parse(
      jsonEncode({
        'schemaVersion': 1,
        'workspaceId': workspaceId,
        'privateKey': privateKey,
      }),
    );

    expect(secret.workspaceId, workspaceId);
    expect(secret.privateKey, contains('PRIVATE KEY'));
    expect(
      () => GitHubAppSecret.parse('-----BEGIN $keyLabel-----'),
      throwsFormatException,
    );
  });
}
