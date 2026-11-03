import 'package:ii_os_functions/src/api_error.dart';
import 'package:ii_os_functions/src/gcp_bootstrap.dart';
import 'package:ii_os_functions/src/gcp_github_discovery.dart';
import 'package:test/test.dart';

void main() {
  test('accepts only the bounded Google service account shape', () {
    final credentials = GcpBootstrapCredentials.parse(_serviceAccount());

    expect(credentials.projectId, 'customer-project');
    expect(
      credentials.email,
      'bootstrap@customer-project.iam.gserviceaccount.com',
    );
  });

  test('rejects unknown fields before authentication', () {
    expect(
      () => GcpBootstrapCredentials.parse({
        ..._serviceAccount(),
        'copiedConnection': {'bucket': 'somewhere-else'},
      }),
      throwsA(
        isA<ApiError>().having(
          (error) => error.code,
          'code',
          'invalid_service_account',
        ),
      ),
    );
  });

  test('rejects a credential payload over 64 KiB', () {
    expect(
      () => GcpBootstrapCredentials.parse({
        ..._serviceAccount(),
        'private_key': 'x' * (64 * 1024),
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('rejects a service account from another project', () {
    expect(
      () => GcpBootstrapCredentials.parse({
        ..._serviceAccount(),
        'client_email': 'bootstrap@other-project.iam.gserviceaccount.com',
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('rejects text outside the service-account PEM block', () {
    expect(
      () => GcpBootstrapCredentials.parse({
        ..._serviceAccount(),
        'private_key':
            'copied from somewhere\n-----BEGIN PRIVATE KEY-----\nx\n' // gitleaks:allow
            '-----END PRIVATE KEY-----',
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('GitHub discovery accepts only literal read and write levels', () {
    expect(
      discoveredGitHubPermissions({
        'actions': 'read',
        'contents': 'admin',
        'deployments': 'read',
        'issues': 'write',
        'metadata': 'read',
      }),
      {'actions:read', 'deployments:read', 'issues:write'},
    );
  });
}

Map<String, Object?> _serviceAccount() => {
  'type': 'service_account',
  'project_id': 'customer-project',
  'private_key_id': 'key-id',
  'private_key':
      '-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----\n',
  'client_email': 'bootstrap@customer-project.iam.gserviceaccount.com',
  'client_id': '123456789012345678901',
  'auth_uri': 'https://accounts.google.com/o/oauth2/auth',
  'token_uri': 'https://oauth2.googleapis.com/token',
  'auth_provider_x509_cert_url': 'https://www.googleapis.com/oauth2/v1/certs',
  'client_x509_cert_url':
      'https://www.googleapis.com/robot/v1/metadata/x509/bootstrap%40customer-project.iam.gserviceaccount.com',
  'universe_domain': 'googleapis.com',
};
