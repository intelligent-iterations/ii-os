import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/state/app_controller.dart';

void main() {
  test(
    'child workspace reads media through its promoted legacy GCP grant',
    () async {
      var requests = 0;
      final api = ApiClient(
        baseUrl: 'https://ii-os.test/api',
        httpClient: MockClient((request) async {
          requests += 1;
          expect(
            request.url.queryParameters['route'],
            'v1/workspaces/workspace-child/jobs/job-1/artifacts/read-url',
          );
          return http.Response(
            '{"error":{"code":"diagnostic_stop","message":"Stop after auth."}}',
            500,
            headers: {'content-type': 'application/json'},
          );
        }),
        reportFailures: false,
        authTokenProvider: (_) async => 'test-token',
      );
      final controller = AppController(api: api);
      addTearDown(controller.dispose);
      final session = SessionModel.fromJson(_session());
      controller
        ..session = session
        ..selectedAccess = session.workspaces.single
        ..connection = session.connectionForWorkspace('workspace-child');

      expect(controller.connection?.workspaceId, 'workspace-parent');
      expect(
        controller.connection?.isBoundTo(
          workspaceId: 'workspace-child',
          organizationId: 'org-1',
        ),
        isFalse,
      );

      await expectLater(
        controller.readArtifactUrl(
          workspaceId: 'workspace-child',
          jobId: 'job-1',
          artifact: const {
            'path': 'workspaces/workspace-child/ghost/job-1/video/result.mp4',
            'generation': '1787750275441995',
            'size_bytes': 1632395,
            'sha256':
                'fd8398268ca72ac1a187f5f93e2e301d2845f2ba269b4b6eabd10d2ca6d982e9',
            'content_type': 'video/mp4',
          },
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(requests, 1);
    },
  );
}

Map<String, Object?> _session() => {
  'user': {
    'uid': 'admin-1',
    'email': 'admin@example.com',
    'displayName': 'Admin',
    'isOwner': false,
  },
  'organizations': [
    {
      'organization': {
        'id': 'org-1',
        'name': 'Acme',
        'resourceCatalogVersion': 1,
        'gcpResources': [
          {
            'id': 'gcp-promoted',
            'name': 'Promoted media project',
            'legacySourceWorkspaceId': 'workspace-parent',
            'active': true,
            'permissionEnvelope': ['assets.read'],
            'connection': {
              'schemaVersion': 2,
              'workspaceId': 'workspace-parent',
              'projectId': 'media-project',
              'projectNumber': '123456789012',
              'databaseId': '(default)',
              'region': 'northamerica-northeast1',
              'bucket': 'media-project-assets',
              'dataServiceAccount': 'broker@platform.iam.gserviceaccount.com',
              'uploadServiceAccount': 'upload@media.iam.gserviceaccount.com',
              'workloadIdentityProvider': 'provider',
              'authProjectId': 'platform',
              'webOrigin': 'https://ii-os.test',
              'githubAppId': '123',
              'githubAppSecret': 'projects/media/secrets/github-app',
            },
          },
        ],
        'githubResources': <Object?>[],
        'runnerPools': <Object?>[],
      },
      'membership': {
        'role': 'admin',
        'roleLabel': 'Organization Admin',
        'effectiveCapabilities': ['org.integrations.manage'],
      },
    },
  ],
  'workspaces': [
    {
      'workspace': {
        'id': 'workspace-child',
        'name': 'Design team',
        'organizationId': 'org-1',
        'environment': 'dev',
        'repositories': <Object?>[],
        'projects': <Object?>[],
        'workflows': <Object?>[],
        'resourceGrantVersion': 1,
        'resourceGrants': {
          'gcp': [
            {
              'resourceId': 'gcp-promoted',
              'permissions': ['assets.read'],
              'primary': true,
            },
          ],
          'github': <Object?>[],
          'runners': <Object?>[],
        },
      },
      'membership': {
        'workspaceId': 'workspace-child',
        'uid': 'admin-1',
        'email': 'admin@example.com',
        'role': 'admin',
        'roleLabel': 'Workspace Admin',
        'featureClaims': <Object?>[],
        'effectiveCapabilities': ['workspace.read'],
      },
    },
  ],
};
