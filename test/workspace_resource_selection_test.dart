import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/workspace_resource_selection_screen.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/state/app_controller.dart';

void main() {
  testWidgets('workspace selects inherited resources without credentials', (
    tester,
  ) async {
    final controller = AppController(
      api: ApiClient(baseUrl: '', reportFailures: false),
    );
    addTearDown(controller.dispose);
    controller.session = SessionModel.fromJson(_sessionJson());
    controller.selectedAccess = controller.session!.workspaces.single;

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceResourceSelectionScreen(controller: controller),
      ),
    );

    expect(find.text('Workspace access'), findsOneWidget);
    expect(
      find.textContaining('available from Acme Organization'),
      findsOneWidget,
    );
    expect(find.textContaining('Media project'), findsWidgets);
    expect(find.textContaining('Product GitHub App'), findsWidgets);
    expect(find.textContaining('GPU pool'), findsWidgets);
    expect(
      find.textContaining('may receive several resources'),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not enable workflows automatically'),
      findsOneWidget,
    );
    expect(find.text('Next: discover workflows'), findsOneWidget);
    expect(
      find.widgetWithText(FilterChip, 'Media project · primary'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilterChip, 'Archive project'), findsOneWidget);
    expect(
      find.widgetWithText(FilterChip, 'Operations GitHub App'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilterChip, 'CPU pool'), findsOneWidget);
    expect(find.textContaining('private key'), findsNothing);
    expect(find.textContaining('Secret Manager'), findsNothing);
  });
}

Map<String, Object?> _sessionJson() => {
  'user': {
    'uid': 'user-1',
    'email': 'admin@example.com',
    'displayName': 'Admin',
    'isOwner': false,
  },
  'organizations': [
    {
      'organization': {
        'id': 'org-1',
        'name': 'Acme Organization',
        'resourceCatalogVersion': 1,
        'gcpResources': [
          {
            'id': 'gcp_media',
            'name': 'Media project',
            'connection': {
              'schemaVersion': 4,
              'organizationId': 'org-1',
              'projectId': 'media-project',
              'projectNumber': '123456789012',
              'databaseId': '(default)',
              'region': 'us-central1',
              'bucket': 'media-project-assets',
              'dataServiceAccount':
                  'broker@platform-project.iam.gserviceaccount.com',
              'uploadServiceAccount':
                  'upload@media-project.iam.gserviceaccount.com',
              'workloadIdentityProvider': 'provider',
              'authProjectId': 'platform-project',
              'webOrigin': 'https://ii-os.example.com',
            },
            'permissionEnvelope': [
              'assets.read',
              'assets.write',
              'workflows.upload',
            ],
            'active': true,
          },
          {
            'id': 'gcp_archive',
            'name': 'Archive project',
            'connection': {
              'schemaVersion': 4,
              'organizationId': 'org-1',
              'projectId': 'archive-project',
              'projectNumber': '123456789013',
              'databaseId': '(default)',
              'region': 'us-central1',
              'bucket': 'archive-project-assets',
              'dataServiceAccount':
                  'broker@platform-project.iam.gserviceaccount.com',
              'uploadServiceAccount':
                  'upload@archive-project.iam.gserviceaccount.com',
              'workloadIdentityProvider': 'provider',
              'authProjectId': 'platform-project',
              'webOrigin': 'https://ii-os.example.com',
            },
            'permissionEnvelope': ['assets.read'],
            'active': true,
          },
        ],
        'githubResources': [
          {
            'id': 'github_product',
            'name': 'Product GitHub App',
            'installationId': 123,
            'repositories': ['acme/product'],
            'permissionEnvelope': ['contents:write'],
            'active': true,
          },
          {
            'id': 'github_ops',
            'name': 'Operations GitHub App',
            'installationId': 124,
            'repositories': ['acme/operations'],
            'permissionEnvelope': ['contents:read'],
            'active': true,
          },
        ],
        'runnerPools': [
          {
            'id': 'runner_gpu',
            'name': 'GPU pool',
            'provider': 'fleet',
            'capabilities': ['gpu.nvidia'],
            'maxCpu': 8,
            'maxRamMiB': 32768,
            'maxConcurrent': 1,
            'active': true,
          },
          {
            'id': 'runner_cpu',
            'name': 'CPU pool',
            'provider': 'fleet',
            'capabilities': ['build.linux'],
            'maxCpu': 8,
            'maxRamMiB': 16384,
            'maxConcurrent': 2,
            'active': true,
          },
        ],
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
        'id': 'workspace-1',
        'name': 'Product',
        'organizationId': 'org-1',
        'environment': 'dev',
        'repositories': <Object?>[],
        'projects': <Object?>[],
        'workflows': <Object?>[],
        'resourceGrantVersion': 1,
        'resourceGrants': {
          'gcp': [
            {
              'resourceId': 'gcp_media',
              'permissions': ['assets.read'],
              'primary': true,
            },
            {
              'resourceId': 'gcp_archive',
              'permissions': ['assets.read'],
              'primary': false,
            },
          ],
          'github': [
            {
              'resourceId': 'github_product',
              'repositories': ['acme/product'],
              'permissions': ['contents:write'],
              'primary': true,
            },
            {
              'resourceId': 'github_ops',
              'repositories': ['acme/operations'],
              'permissions': ['contents:read'],
              'primary': false,
            },
          ],
          'runners': [
            {
              'resourceId': 'runner_gpu',
              'capabilities': ['gpu.nvidia'],
              'maxCpu': 8,
              'maxRamMiB': 32768,
              'maxConcurrent': 1,
              'primary': true,
            },
            {
              'resourceId': 'runner_cpu',
              'capabilities': ['build.linux'],
              'maxCpu': 4,
              'maxRamMiB': 8192,
              'maxConcurrent': 1,
              'primary': false,
            },
          ],
        },
      },
      'membership': {
        'workspaceId': 'workspace-1',
        'uid': 'user-1',
        'email': 'admin@example.com',
        'role': 'admin',
        'roleLabel': 'Workspace Admin',
        'featureClaims': <Object?>[],
        'effectiveCapabilities': ['workspace.read', 'workspace.manage'],
      },
    },
  ],
};
