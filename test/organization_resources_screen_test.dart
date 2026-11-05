import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/organization_resources_screen.dart';
import 'package:ii_os/services/api_client.dart';
import 'package:ii_os/state/app_controller.dart';

import 'resource_view_model_fixtures.dart';

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
    // A deployment without a runner control plane can still make a workspace
    // dispatchable: the person describes the runners they already run.
    expect(find.text('Add your runners'), findsOneWidget);
    expect(_button(tester, 'Add your runners').onPressed, isNotNull);
    expect(find.text('Sync reported capacity'), findsOneWidget);
    expect(find.text('Sync Fleet capacity'), findsNothing);
    expect(find.textContaining('Fleet'), findsNothing);
    expect(find.textContaining('GitHub-hosted runners'), findsOneWidget);
  });

  testWidgets('a role that cannot manage runners sees why, beside the action', (
    tester,
  ) async {
    final controller = _controller(
      _sessionJson(capabilities: const ['org.integrations.manage']),
    );

    await tester.pumpWidget(
      MaterialApp(home: OrganizationResourcesScreen(controller: controller)),
    );

    expect(find.text('Add your runners'), findsOneWidget);
    expect(_button(tester, 'Add your runners').onPressed, isNull);
    expect(_button(tester, 'Sync reported capacity').onPressed, isNull);
    expect(
      find.textContaining('Only an Organization Admin can add or change'),
      findsOneWidget,
    );
  });

  testWidgets('adding your runners saves a customer pool', (tester) async {
    final controller = _controller(_sessionJson());
    final repository = FakeOrganizationResourceRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationResourcesScreen(
          controller: controller,
          repository: repository,
        ),
      ),
    );
    await tester.tap(find.text('Add your runners'));
    await tester.pumpAndSettle();

    expect(find.text('Workspaces can use these runners'), findsNothing);
    await tester.enterText(_field('Name'), 'GPU runners');
    await tester.enterText(_field('Runner group'), 'gpu-runners');
    await tester.enterText(
      _field('Capabilities'),
      'runtime-docker, gpu.nvidia',
    );
    await tester.enterText(_field('CPU cores'), '16');
    await tester.enterText(_field('Memory (MiB)'), '65536');
    await tester.enterText(_field('Jobs at once'), '2');
    await tester.tap(find.text('Add runners'));
    await tester.pumpAndSettle();

    final saved = repository.runner;
    expect(saved?.id, 'runner_gpu_runners');
    expect(saved?.provider, 'customer');
    expect(saved?.providerPoolId, 'gpu-runners');
    expect(saved?.capabilities, {'runtime-docker', 'gpu.nvidia'});
    expect(saved?.maxCpu, 16);
    expect(saved?.maxRamMiB, 65536);
    expect(saved?.maxConcurrent, 2);
    expect(find.text('Runner group'), findsNothing);
  });

  testWidgets('sync without a capacity report points to adding your runners', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _controller(_sessionJson());
    final repository = FakeOrganizationResourceRepository()
      ..failure = const RunnerPoolFailure(RunnerPoolFailureKind.notReported);

    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationResourcesScreen(
          controller: controller,
          repository: repository,
        ),
      ),
    );
    await tester.tap(find.text('Sync reported capacity'));
    await tester.pumpAndSettle();

    final message = find.textContaining('No capacity report has arrived');
    expect(message, findsOneWidget);
    // Rendered in the runner card, next to the action that failed.
    expect(
      find.ancestor(of: message, matching: find.byType(Card)),
      findsOneWidget,
    );
    expect(find.textContaining('Fleet'), findsNothing);
  });

  testWidgets('the runner form refuses a capability it cannot save', (
    tester,
  ) async {
    final controller = _controller(_sessionJson());
    final repository = FakeOrganizationResourceRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationResourcesScreen(
          controller: controller,
          repository: repository,
        ),
      ),
    );
    await tester.tap(find.text('Add your runners'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Name'), 'GPU runners');
    await tester.enterText(_field('Runner group'), 'gpu runners');
    await tester.enterText(_field('Capabilities'), 'gpu nvidia');
    await tester.enterText(_field('CPU cores'), '0');
    await tester.enterText(_field('Memory (MiB)'), '65536');
    await tester.enterText(_field('Jobs at once'), '2');
    await tester.tap(find.text('Add runners'));
    await tester.pumpAndSettle();

    expect(repository.runner, isNull);
    expect(find.textContaining('Use letters, digits'), findsOneWidget);
    expect(find.textContaining('Separate capabilities'), findsWidgets);
    expect(find.text('Enter a positive number.'), findsOneWidget);
  });

  for (final (label, size) in [
    ('desktop', const Size(1440, 1200)),
    ('phone', const Size(390, 844)),
  ]) {
    testWidgets(
      'your runners can be edited; reported runners cannot ($label)',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = _controller(_sessionJson(withRunners: true));
        final repository = FakeOrganizationResourceRepository();

        await tester.pumpWidget(
          MaterialApp(
            home: OrganizationResourcesScreen(
              controller: controller,
              repository: repository,
            ),
          ),
        );

        expect(find.byTooltip('Edit Studio runners'), findsOneWidget);
        expect(find.byTooltip('Edit Reported GPU pool'), findsNothing);
        expect(find.textContaining('Your runners · studio'), findsOneWidget);
        expect(
          find.textContaining('From your capacity report'),
          findsOneWidget,
        );

        await tester.ensureVisible(find.byTooltip('Edit Studio runners'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Edit Studio runners'));
        await tester.pumpAndSettle();
        expect(find.text('Edit your runners'), findsOneWidget);
        expect(
          tester.widget<TextFormField>(_field('Name')).controller?.text,
          'Studio runners',
        );
        await tester.ensureVisible(
          find.text('Workspaces can use these runners'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Workspaces can use these runners'));
        await tester.pump();
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();

        expect(repository.runner?.id, 'runner_studio');
        expect(repository.runner?.active, isFalse);
        expect(repository.runner?.capabilities, {'runtime-docker'});
      },
    );
  }

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

AppController _controller(Map<String, Object?> session) {
  final controller = AppController(
    api: ApiClient(baseUrl: '', reportFailures: false),
  );
  addTearDown(controller.dispose);
  controller.session = SessionModel.fromJson(session);
  controller.selectedAccess = controller.session!.workspaces.single;
  return controller;
}

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Map<String, Object?> _sessionJson({
  bool withLegacy = false,
  bool withRunners = false,
  List<String> capabilities = const [
    'org.integrations.manage',
    'org.runners.manage',
  ],
}) => {
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
        'runnerPools': [
          if (withRunners) ...[
            {
              'id': 'runner_fleet_0123456789ab',
              'name': 'Reported GPU pool',
              'provider': 'fleet',
              'providerPoolId': 'gpu-pool',
              'capabilities': ['gpu.nvidia'],
              'maxCpu': 16,
              'maxRamMiB': 65536,
              'maxConcurrent': 2,
              'active': true,
            },
            {
              'id': 'runner_studio',
              'name': 'Studio runners',
              'provider': 'customer',
              'providerPoolId': 'studio',
              'capabilities': ['runtime-docker'],
              'maxCpu': 8,
              'maxRamMiB': 16384,
              'maxConcurrent': 1,
              'active': true,
            },
          ],
        ],
      },
      'membership': {
        'role': 'admin',
        'roleLabel': 'Organization Admin',
        'effectiveCapabilities': capabilities,
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
