import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';

/// Renders whole pages for visual review.
///
/// `golden_harness.dart` wraps a single widget at 360px, which is the right
/// frame for a component. This one seeds a workspace and renders a page at a
/// real viewport, so the golden shows what an operator sees rather than a
/// component on a blank canvas.
///
/// There is no network here. A page that fetches on init renders its failure
/// surface, and that is deliberate: it is a state every one of these pages can
/// reach, it is the one nobody looks at, and it is where broken layout hides.

/// Every capability the UI gates on, so a page renders its full surface
/// instead of the reduced read-only variant.
///
/// Collected from every `controller.can(...)` call site. A new capability that
/// is not added here shows up as a page quietly losing a control in its golden.
const iiOsAllCapabilities = <String>{
  'agent.permissions.manage',
  'agent.permissions.read',
  'audit.read',
  'characters.read',
  'characters.write',
  'jobs.read',
  'jobs.trigger',
  'lines.read',
  'members.manage',
  'tickets.read',
  'tickets.write',
  'workspace.manage',
};

/// The desktop viewport the goldens are captured at.
const iiOsDesktopViewport = Size(1440, 900);

/// The mobile viewport, for pages whose layout switches.
const iiOsMobileViewport = Size(390, 844);

/// A controller already signed in to a workspace.
///
/// The caller owns disposal; every test that builds one must
/// `addTearDown(controller.dispose)`.
AppController pageController({
  Set<String> capabilities = iiOsAllCapabilities,
  List<String> workflows = const [
    'image-create',
    'video-create',
    'song-create',
  ],
}) {
  return AppController()
    ..session = const SessionModel(
      user: UserProfile(
        uid: 'owner-1',
        email: 'owner@example.com',
        displayName: 'Owner',
        isOwner: true,
      ),
      workspaces: [],
    )
    ..selectedAccess = WorkspaceAccess(
      workspace: WorkspaceModel(
        id: 'workspace-1',
        name: 'Media operations',
        environment: 'dev',
        githubInstallationId: 12,
        repositories: const ['acme/media'],
        projects: const [],
        workflows: workflows,
        artifactStorage: null,
      ),
      membership: MembershipModel(
        workspaceId: 'workspace-1',
        uid: 'owner-1',
        email: 'owner@example.com',
        role: 'owner',
        roleLabel: 'Owner',
        featureClaims: const {},
        capabilities: capabilities,
      ),
    )
    ..dashboard = const {
      'activeJobs': 2,
      'completedJobs': 8,
      'openTickets': 4,
      'members': 3,
    };
}

/// Re-seeds [controller] with a representative organization resource catalog.
///
/// The resource administration pages require an organization-owned catalog,
/// while older page goldens intentionally retain their legacy workspace
/// fixture. Keeping the richer fixture local to those pages avoids changing
/// unrelated visual baselines.
///
/// [withCustomerRunners] adds a pool the organization keeps by hand, so the
/// organization resources page shows both kinds of runner pool.
AppController seedResourcePageController(
  AppController controller, {
  bool withCustomerRunners = false,
}) {
  controller.session = SessionModel.fromJson(
    withCustomerRunners
        ? _withCustomerRunners(_resourceSessionFixture)
        : _resourceSessionFixture,
  );
  controller.selectedAccess = controller.session!.workspaces.single;
  return controller;
}

Map<String, Object?> _withCustomerRunners(Map<String, Object?> fixture) {
  final session = jsonDecode(jsonEncode(fixture)) as Map<String, Object?>;
  final access = (session['organizations']! as List<Object?>).single!;
  final organization =
      (access as Map<String, Object?>)['organization']! as Map<String, Object?>;
  (organization['runnerPools']! as List<Object?>).add({
    'id': 'runner_studio_runners',
    'name': 'Studio runners',
    'provider': 'customer',
    'providerPoolId': 'studio-runners',
    'capabilities': ['gpu.nvidia', 'runtime-docker'],
    'maxCpu': 8,
    'maxRamMiB': 32768,
    'maxConcurrent': 1,
    'active': true,
  });
  return session;
}

final _resourceSessionFixture = <String, Object?>{
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
        'name': 'Acme Organization',
        'resourceCatalogVersion': 1,
        'gcpResources': [
          {
            'id': 'gcp_media',
            'name': 'Media production',
            'connection': {
              'schemaVersion': 4,
              'organizationId': 'org-1',
              'projectId': 'acme-media',
              'projectNumber': '123456789012',
              'databaseId': '(default)',
              'region': 'us-central1',
              'bucket': 'acme-media-assets',
              'dataServiceAccount':
                  'broker@platform-project.iam.gserviceaccount.com',
              'uploadServiceAccount':
                  'upload@acme-media.iam.gserviceaccount.com',
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
            'id': 'gcp_analytics',
            'name': 'Analytics',
            'connection': {
              'schemaVersion': 4,
              'organizationId': 'org-1',
              'projectId': 'acme-analytics',
              'projectNumber': '987654321098',
              'databaseId': '(default)',
              'region': 'us-central1',
              'bucket': 'acme-analytics-assets',
              'dataServiceAccount':
                  'broker@platform-project.iam.gserviceaccount.com',
              'uploadServiceAccount':
                  'upload@acme-analytics.iam.gserviceaccount.com',
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
            'secretGcpResourceId': 'gcp_media',
            'appId': '12345',
            'privateKeySecret':
                'projects/acme-media/secrets/github-app-key/versions/latest',
            'installationId': 321,
            'repositories': ['acme/product', 'acme/mobile'],
            'permissionEnvelope': ['contents:write', 'pull_requests:write'],
            'active': true,
          },
        ],
        'runnerPools': [
          {
            'id': 'runner_gpu',
            'name': 'GPU production pool',
            'provider': 'fleet',
            'capabilities': ['comfyui', 'gpu.nvidia'],
            'maxCpu': 16,
            'maxRamMiB': 65536,
            'maxConcurrent': 2,
            'active': true,
          },
        ],
      },
      'membership': {
        'role': 'admin',
        'roleLabel': 'Organization Admin',
        'effectiveCapabilities': [
          'org.integrations.manage',
          'org.members.manage',
          'org.runners.manage',
          'org.workspaces.access.manage',
        ],
      },
    },
  ],
  'workspaces': [
    {
      'workspace': {
        'id': 'workspace-1',
        'name': 'Media operations',
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
              'permissions': ['assets.read', 'assets.write'],
              'primary': true,
            },
          ],
          'github': [
            {
              'resourceId': 'github_product',
              'repositories': ['acme/product'],
              'permissions': ['contents:write'],
              'primary': true,
            },
          ],
          'runners': [
            {
              'resourceId': 'runner_gpu',
              'capabilities': ['comfyui'],
              'maxCpu': 8,
              'maxRamMiB': 32768,
              'maxConcurrent': 1,
              'primary': true,
            },
          ],
        },
      },
      'membership': {
        'workspaceId': 'workspace-1',
        'uid': 'admin-1',
        'email': 'admin@example.com',
        'role': 'admin',
        'roleLabel': 'Workspace Admin',
        'featureClaims': <Object?>[],
        'effectiveCapabilities': ['workspace.read', 'workspace.manage'],
      },
    },
  ],
};

/// Pumps [page] at [size] and settles the frame.
///
/// Uses `pump` with a fixed elapsed time rather than `pumpAndSettle`: several
/// pages hold an indeterminate progress indicator, which never settles and
/// would hang the test instead of failing it.
Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  Size size = iiOsDesktopViewport,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: IiOsTheme.light(),
      home: Scaffold(body: page),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// Loads the brand typeface and the icon font.
///
/// Lucide matters as much as Inter here: without it every icon renders as a
/// tofu box, and a page full of identical grey squares hides exactly the
/// problems these goldens exist to catch -- a wrong glyph, a missing one, or an
/// icon sized off the scale.
Future<void> loadPageFonts() async {
  final brand = FontLoader(iiOsFontFamily);
  for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    brand.addFont(
      rootBundle.load('packages/ii_os_design_system/fonts/Manrope-$weight.ttf'),
    );
  }
  await brand.load();

  final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
  await lucide.load();
}
