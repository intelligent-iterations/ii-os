import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/organization_resources_screen.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/state/app_controller.dart';

void main() {
  testWidgets('organization admin sees each resource pool and add action', (
    tester,
  ) async {
    final controller = AppController(
      api: ApiClient(baseUrl: '', reportFailures: false),
    );
    addTearDown(controller.dispose);
    controller.session = SessionModel.fromJson(_sessionJson());
    controller.selectedAccess = controller.session!.workspaces.single;

    await tester.pumpWidget(
      MaterialApp(home: OrganizationResourcesScreen(controller: controller)),
    );

    expect(find.text('Organization resources'), findsOneWidget);
    expect(find.text('GCP projects'), findsOneWidget);
    expect(find.text('GitHub Apps'), findsOneWidget);
    expect(find.text('Runner pools'), findsOneWidget);
    expect(find.text('Connect GCP project'), findsOneWidget);
    expect(find.text('Add GitHub App'), findsNothing);
    expect(find.text('Sync Fleet capacity'), findsOneWidget);
    expect(find.text('Add runner pool'), findsNothing);
    expect(find.textContaining('GitHub-hosted runners'), findsOneWidget);
  });

  testWidgets('empty catalog offers the existing workspace setup', (
    tester,
  ) async {
    final controller = AppController(
      api: ApiClient(baseUrl: '', reportFailures: false),
    );
    addTearDown(controller.dispose);
    controller.session = SessionModel.fromJson(_sessionJson(withLegacy: true));
    controller.selectedAccess = controller.session!.workspaces.firstWhere(
      (access) => access.workspace.id == 'workspace-1',
    );

    await tester.pumpWidget(
      MaterialApp(home: OrganizationResourcesScreen(controller: controller)),
    );

    expect(find.text('Use existing setup'), findsOneWidget);
    expect(find.textContaining('without entering cloud'), findsOneWidget);
  });

  testWidgets('attached legacy setup offers an exact permission refresh', (
    tester,
  ) async {
    final controller = AppController(
      api: ApiClient(baseUrl: '', reportFailures: false),
    );
    addTearDown(controller.dispose);
    controller.session = SessionModel.fromJson(_attachedLegacySessionJson());
    controller.selectedAccess = controller.session!.workspaces.firstWhere(
      (access) => access.workspace.id == 'workspace-1',
    );

    await tester.pumpWidget(
      MaterialApp(home: OrganizationResourcesScreen(controller: controller)),
    );

    expect(find.text('Refresh GitHub permissions'), findsOneWidget);
    expect(
      find.textContaining('accepted permissions from GitHub'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No credential is copied or rotated'),
      findsOneWidget,
    );
    expect(find.text('connected'), findsWidgets);
    expect(find.text('Add another GCP project'), findsOneWidget);
    expect(find.text('Connect or refresh GCP project'), findsNothing);
  });

  testWidgets('GCP onboarding accepts service account paste or file', (
    tester,
  ) async {
    final controller = AppController(
      api: ApiClient(baseUrl: '', reportFailures: false),
    );
    addTearDown(controller.dispose);
    controller.session = SessionModel.fromJson(_sessionJson());
    controller.selectedAccess = controller.session!.workspaces.single;

    await tester.pumpWidget(
      MaterialApp(home: OrganizationResourcesScreen(controller: controller)),
    );
    await tester.tap(find.text('Connect GCP project'));
    await tester.pumpAndSettle();

    expect(find.text('Service account JSON'), findsOneWidget);
    expect(find.text('Choose JSON file'), findsOneWidget);
    expect(find.textContaining('manifest'), findsNothing);
    expect(find.textContaining('never stored'), findsOneWidget);
    expect(find.textContaining('ii_os_resource=github_app'), findsOneWidget);
    expect(find.textContaining('ii_os_organization_id=org-1'), findsOneWidget);
    expect(find.textContaining('schemaVersion'), findsOneWidget);
    expect(find.textContaining('appId'), findsOneWidget);
    final secretField = tester
        .widgetList<TextField>(find.byType(TextField))
        .singleWhere(
          (field) => field.decoration?.labelText == 'Service account JSON',
        );
    expect(secretField.obscureText, isTrue);
    expect(find.byTooltip('Show service account JSON'), findsOneWidget);
  });
}

Map<String, Object?> _sessionJson({bool withLegacy = false}) => {
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
        'name': 'Product',
        'organizationId': 'org-1',
        'environment': 'dev',
        'repositories': <Object?>[],
        'projects': <Object?>[],
        'workflows': <Object?>[],
      },
      'membership': {
        'workspaceId': 'workspace-1',
        'uid': 'admin-1',
        'email': 'admin@example.com',
        'role': 'view_only',
        'roleLabel': 'Workspace Viewer',
        'featureClaims': <Object?>[],
        'effectiveCapabilities': ['workspace.read'],
      },
    },
    if (withLegacy)
      {
        'workspace': {
          'id': 'workspace-existing',
          'name': 'Existing',
          'organizationId': 'org-1',
          'environment': 'dev',
          'repositories': ['acme/product'],
          'projects': <Object?>[],
          'workflows': <Object?>[],
          'connection': {
            'schemaVersion': 2,
            'workspaceId': 'workspace-existing',
            'projectId': 'media-project',
            'projectNumber': '123456789012',
            'databaseId': '(default)',
            'region': 'us-central1',
            'bucket': 'media-project-assets',
            'dataServiceAccount': 'broker@platform.iam.gserviceaccount.com',
            'uploadServiceAccount':
                'upload@media-project.iam.gserviceaccount.com',
            'workloadIdentityProvider':
                'projects/123456789012/locations/global/workloadIdentityPools/ii-os-github/providers/ii-os-workflows',
            'authProjectId': 'platform',
            'webOrigin': 'https://ii-os.example.com',
            'githubAppId': '123',
            'githubAppSecret': 'projects/media-project/secrets/github-app',
          },
        },
        'membership': {
          'workspaceId': 'workspace-existing',
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

Map<String, Object?> _attachedLegacySessionJson() {
  final session = _sessionJson(withLegacy: true);
  final organizations = session['organizations']! as List<Object?>;
  final organizationAccess = organizations.single! as Map<String, Object?>;
  final organization =
      organizationAccess['organization']! as Map<String, Object?>;
  final workspaces = session['workspaces']! as List<Object?>;
  final legacyAccess = workspaces.last! as Map<String, Object?>;
  final legacyWorkspace = legacyAccess['workspace']! as Map<String, Object?>;
  final connection = legacyWorkspace['connection']! as Map<String, Object?>;
  organization['gcpResources'] = [
    {
      'id': 'gcp_legacy_primary',
      'name': 'Existing GCP project',
      'connection': connection,
      'permissionEnvelope': ['assets.read'],
      'active': true,
      'legacySourceWorkspaceId': 'workspace-existing',
    },
  ];
  return session;
}
