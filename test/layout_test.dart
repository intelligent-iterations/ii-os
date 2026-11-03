import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/job_repository.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';
import 'package:ii_os/screens/auth_screen.dart';
import 'package:ii_os/screens/character_builder_screen.dart';
import 'package:ii_os/screens/character_detail_screen.dart';
import 'package:ii_os/screens/data_plane_connection_screen.dart';
import 'package:ii_os/screens/home_screen.dart';
import 'package:ii_os/screens/narration_generation_screen.dart';
import 'package:ii_os/screens/no_workspace_screen.dart';
import 'package:ii_os/screens/song_generation_screen.dart';
import 'package:ii_os/screens/video_generation_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/people_directory.dart';

void main() {
  test('new accounts have no inherited data-plane connection', () {
    final controller = AppController();
    addTearDown(controller.dispose);

    expect(controller.api.baseUrl, '/api');
    expect(controller.connection, isNull);
  });

  testWidgets('authentication surface fits a mobile viewport', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(theme: IiOsTheme.light(), home: const AuthScreen()),
      );
      await tester.pump();

      expect(find.text('ii-os'), findsOneWidget);
      expect(find.text('Send sign-in code'), findsOneWidget);
      expect(find.textContaining('No password needed'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Password'), findsNothing);
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('home KPI surface fits desktop and mobile widths', (
    tester,
  ) async {
    final controller = AppController()
      ..session = const SessionModel(
        user: UserProfile(
          uid: 'owner-1',
          email: 'owner@example.com',
          displayName: 'Owner',
          isOwner: true,
        ),
        workspaces: [],
      )
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['image-create'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'owner-1',
          email: 'owner@example.com',
          role: 'owner',
          roleLabel: 'Owner',
          featureClaims: {},
          capabilities: {'workspace.read'},
        ),
      )
      ..dashboard = const {
        'activeJobs': 2,
        'completedJobs': 8,
        'openTickets': 4,
        'members': 3,
      };
    addTearDown(controller.dispose);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(body: HomeScreen(controller: controller)),
        ),
      );
      await tester.pump();
      expect(find.text('Active jobs'), findsOneWidget);
      expect(find.text('Workspace connections'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('invitation recovery fits a mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()
      ..session = const SessionModel(
        user: UserProfile(
          uid: 'editor-1',
          email: 'editor@example.com',
          displayName: 'Editor',
          isOwner: false,
        ),
        workspaces: [],
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: NoWorkspaceScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Create or join a workspace'), findsOneWidget);
    expect(find.text('Signed in as editor@example.com'), findsOneWidget);
    expect(find.text('Create workspace'), findsOneWidget);
    expect(find.text('Join an existing workspace'), findsOneWidget);
    expect(find.text('Review invitations'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an organization member creates a workspace inside that tenant', (
    tester,
  ) async {
    final controller = AppController()
      ..session = const SessionModel(
        user: UserProfile(
          uid: 'owner-1',
          email: 'owner@example.com',
          displayName: 'Owner',
          isOwner: false,
        ),
        workspaces: [],
        organizations: [
          OrganizationAccess(
            id: 'org-1',
            name: 'Intelligent Iterations',
            role: 'Owner',
            capabilities: {
              'org.read',
              'org.workspaces.create',
              'org.integrations.manage',
            },
          ),
        ],
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: NoWorkspaceScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Intelligent Iterations'), findsOneWidget);
    expect(find.text('Workspace name'), findsOneWidget);
    expect(find.text('Create workspace'), findsOneWidget);
    expect(
      find.textContaining('GCP, GitHub, and Fleet connections'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('retired connection URL has no credential import controls', (
    tester,
  ) async {
    final controller = AppController()..loading = false;
    addTearDown(controller.dispose);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: DataPlaneConnectionScreen(controller: controller),
        ),
      );
      await tester.pump();
      expect(find.text('Organization setup unavailable'), findsOneWidget);
      expect(find.text('Reload session'), findsOneWidget);
      expect(find.textContaining('Import'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('old connection route opens organization resources', (
    tester,
  ) async {
    final controller = AppController()
      ..loading = false
      ..session = const SessionModel(
        user: UserProfile(
          uid: 'owner-1',
          email: 'admin@example.com',
          displayName: 'Admin',
          isOwner: true,
        ),
        organizations: [
          OrganizationAccess(
            id: 'org-1',
            name: 'Intelligent Iterations',
            role: 'Owner',
            capabilities: {
              'org.read',
              'org.workspaces.create',
              'org.integrations.manage',
              'org.runners.manage',
            },
          ),
        ],
        workspaces: [
          WorkspaceAccess(
            workspace: WorkspaceModel(
              id: 'wrong-workspace',
              name: 'New workspace',
              organizationId: 'org-1',
              environment: 'dev',
              githubInstallationId: null,
              repositories: [],
              projects: [],
              workflows: [],
              artifactStorage: null,
            ),
            membership: MembershipModel(
              workspaceId: 'wrong-workspace',
              uid: 'owner-1',
              email: 'admin@example.com',
              role: 'owner',
              roleLabel: 'Owner',
              featureClaims: {},
              capabilities: {'workspace.manage'},
            ),
          ),
          WorkspaceAccess(
            workspace: WorkspaceModel(
              id: 'workspace-admin',
              name: 'Admin workspace',
              organizationId: 'org-1',
              environment: 'dev',
              githubInstallationId: null,
              repositories: [],
              projects: [],
              workflows: [],
              artifactStorage: null,
            ),
            membership: MembershipModel(
              workspaceId: 'workspace-admin',
              uid: 'owner-1',
              email: 'admin@example.com',
              role: 'owner',
              roleLabel: 'Owner',
              featureClaims: {},
              capabilities: {'workspace.manage'},
            ),
          ),
        ],
      )
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'wrong-workspace',
          name: 'New workspace',
          organizationId: 'org-1',
          environment: 'dev',
          githubInstallationId: null,
          repositories: [],
          projects: [],
          workflows: [],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'wrong-workspace',
          uid: 'owner-1',
          email: 'admin@example.com',
          role: 'owner',
          roleLabel: 'Owner',
          featureClaims: {},
          capabilities: {'workspace.manage'},
        ),
      );
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: DataPlaneConnectionScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Organization resources'), findsOneWidget);
    expect(find.text('Connect GCP project'), findsOneWidget);
    expect(find.textContaining('Import'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('video generation form fits desktop and mobile widths', (
    tester,
  ) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#image-to-video'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {'jobs.trigger'},
          capabilities: {'jobs.read', 'jobs.trigger'},
        ),
      );
    addTearDown(controller.dispose);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(body: VideoGenerationScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video generation'), findsOneWidget);
      expect(find.text('Landscape'), findsOneWidget);
      expect(find.text('24 FPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('song generation form fits desktop and mobile widths', (
    tester,
  ) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#song-create-acestep-xl-sft'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {'jobs.trigger'},
          capabilities: {'jobs.read', 'jobs.trigger'},
        ),
      );
    addTearDown(controller.dispose);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(body: SongGenerationScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Song generation'), findsOneWidget);
      expect(find.text('Instrumental'), findsOneWidget);
      expect(find.text('Generate song'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('narration generation form fits desktop and mobile widths', (
    tester,
  ) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#narration-create-chatterbox-tts'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {'jobs.trigger'},
          capabilities: {'jobs.read', 'jobs.trigger'},
        ),
      );
    addTearDown(controller.dispose);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            body: NarrationGenerationScreen(
              controller: controller,
              templateRepository: _LayoutTemplates([
                _workflowTemplate(
                  id: 'acme/media#narration-create-chatterbox-tts',
                  workflowId: 'narration-create-chatterbox-tts',
                  displayName: 'Chatterbox Narration',
                  model: 'Chatterbox Turbo TTS',
                ),
              ]),
              jobRepository: const _LayoutJobs(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Narration'), findsOneWidget);
      expect(find.text('Chatterbox Turbo'), findsOneWidget);
      expect(find.text('Use voice clone reference'), findsOneWidget);
      expect(find.text('Generate narration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'team members and pending invites fit desktop and mobile widths',
    (tester) async {
      const directory = OrganizationPeopleModel(
        people: [
          OrganizationPersonModel(
            uid: 'owner-1',
            email: 'owner@example.com',
            role: 'owner',
            roleLabel: 'Organization Owner',
          ),
        ],
        workspaces: [
          OrganizationWorkspaceModel(
            id: 'workspace-1',
            name: 'Media operations',
            environment: 'dev',
          ),
        ],
        invitations: [
          OrganizationInvitationModel(
            id: '11111111-1111-4111-8111-111111111111',
            email: 'editor@example.com',
            role: 'member',
            roleLabel: 'Organization Member',
            workspaceIds: ['workspace-1'],
            deliveryStatus: 'delivered',
            expiresAt: null,
          ),
        ],
      );

      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: IiOsTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PeopleDirectory(
                  directory: directory,
                  people: directory.people,
                  onManageAccess: (_) {},
                  onRevokeInvitation: (_) {},
                  isRevoking: (_) => false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('People'), findsOneWidget);
        expect(find.text('Pending invitations'), findsOneWidget);
        expect(find.text('editor@example.com'), findsOneWidget);
        expect(find.text('Email sent'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('character builder fits a mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: null,
          repositories: [],
          projects: [],
          workflows: [],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {
            'characters.read',
            'characters.write',
            'jobs.trigger',
          },
          capabilities: {'characters.read', 'characters.write', 'jobs.trigger'},
        ),
      );
    addTearDown(controller.dispose);
    const character = CharacterModel(
      id: 'character-1',
      workspaceId: 'workspace-1',
      name: 'Untitled character',
      answers: {},
      prompt: 'Permanent character-sheet specification',
      bodyPrompt: 'TEXT-TO-IMAGE FULL-BODY CHARACTER SHEET',
      status: 'draft',
      thumbnailUrl: null,
      createdAt: null,
      updatedAt: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: CharacterBuilderScreen(
            key: const ValueKey('saved-prompt-character'),
            controller: controller,
            character: character,
            onSaved: (_) {},
            onGenerated: (_, _, _) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Character builder'), findsOneWidget);
    expect(
      find.text('Build one final full-body reference sheet'),
      findsNothing,
    );
    expect(find.text('Output 1 of 2'), findsNothing);
    expect(find.text('Output 2 of 2'), findsNothing);
    expect(find.text('Shape the character'), findsOneWidget);
    expect(
      find.text('What shape is the character\u2019s face?'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('character-combined-silhouette')),
      findsOneWidget,
    );
    expect(find.text('Required views in this output'), findsNothing);
    expect(find.text('Side profile'), findsNothing);
    expect(find.text('Back profile'), findsNothing);
    expect(find.text('Full-body generation prompt'), findsOneWidget);
    final generate = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate'),
    );
    expect(generate.onPressed, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: CharacterBuilderScreen(
            key: const ValueKey('missing-prompt-character'),
            controller: controller,
            character: const CharacterModel(
              id: 'character-2',
              workspaceId: 'workspace-1',
              name: 'Untitled character',
              answers: {},
              prompt: '',
              status: 'draft',
              thumbnailUrl: null,
              createdAt: null,
              updatedAt: null,
            ),
            onSaved: (_) {},
            onGenerated: (_, _, _) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    final missingPrompt = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate'),
    );
    expect(missingPrompt.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed character exposes the generation job action', (
    tester,
  ) async {
    final controller = AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Media operations',
          environment: 'dev',
          githubInstallationId: 12,
          repositories: ['acme/media'],
          projects: [],
          workflows: ['acme/media#image-create'],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'editor-1',
          email: 'editor@example.com',
          role: 'editor',
          roleLabel: 'Editor',
          featureClaims: {'characters.write', 'jobs.trigger'},
          capabilities: {'characters.write', 'jobs.trigger'},
        ),
      );
    addTearDown(controller.dispose);
    const character = CharacterModel(
      id: 'character-1',
      workspaceId: 'workspace-1',
      name: 'Amaru',
      answers: {},
      prompt: 'Saved Z-Image prompt',
      bodyPrompt: 'Saved body expansion prompt',
      status: 'ready',
      thumbnailUrl: null,
      createdAt: null,
      updatedAt: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: CharacterDetailScreen(
            controller: controller,
            character: character,
            canWrite: true,
            initialGeneration: const {
              'jobId': 'job-123',
              'status': 'dispatched',
            },
            initialImages: const [
              CharacterImageModel(
                jobId: 'job-122',
                path: 'workspaces/workspace-1/runs/job-122/older-character.png',
                generation: '41',
                contentType: 'image/png',
                url: '',
                urlErrorCode: 'workspace_not_connected',
                urlErrorMessage:
                    'Connect this workspace to its customer-owned data plane first.',
                selected: false,
                createdAt: null,
              ),
              CharacterImageModel(
                jobId: 'job-123',
                path: 'workspaces/workspace-1/runs/job-123/new-character.png',
                generation: '42',
                contentType: 'image/png',
                url: '',
                selected: false,
                createdAt: null,
              ),
            ],
            onSaved: (_) {},
            onDeleted: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Generate full-body sheet'), findsOneWidget);
    expect(find.text('Job submitted'), findsNothing);
    expect(find.text('job-123'), findsNothing);
    expect(find.text('Historical references'), findsNothing);
    expect(
      find.byKey(const ValueKey('character-history-thumbnails')),
      findsOneWidget,
    );
    expect(find.text('Shape the character'), findsOneWidget);
    expect(find.text('Shape the head'), findsNothing);
    expect(find.text('Shape the full body'), findsNothing);
    expect(find.text('Output 1 · Close-up head sheets'), findsNothing);
    expect(find.byKey(const ValueKey('character-essentials')), findsOneWidget);
    expect(find.text('Goal (optional)'), findsNothing);
    expect(find.text('Selected'), findsNothing);
    expect(
      find.text('What shape is the character\u2019s face?'),
      findsOneWidget,
    );
    expect(find.text('Character name (optional)'), findsOneWidget);

    final generateBody = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate full-body sheet'),
    );
    expect(generateBody.onPressed, isNotNull);
    expect(find.text('Output 2 · Full-body sheets'), findsNothing);
    expect(find.text('Full-body generation prompt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _LayoutTemplates implements WorkflowTemplateRepository {
  const _LayoutTemplates(this.templates);

  final List<WorkflowTemplateModel> templates;

  @override
  Future<List<WorkflowTemplateModel>> list(
    String workspaceId, {
    String? workflowIdPrefix,
  }) async => templates
      .where(
        (template) =>
            workflowIdPrefix == null ||
            template.workflowId.startsWith(workflowIdPrefix),
      )
      .toList(growable: false);
}

final class _LayoutJobs implements JobRepository {
  @override
  Future<JobListing> list(String workspaceId) async => JobListing.empty;

  @override
  Future<JsonMap> detail(String workspaceId, String jobId) async => const {};

  const _LayoutJobs();

  @override
  Future<JsonMap> submit(String workspaceId, JobSubmission submission) async =>
      const {'jobId': 'layout-job', 'status': 'requested'};
}

WorkflowTemplateModel _workflowTemplate({
  required String id,
  required String workflowId,
  required String displayName,
  required String model,
}) => WorkflowTemplateModel(
  id: id,
  workflowId: workflowId,
  version: '1',
  displayName: displayName,
  model: model,
  repository: 'acme/media',
  enabled: true,
  disabledReason: '',
);
