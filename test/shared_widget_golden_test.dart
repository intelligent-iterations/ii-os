@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/data_plane_connection.dart';
import 'package:ii_os/models/github_setup_readiness.dart';
import 'package:ii_os/models/generation_history.dart';
import 'package:ii_os/services/verified_artifact_media.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/widgets/artifact_thumbnail.dart';
import 'package:ii_os/widgets/common.dart';
import 'package:ii_os/widgets/media_library_tile.dart';
import 'package:ii_os/repositories/generation_history_repository.dart';
import 'package:ii_os/widgets/media_library_body.dart';
import 'package:ii_os/widgets/media_library_grid.dart';
import 'package:ii_os/widgets/media_library_view.dart';
import 'package:ii_os/widgets/media_picker.dart';
import 'package:ii_os/widgets/media_upload_pane.dart';
import 'package:ii_os/widgets/data_plane_status.dart';
import 'package:ii_os/widgets/github_setup_onboarding.dart';
import 'package:ii_os/widgets/image_generation_form.dart';
import 'package:ii_os/widgets/ii_os_app_title.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:ii_os/widgets/voice_clone_reference_field.dart';
import 'package:ii_os/widgets/model_choice.dart';
import 'package:ii_os/widgets/model_choice_cards.dart';
import 'package:ii_os/widgets/workflow_unavailable_notice.dart';
import 'package:ii_os/widgets/workspace_creation_dialog.dart';
import 'package:ii_os/widgets/workspace_connection_row.dart';
import 'package:file_selector/file_selector.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'golden_harness.dart';

/// Goldens for the shared widgets, so a theme or token change has to be
/// deliberate.
///
/// Tagged `golden` because these compare rendered pixels and are therefore tied
/// to the Flutter revision and the host platform that generated them. Regenerate
/// with:
///
///     flutter test --tags golden --update-goldens
WorkflowTemplateModel _template(String id, {bool enabled = true}) =>
    WorkflowTemplateModel(
      id: id,
      workflowId: 'image-create-$id',
      version: '1',
      displayName: id,
      model: id,
      repository: 'acme/example',
      enabled: enabled,
      disabledReason: enabled ? '' : 'The workflow is not installed on dev.',
    );

/// A catalog entry for one of the shipped image models, so the golden shows the
/// guide each card resolves to rather than the unknown-model fallback.
WorkflowTemplateModel _imageModel(
  String workflowId,
  String model, {
  bool enabled = true,
}) => WorkflowTemplateModel(
  id: workflowId,
  workflowId: workflowId,
  version: '1',
  displayName: model,
  model: model,
  repository: 'acme/example',
  enabled: enabled,
  disabledReason: enabled ? '' : 'The workflow is not installed on dev.',
);

void main() {
  setUpAll(loadIiOsFonts);

  testWidgets('signed-in app title exposes the deployed build', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Align(alignment: Alignment.topLeft, child: IiOsAppTitle()),
        width: 360,
      ),
    );
    await expectLater(
      find.byType(IiOsAppTitle),
      matchesGoldenFile('goldens/ii_os_app_title.png'),
    );
  });

  testWidgets('workspace creation dialog explains the tenant boundary', (
    tester,
  ) async {
    const organization = OrganizationAccess(
      id: 'org-1',
      name: 'Intelligent Iterations',
      role: 'Owner',
      capabilities: {'org.workspaces.create'},
    );
    await tester.pumpWidget(
      goldenHarness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWorkspaceCreationDialog(
              context: context,
              organization: organization,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/workspace_creation_dialog.png'),
    );
  });

  testWidgets('organization data plane names its shared scope', (tester) async {
    final controller = AppController()
      ..connection = const DataPlaneConnectionModel(
        organizationId: '5e30d16c-e97e-4dab-8ac7-61c0b3af0a37',
        projectId: 'acme-media',
        projectNumber: '123456789012',
        databaseId: 'ii-os',
        region: 'us-central1',
        bucket: 'acme-media-artifacts',
        dataServiceAccount: 'broker@acme-media.iam.gserviceaccount.com',
        uploadServiceAccount: 'upload@acme-media.iam.gserviceaccount.com',
        workloadIdentityProvider:
            'projects/123456789012/locations/global/workloadIdentityPools/acme/providers/github',
        authProjectId: 'ii-os-control',
        webOrigin: 'https://os.example.com',
      );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      goldenHarness(DataPlaneStatusPanel(controller: controller), width: 720),
    );
    await expectLater(
      find.byType(DataPlaneStatusPanel),
      matchesGoldenFile('goldens/data_plane_status_organization.png'),
    );
  });

  testWidgets('PageFrame carries an identity glyph beside its title', (
    tester,
  ) async {
    // The sidebar entry and this header are the only two places a production
    // line's colour and icon appear, so the header slot is worth pinning.
    await tester.pumpWidget(
      goldenHarness(
        const PageFrame(
          title: 'Payments',
          subtitle: 'acme/payments · repository-maintainer',
          leading: IiOsIdentityGlyph(
            colorToken: 'violet',
            iconToken: 'creditCard',
            size: IiOsIdentityGlyph.headerSize,
          ),
          child: SizedBox.shrink(),
        ),
        width: 520,
      ),
    );
    await expectLater(
      find.byType(PageFrame),
      matchesGoldenFile('goldens/page_frame_identity.png'),
    );
  });

  testWidgets('KpiCard renders a value and an absent value', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Active jobs',
                value: '12',
                hue: IiOsPalette.light.info,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: KpiCard(
                label: 'Members',
                value: null,
                hue: IiOsPalette.light.accent,
              ),
            ),
          ],
        ),
        width: 420,
      ),
    );
    await expectLater(
      find.byType(Row).first,
      matchesGoldenFile('goldens/kpi_card.png'),
    );
  });

  testWidgets('StatusPill covers the status colour families', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusPill('running'),
            StatusPill('finished'),
            StatusPill('failed'),
            StatusPill('cancelled'),
            StatusPill('needs_review'),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(Wrap).first,
      matchesGoldenFile('goldens/status_pill.png'),
    );
  });

  testWidgets('busy surfaces render loading and refreshing', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LoadingSurface(label: 'Loading storyboards'),
            RefreshingStrip(),
          ],
        ),
        width: 420,
      ),
    );
    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/state_surfaces_busy.png'),
    );
  });

  testWidgets('resolved surfaces render error and empty', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        Column(
          key: const ValueKey('background-work-states'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ErrorSurface(
              title: 'Storyboards could not be loaded',
              message: 'The control API did not respond in time.',
              onRetry: () {},
            ),
            const EmptyState(
              title: 'No storyboards yet',
              message: 'Create one to get started.',
              icon: LucideIcons.panelsTopLeft,
            ),
          ],
        ),
        width: 420,
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('background-work-states')),
      matchesGoldenFile('goldens/state_surfaces_resolved.png'),
    );
  });

  testWidgets('background work separates running from retryable', (
    tester,
  ) async {
    await tester.pumpWidget(
      goldenHarness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BackgroundWorkCard(
              running: true,
              title: 'Installing agent permissions\u2026',
              detail:
                  'The installer is running in your repository. This normally '
                  'takes a few minutes.',
              onFollow: () {},
              followLabel: 'Watch the run',
              onRetry: () {},
              retryLabel: 'Install again',
            ),
            IiOsGap.vSm,
            BackgroundWorkCard(
              running: false,
              title: 'This is taking longer than usual',
              detail:
                  'The run may still finish. Start again only from this '
                  'stopped state.',
              onFollow: () {},
              followLabel: 'Watch the run',
              onRetry: () {},
              retryLabel: 'Install again',
            ),
          ],
        ),
        width: 520,
      ),
    );
    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/background_work_states.png'),
    );
  });

  testWidgets('workshop setup makes current status and next action explicit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const repository = 'acme-co/example-app';
    final readiness = GitHubSetupReadinessModel.fromJson({
      'status': 'action_required',
      'checkedAt': '2026-08-13T12:00:00Z',
      'workspace': {
        'status': 'ready',
        'dispatchAllowed': true,
        'checkedAt': '2026-08-13T12:00:00Z',
        'checks': <Object?>[],
      },
      'repositories': [
        {
          'repository': repository,
          'status': 'action_required',
          'dispatchAllowed': false,
          'checkedAt': '2026-08-13T12:00:00Z',
          'checks': [
            {
              'id': 'github_installation',
              'label': 'GitHub App installation connected',
              'status': 'passed',
              'repository': repository,
            },
            {
              'id': 'repository_selected',
              'label': 'Repository selected',
              'status': 'passed',
              'repository': repository,
            },
            {
              'id': 'github_repository_access',
              'label': 'Repository access',
              'status': 'passed',
              'repository': repository,
            },
            {
              'id': 'github_app_actions',
              'label': 'Actions',
              'status': 'action_required',
              'repository': repository,
              'currentValue': 'No access',
              'requiredValue': 'Read and write',
            },
            {
              'id': 'github_app_contents',
              'label': 'Contents',
              'status': 'action_required',
              'repository': repository,
              'currentValue': 'Read-only',
              'requiredValue': 'Read and write',
            },
            {
              'id': 'github_app_deployments',
              'label': 'Deployments',
              'status': 'warning',
              'repository': repository,
              'currentValue': 'No access',
              'requiredValue': 'Read-only',
            },
            {
              'id': 'github_app_pull_requests',
              'label': 'Pull requests',
              'status': 'action_required',
              'repository': repository,
              'currentValue': 'No access',
              'requiredValue': 'Read and write',
            },
          ],
        },
      ],
      'checks': <Object?>[],
    });
    await tester.pumpWidget(
      goldenHarness(
        SingleChildScrollView(
          child: AgentReadinessCard(
            readiness: readiness,
            repository: repository,
            repositories: const [repository],
            step: 'permissions',
            loading: false,
            error: null,
            actionInProgress: false,
            blockedReason: (_) => null,
            onRepositoryChanged: (_) {},
            onStepChanged: (_) {},
            onAction: (_, _) {},
            onOpenWorkshop: () {},
            onRefresh: () {},
          ),
        ),
        width: 1000,
      ),
    );
    await expectLater(
      find.byType(AgentReadinessCard),
      matchesGoldenFile('goldens/github_setup_progress_action_needed.png'),
    );
    await expectLater(
      find.byType(AgentReadinessCard),
      matchesGoldenFile('goldens/github_setup_header_action_needed.png'),
    );
    await tester.scrollUntilVisible(
      find.text('Recommended: enable deployment verification'),
      500,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AgentReadinessCard),
      matchesGoldenFile('goldens/github_setup_deployment_recommendation.png'),
    );
  });

  testWidgets('model choice, stacked and paired', (tester) async {
    final templates = [
      _imageModel('image-create', 'Z-Image Turbo'),
      _imageModel('image-create-qwen-2512', 'Qwen Image 2512'),
      _imageModel(
        'image-create-flux2-klein',
        'FLUX.2 Klein 4B',
        enabled: false,
      ),
    ];
    Widget subject() => ModelChoice(
      templates: templates,
      selectedId: 'image-create',
      enabled: true,
      onSelected: (_) {},
    );

    await tester.pumpWidget(goldenHarness(subject(), width: 420));
    await expectLater(
      find.byType(ModelChoice),
      matchesGoldenFile('goldens/model_choice.png'),
    );

    await tester.pumpWidget(goldenHarness(subject(), width: 760));
    await expectLater(
      find.byType(ModelChoiceCards),
      matchesGoldenFile('goldens/model_choice_cards.png'),
    );
  });

  testWidgets('workflow unavailable notice, blocked and pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      goldenHarness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkflowUnavailableNotice(
              template: _template('blocked', enabled: false),
              fallbackReason: 'No enabled image workflow is available.',
            ),
            const WorkflowUnavailableNotice(
              template: null,
              fallbackReason: 'Waiting for the workflow to land on dev.',
            ),
          ],
        ),
        width: 420,
      ),
    );
    await expectLater(
      find.byType(Column).first,
      matchesGoldenFile('goldens/workflow_unavailable_notice.png'),
    );
  });

  testWidgets('responsive field pair stacks and sits side by side', (
    tester,
  ) async {
    const pair = ResponsiveFieldPair(
      first: TextField(decoration: InputDecoration(labelText: 'Aspect ratio')),
      second: TextField(decoration: InputDecoration(labelText: 'Seed')),
    );
    await tester.pumpWidget(goldenHarness(pair, width: 600));
    await expectLater(
      find.byType(ResponsiveFieldPair),
      matchesGoldenFile('goldens/responsive_field_pair_wide.png'),
    );

    await tester.pumpWidget(goldenHarness(pair, width: 320));
    await expectLater(
      find.byType(ResponsiveFieldPair),
      matchesGoldenFile('goldens/responsive_field_pair_narrow.png'),
    );
  });

  testWidgets('duration selector', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        DurationSelector(
          value: 15,
          minimum: 2,
          maximum: 20,
          divisions: 18,
          valueFormatter: (value) => '${value.round()} seconds',
          onChanged: (_) {},
        ),
        width: 520,
      ),
    );
    await expectLater(
      find.byType(DurationSelector),
      matchesGoldenFile('goldens/duration_selector.png'),
    );
  });

  testWidgets('prompting guide content', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const PromptingGuideContent(
          summary: 'Plan a short audiovisual timeline, not a keyword list.',
          sections: [
            PromptingGuideSection(
              title: 'Stage the action',
              body: 'Describe what changes between the opening and the end.',
            ),
            PromptingGuideSection(
              title: 'Direct the camera',
              body: 'Name the movement, range, and speed that matter.',
            ),
          ],
          promptTemplate:
              '[Shot 1] Subject, action, camera, and synchronized sound\u2026',
        ),
        width: 600,
      ),
    );
    await expectLater(
      find.byType(PromptingGuideContent),
      matchesGoldenFile('goldens/prompting_guide_content.png'),
    );
  });

  testWidgets('voice clone reference field', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        VoiceCloneReferenceField(
          enabled: true,
          useVoiceClone: true,
          consent: false,
          file: null,
          contentType: null,
          onUseVoiceCloneChanged: (_) {},
          onConsentChanged: (_) {},
          onSelect: () {},
          onClear: () {},
        ),
        width: 520,
      ),
    );
    await expectLater(
      find.byType(VoiceCloneReferenceField),
      matchesGoldenFile('goldens/voice_clone_reference_field.png'),
    );
  });

  testWidgets('image generation form, idle and submitting', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        ImageGenerationForm(
          canSubmit: true,
          submitting: false,
          onSubmit: ({required prompt, required aspectRatio, required seed}) {},
        ),
        width: 560,
      ),
    );
    await expectLater(
      find.byType(ImageGenerationForm),
      matchesGoldenFile('goldens/image_generation_form.png'),
    );
  });

  testWidgets('workspace connection rows', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkspaceConnectionRow(
                icon: LucideIcons.gitFork,
                title: 'Repositories',
                value: '3',
                detail: 'acme/example, acme/site, acme/tools',
              ),
              Divider(),
              WorkspaceConnectionRow(
                icon: LucideIcons.workflow,
                title: 'Workflows',
                value: '0',
                detail: 'No workflows configured',
              ),
            ],
          ),
        ),
        width: 480,
      ),
    );
    await expectLater(
      find.byType(Card).first,
      matchesGoldenFile('goldens/workspace_connection_row.png'),
    );
  });

  testWidgets('GitHub permission setup guide', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        const PermissionChangeGuide(
          steps: ['Open permission settings.', 'Save changes.'],
          changes: [
            PermissionChange(
              name: 'Administration',
              section: 'Repository permissions',
              currentValue: 'No access',
              requiredValue: 'Read-only',
              reason:
                  'Lets ii-os confirm your protections are in place. It can '
                  'read those settings, never change them.',
            ),
            PermissionChange(
              name: 'Pull requests',
              section: 'Repository permissions',
              currentValue: 'Read-only',
              requiredValue: 'Read and write',
              reason:
                  'Lets ii-os open the pull request with the finished work.',
            ),
          ],
        ),
        width: 480,
      ),
    );
    await expectLater(
      find.byType(PermissionChangeGuide),
      matchesGoldenFile('goldens/github_permission_setup_guide.png'),
    );
  });

  testWidgets('DataPlaneTechnicalChecks stays collapsed by default', (
    tester,
  ) async {
    // The disclosure is the only place the validator's own words are allowed
    // to render, so its collapsed state is the contract worth pinning: a theme
    // change that expands it by default puts operator text back on the page.
    await tester.pumpWidget(
      goldenHarness(
        const DataPlaneTechnicalChecks(
          checks: [
            DataPlaneCheckModel(
              id: 'object_crud',
              label: 'GCS object canary',
              status: 'passed',
              detail: 'Wrote and deleted a disposable object.',
            ),
            DataPlaneCheckModel(
              id: 'bucket_admin_denied',
              label: 'Bucket administration denied',
              status: 'action_required',
              detail: 'storage.buckets.update was not denied for the broker.',
            ),
          ],
        ),
        width: 420,
      ),
    );
    await expectLater(
      find.byType(DataPlaneTechnicalChecks),
      matchesGoldenFile('goldens/data_plane_status_technical_checks.png'),
    );
  });

  testWidgets('ArtifactThumbnail shows the well when there is no preview', (
    tester,
  ) async {
    // The state with nothing to fetch is the deterministic one, and it is the
    // one that carries the media well and the palette a theme change moves.
    await tester.pumpWidget(
      goldenHarness(
        const SizedBox(
          height: 180,
          child: ArtifactThumbnail(
            identity: 'job-1:panel.png',
            load: null,
            placeholderIcon: LucideIcons.audioLines,
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(ArtifactThumbnail),
      matchesGoldenFile('goldens/artifact_thumbnail.png'),
    );
  });

  testWidgets('MediaLibraryTile leads with the prompt over the artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      goldenHarness(
        SizedBox(
          height: 200,
          width: 168,
          child: MediaLibraryTile(
            entry: HistoryEntryModel.fromJobArtifact(
              job: const {
                'jobId': 'video-job',
                'repository': 'acme/media',
                'status': 'completed',
                'submittedAt': '2026-08-16T12:00:00Z',
                'generationMetadata': {
                  'model': 'MiniMax H3',
                  'prompt': 'The dancer performs on a rain-glossed rooftop',
                },
              },
              artifact: const {
                'path': 'workspaces/w/runs/video-job/media/dance.mp4',
                'content_type': 'video/mp4',
                'generation': '1',
              },
            ),
            loadPreview: null,
            onPick: (_) {},
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(MediaLibraryTile),
      matchesGoldenFile('goldens/media_library_tile.png'),
    );
  });

  testWidgets('MediaLibraryView lays out tiles as pictures', (tester) async {
    JsonMap job(String id, String prompt) => {
      'jobId': id,
      'repository': 'acme/media',
      'status': 'completed',
      'submittedAt': '2026-08-16T12:00:00Z',
      'generationMetadata': {'model': 'Z-Image', 'prompt': prompt},
      'artifacts': [
        {
          'path': 'workspaces/w/runs/$id/media/$id.png',
          'content_type': 'image/png',
          'generation': '1786900000000000',
        },
      ],
    };
    HistoryEntryModel entry(String id, String prompt) {
      final source = job(id, prompt);
      return HistoryEntryModel.fromJobArtifact(
        job: source,
        artifact: (source['artifacts']! as List).first as JsonMap,
        poster: null,
      );
    }

    await tester.pumpWidget(
      goldenHarness(
        SizedBox(
          height: 420,
          child: MediaLibraryView(
            entries: [
              entry('job-a', 'a rain-glossed rooftop at blue hour'),
              entry('job-b', 'a calm ocean wave at sunset'),
              entry('job-c', 'the dancer, wide shot'),
            ],
            controller: ScrollController(),
            // An image is its own preview, so the loader is called. It never
            // completes here: the state worth pinning is the grid's layout,
            // not whatever bytes happen to arrive.
            loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
            loadingMore: false,
            onPick: (_) {},
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the preview spinner never stops, so nothing settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(MediaLibraryView),
      matchesGoldenFile('goldens/media_library_view.png'),
    );
  });

  testWidgets('MediaUploadPane names what it accepts', (tester) async {
    await tester.pumpWidget(
      goldenHarness(
        SizedBox(
          height: 320,
          child: MediaUploadPane(
            types: const [
              XTypeGroup(label: 'images', extensions: ['png', 'jpg']),
            ],
            onPicked: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MediaUploadPane),
      matchesGoldenFile('goldens/media_upload_pane.png'),
    );
  });

  testWidgets('MediaLibraryBody says which nothing it is showing', (
    tester,
  ) async {
    // An empty library and an unavailable one are different facts, and the
    // grid used to render both as the same silence.
    final history = GenerationHistoryRepository.withLoader(
      workspaceId: 'w',
      retentionDays: 30,
      loader: (_) async => {'jobs': <JsonMap>[], 'hasMore': false},
    );
    await tester.pumpWidget(
      goldenHarness(
        SizedBox(
          height: 300,
          child: MediaLibraryBody(
            history: history,
            entries: const [],
            kindLabel: 'Videos',
            loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
            scroll: ScrollController(),
            onPick: (_) {},
            onLoadMore: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MediaLibraryBody),
      matchesGoldenFile('goldens/media_library_body_empty.png'),
    );
  });

  testWidgets('the media picker offers both sources from one sheet', (
    tester,
  ) async {
    final history = GenerationHistoryRepository.withLoader(
      workspaceId: 'w',
      retentionDays: 30,
      loader: (_) async => {'jobs': <JsonMap>[], 'hasMore': false},
    );
    await tester.pumpWidget(
      goldenHarness(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showMediaPicker(
              context: context,
              history: history,
              loadPreview: (_) => Completer<VerifiedArtifactMedia>().future,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MediaLibraryGrid),
      matchesGoldenFile('goldens/media_picker_library.png'),
    );
  });
}
