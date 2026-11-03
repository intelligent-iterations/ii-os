import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/organization_resources_screen.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/state/app_controller.dart';

void main() {
  testWidgets(
    'organization admin can reuse the original workspace infrastructure',
    (tester) async {
      final controller = AppController(
        api: ApiClient(baseUrl: '', reportFailures: false),
      );
      addTearDown(controller.dispose);
      controller.session = SessionModel.fromJson(_legacySession());
      controller.selectedAccess = controller.session!.workspaces.single;

      await tester.pumpWidget(
        MaterialApp(home: OrganizationResourcesScreen(controller: controller)),
      );

      expect(find.text('Use existing setup'), findsOneWidget);
      expect(
        find.textContaining('without entering cloud or GitHub credentials'),
        findsOneWidget,
      );
      expect(find.text('Add GitHub App'), findsNothing);
    },
  );
}

Map<String, Object?> _legacySession() => {
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
        'gcpResources': <Object?>[],
        'githubResources': <Object?>[],
        'runnerPools': <Object?>[],
      },
      'membership': {
        'role': 'admin',
        'roleLabel': 'Organization Admin',
        'effectiveCapabilities': [
          'org.integrations.manage',
          'org.runners.manage',
        ],
      },
    },
  ],
  'workspaces': [
    {
      'workspace': {
        'id': 'workspace-1',
        'name': 'Original workspace',
        'organizationId': 'org-1',
        'environment': 'dev',
        'githubInstallationId': 123,
        'repositories': ['acme/product'],
        'projects': <Object?>[],
        'workflows': <Object?>[],
        'connection': {
          'schemaVersion': 2,
          'workspaceId': 'workspace-1',
          'projectId': 'media-project',
          'projectNumber': '123456789012',
          'databaseId': '(default)',
          'region': 'us-central1',
          'bucket': 'media-project-assets',
          'dataServiceAccount': 'broker@platform.iam.gserviceaccount.com',
          'uploadServiceAccount':
              'upload@media-project.iam.gserviceaccount.com',
          'workloadIdentityProvider':
              'projects/123456789012/locations/global/'
              'workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
          'authProjectId': 'platform',
          'webOrigin': 'https://ii-os.example.com',
          'githubAppId': '123',
          'githubAppSecret': 'projects/media-project/secrets/github-app',
        },
      },
      'membership': {
        'workspaceId': 'workspace-1',
        'uid': 'admin-1',
        'email': 'admin@example.com',
        'role': 'owner',
        'roleLabel': 'Workspace Owner',
        'featureClaims': <Object?>[],
        'effectiveCapabilities': ['workspace.read', 'workspace.manage'],
      },
    },
  ],
};
