import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/runtime_estimate.dart';
import 'package:ii_os/models/storyboard.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/common.dart';
import 'package:ii_os/widgets/storyboard_editor_components.dart';
import 'package:ii_os/widgets/storyboard_panel_grid.dart';
import 'package:ii_os/widgets/storyboard_panel_image_picker.dart';

void main() {
  test('completed storyboard panel exposes its image artifact', () {
    final storyboard = StoryboardModel.fromJson({
      'id': 'storyboard-1',
      'name': 'Flooded city',
      'overview': 'A courier races through a flooded city.',
      'panels': [
        {
          'id': 'panel-1',
          'prompt': 'The courier reaches the station.',
          'characterIds': ['mara'],
          'referencePanelIds': ['panel-2'],
          'jobId': 'job-1',
          'job': {
            'status': 'completed',
            'artifacts': [
              {
                'path': 'workspaces/w/runs/job-1/image/panel.png',
                'generation': '42',
                'content_type': 'image/png',
              },
            ],
          },
        },
      ],
      'createdAt': '2026-07-16T20:00:00Z',
      'updatedAt': '2026-07-16T20:05:00Z',
    });

    expect(storyboard.panels.single.status, 'completed');
    expect(storyboard.panels.single.imageArtifact?['generation'], '42');
    expect(storyboard.panels.single.generationJobIds, ['job-1']);
    expect(storyboard.panels.single.referencePanelIds, {'panel-2'});
  });

  test('selected historical panel image overrides the latest generation', () {
    final panel = StoryboardPanelModel.fromJson({
      'id': 'panel-1',
      'jobId': 'job-new',
      'generationJobIds': ['job-old', 'job-new'],
      'selectedImage': {
        'jobId': 'job-old',
        'path': 'workspaces/w/runs/job-old/image/panel.png',
        'generation': '41',
        'content_type': 'image/png',
      },
      'job': {
        'status': 'completed',
        'artifacts': [
          {
            'path': 'workspaces/w/runs/job-new/image/panel.png',
            'generation': '42',
            'content_type': 'image/png',
          },
        ],
      },
    });

    expect(panel.imageJobId, 'job-old');
    expect(panel.imageArtifact?['generation'], '41');
    expect(panel.generationJobIds, ['job-old', 'job-new']);
  });

  test('legacy storyboard selection uses verified metadata from its job', () {
    final sha256 = List.filled(64, 'a').join();
    final panel = StoryboardPanelModel.fromJson({
      'id': 'panel-1',
      'jobId': 'job-new',
      'selectedImage': {
        'jobId': 'job-old',
        'path': 'workspaces/w/runs/job-old/image/panel.png',
        'generation': '41',
        'content_type': 'image/png',
      },
      'job': {'status': 'completed', 'artifacts': <Object?>[]},
      'selectedImageJob': {
        'status': 'completed',
        'artifacts': [
          {
            'path': 'workspaces/w/runs/job-old/image/panel.png',
            'generation': '41',
            'size_bytes': 1024,
            'sha256': sha256,
            'content_type': 'image/png',
          },
        ],
      },
    });

    expect(panel.imageArtifact?['size_bytes'], 1024);
    expect(panel.imageArtifact?['sha256'], sha256);

    final draft = StoryboardPanelDraft.fromModel(panel);
    addTearDown(draft.dispose);
    expect(draft.imageArtifact?['size_bytes'], 1024);
    expect(draft.imageArtifact?['sha256'], sha256);
  });

  test('panel history preserves the complete verified media identity', () {
    final sha256 = List.filled(64, 'b').join();
    final image = StoryboardPanelImageModel.fromJson({
      'jobId': 'job-old',
      'path': 'workspaces/w/runs/job-old/image/panel.png',
      'generation': '41',
      'content_type': 'image/png',
      'size_bytes': 2048,
      'sha256': sha256,
      'selected': false,
      'createdAt': '2026-07-30T12:00:00Z',
    });

    expect(image.sizeBytes, 2048);
    expect(image.sha256, sha256);
    expect(image.artifact['size_bytes'], 2048);
    expect(image.artifact['sha256'], sha256);
  });

  test('an active new generation temporarily replaces the old selection', () {
    final panel = StoryboardPanelModel.fromJson({
      'id': 'panel-1',
      'jobId': 'job-new',
      'generationJobIds': ['job-old', 'job-new'],
      'selectedImage': {
        'jobId': 'job-old',
        'path': 'workspaces/w/runs/job-old/image/panel.png',
        'generation': '41',
        'content_type': 'image/png',
      },
      'job': {'status': 'running', 'artifacts': <Object?>[]},
    });

    expect(panel.imageJobId, 'job-new');
    expect(panel.imageArtifact, isNull);
    expect(isActiveStoryboardJobStatus(panel.status), isTrue);
  });

  test('generator trace prefers the final prompt sent in job inputs', () {
    final panel = StoryboardPanelModel.fromJson({
      'id': 'panel-1',
      'generationPrompt': 'Original panel prompt.',
      'job': {
        'generationMetadata': {'prompt': 'Enhanced cinematic panel prompt.'},
        'inputs': {
          'prompt':
              'Enhanced cinematic panel prompt.\n\n'
              'Image 2 refers to "Jenny".',
        },
      },
    });

    expect(
      panel.promptSentToGenerator,
      'Enhanced cinematic panel prompt.\n\n'
      'Image 2 refers to "Jenny".',
    );
    expect(storyboardPromptSentToGenerator(job: null), isNull);
  });

  test('historical selection uses its own final generator prompt', () {
    final panel = StoryboardPanelModel.fromJson({
      'id': 'panel-1',
      'jobId': 'job-new',
      'generationJobIds': ['job-old', 'job-new'],
      'selectedImage': {
        'jobId': 'job-old',
        'path': 'workspaces/w/runs/job-old/image/panel.png',
        'generation': '41',
        'content_type': 'image/png',
      },
      'job': {
        'status': 'completed',
        'inputs': {'prompt': 'New generation prompt.'},
      },
      'selectedImageJob': {
        'status': 'completed',
        'inputs': {'prompt': 'Historical generation prompt.'},
      },
    });

    expect(panel.imageJobId, 'job-old');
    expect(panel.promptSentToGenerator, 'Historical generation prompt.');
    expect(panel.promptSentToGenerator, isNot('New generation prompt.'));
  });

  test('generator trace never substitutes the pre-enhancement snapshot', () {
    final panel = StoryboardPanelModel.fromJson({
      'id': 'panel-1',
      'generationPrompt': 'Original panel prompt.',
      'job': {'status': 'completed'},
    });

    expect(panel.promptSentToGenerator, isNull);
  });

  test('animated storyboard panel exposes its persisted video cut state', () {
    final storyboard = StoryboardModel.fromJson({
      'id': 'storyboard-1',
      'name': 'Flooded city',
      'overview': '',
      'panels': [
        {
          'id': 'panel-1',
          'prompt': 'The courier reaches the station.',
          'characterIds': <String>[],
          'videoJobId': 'video-job-1',
          'videoGenerationPrompt': 'Camera tracks beside the courier.',
          'videoDurationSeconds': 8,
          'videoJob': {
            'status': 'completed',
            'artifacts': [
              {
                'path': 'workspaces/w/runs/video-job-1/video/scene.mp4',
                'generation': '7',
                'content_type': 'video/mp4',
              },
            ],
          },
        },
      ],
    });
    final panel = storyboard.panels.single;

    expect(panel.motionPrompt, 'Camera tracks beside the courier.');
    expect(panel.videoDurationSeconds, 8);
    expect(panel.videoStatus, 'completed');
    expect(panel.videoArtifact?['path'], contains('scene.mp4'));
  });

  testWidgets('workflow pending notice is presented as loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: const Scaffold(
          body: WorkflowPendingNotice(
            message: 'Waiting for a pinned image model pack.',
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.error), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prompt trace shows the final post-enhancement job prompt', (
    tester,
  ) async {
    final panel = StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'Original scene prompt.',
      characterIds: const {},
      jobId: 'job-1',
      generationPrompt: 'Pre-enhancement snapshot.',
      job: const {
        'status': 'completed',
        'artifacts': [
          {
            'path': 'workspaces/w/runs/job-1/image/panel.png',
            'content_type': 'image/png',
          },
        ],
        'generationMetadata': {
          'prompt': 'Enhanced cinematic prompt before reference mapping.',
        },
        'inputs': {
          'prompt':
              'Enhanced cinematic prompt sent to the generator.\n\n'
              'Image 2 refers to "Jenny".',
        },
      },
    );
    addTearDown(panel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoryboardPanelEditor(
              panel: panel,
              panelNumber: 1,
              characters: const [],
              panelReferences: const [],
              loadingCharacters: false,
              enabled: true,
              generating: false,
              canGenerate: true,
              onChanged: () {},
              onGenerate: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Prompt sent to generator'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Enhanced cinematic prompt sent to the generator.\n\n'
        'Image 2 refers to "Jenny".',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Enhanced cinematic prompt before reference mapping.'),
      findsNothing,
    );
    expect(find.text('Pre-enhancement snapshot.'), findsNothing);
  });

  testWidgets('panel editor shows its selected workflow estimate', (
    tester,
  ) async {
    final panel = StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'A quiet station at dawn.',
      characterIds: const {},
    );
    addTearDown(panel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoryboardPanelEditor(
              panel: panel,
              panelNumber: 1,
              characters: const [],
              panelReferences: const [],
              loadingCharacters: false,
              enabled: true,
              generating: false,
              canGenerate: true,
              runtimeEstimate: const RuntimeEstimateSnapshot(
                estimatedSeconds: 30,
                hardware: '24 GB GPU',
                measuredAt: '2026-08-22',
                baselineOutputSeconds: 0,
                baselineRuntimeSeconds: 30,
                selectedInputs: {},
              ),
              onChanged: () {},
              onGenerate: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('About 1 minute'), findsOneWidget);
  });

  testWidgets('prompt trace follows a selected historical generation', (
    tester,
  ) async {
    final panel = StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'Current scene prompt.',
      characterIds: const {},
      jobId: 'job-new',
      generationJobIds: const ['job-old', 'job-new'],
      selectedImage: const {
        'jobId': 'job-old',
        'path': 'workspaces/w/runs/job-old/image/panel.png',
        'generation': '41',
        'content_type': 'image/png',
      },
      job: const {
        'status': 'completed',
        'inputs': {'prompt': 'New generation prompt.'},
      },
      selectedImageJob: const {
        'status': 'completed',
        'inputs': {'prompt': 'Historical generation prompt.'},
      },
    );
    addTearDown(panel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoryboardPanelEditor(
              panel: panel,
              panelNumber: 1,
              characters: const [],
              panelReferences: const [],
              loadingCharacters: false,
              enabled: true,
              generating: false,
              canGenerate: true,
              onChanged: () {},
              onGenerate: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Job job-old'), findsOneWidget);
    await tester.tap(find.text('Prompt sent to generator'));
    await tester.pumpAndSettle();
    expect(find.text('Historical generation prompt.'), findsOneWidget);
    expect(find.text('New generation prompt.'), findsNothing);
  });

  testWidgets('prompt trace waits for the generated image', (tester) async {
    final panel = StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'Original scene prompt.',
      characterIds: const {},
      jobId: 'job-1',
      generationPrompt: 'Pre-enhancement snapshot.',
      job: const {
        'status': 'running',
        'inputs': {'prompt': 'Enhanced cinematic prompt.'},
      },
    );
    addTearDown(panel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: StoryboardPanelEditor(
            panel: panel,
            panelNumber: 1,
            characters: const [],
            panelReferences: const [],
            loadingCharacters: false,
            enabled: true,
            generating: false,
            canGenerate: true,
            onChanged: () {},
            onGenerate: () {},
          ),
        ),
      ),
    );

    expect(find.text('Prompt sent to generator'), findsNothing);
    expect(find.text('Enhanced cinematic prompt.'), findsNothing);
  });

  testWidgets('storyboard panel workspace fits mobile and desktop widths', (
    tester,
  ) async {
    final controller = AppController();
    final overview = TextEditingController(text: 'A courier crosses a city.');
    final panels = List.generate(
      3,
      (index) => StoryboardPanelDraft(
        id: 'panel-$index',
        prompt: 'Scene ${index + 1}',
        characterIds: const {},
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(overview.dispose);
    addTearDown(() {
      for (final panel in panels) {
        panel.dispose();
      }
    });

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  StoryboardOverviewField(
                    controller: overview,
                    enabled: true,
                    onChanged: () {},
                  ),
                  const SizedBox(height: 16),
                  StoryboardPanelGrid(
                    controller: controller,
                    workspaceId: 'workspace-1',
                    panels: panels,
                    selected: 0,
                    generatingPanelId: null,
                    canAnimateSelected: false,
                    onSelect: (_) {},
                    onAnimateSelected: () {},
                  ),
                  const SizedBox(height: 16),
                  StoryboardPanelEditor(
                    panel: panels.first,
                    panelNumber: 1,
                    characters: const [],
                    panelReferences: const [],
                    loadingCharacters: false,
                    enabled: true,
                    generating: false,
                    canGenerate: true,
                    onChanged: () {},
                    onGenerate: () {},
                    imagePicker: StoryboardPanelImagePicker(
                      controller: controller,
                      storyboardId: 'storyboard-1',
                      panel: panels.first,
                      generating: false,
                      canSelect: true,
                      onBeforeSelect: () async => true,
                      onStoryboardChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Panel 1'), findsWidgets);
      expect(find.text('Panel image history'), findsOneWidget);
      expect(find.text('0/150 words'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
