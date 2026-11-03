import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/screens/storyboard_panel_animation_screen.dart';
import 'package:ii_os/screens/storyboard_scenes_screen.dart';
import 'package:ii_os/state/app_controller.dart';
import 'package:ii_os/theme/ii_os_theme.dart';
import 'package:ii_os/widgets/storyboard_editor_components.dart';
import 'package:ii_os/widgets/storyboard_panel_grid.dart';

void main() {
  test('watch cut follows the current storyboard panel order', () {
    final first = _animatedPanel('panel-1');
    final draft = StoryboardPanelDraft(
      id: 'panel-2',
      prompt: 'Not animated yet.',
      characterIds: const {},
    );
    final third = _animatedPanel('panel-3');
    addTearDown(first.dispose);
    addTearDown(draft.dispose);
    addTearDown(third.dispose);

    final ready = animatedStoryboardPanelsInOrder([third, draft, first]);

    expect(ready.map((panel) => panel.id), ['panel-3', 'panel-1']);
  });

  testWidgets('view scenes does not poll when every job is terminal', (
    tester,
  ) async {
    final controller = _controller();
    final panel = StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'Nothing is generating.',
      characterIds: const {},
    );
    var refreshes = 0;
    addTearDown(controller.dispose);
    addTearDown(panel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: StoryboardScenesScreen(
          controller: controller,
          panels: [panel],
          storyboardName: 'Quiet storyboard',
          onBack: () {},
          onRefresh: () async => refreshes++,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(
      refreshes,
      0,
      reason: 'an idle scenes page must not reread storyboard job documents',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('view scenes polls only while a video job is active', (
    tester,
  ) async {
    final controller = _controller();
    final panel = StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'The active scene is still rendering.',
      characterIds: const {},
      videoJobId: 'video-panel-1',
      videoJob: const {'status': 'running'},
    );
    var refreshes = 0;
    addTearDown(controller.dispose);
    addTearDown(panel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: StoryboardScenesScreen(
          controller: controller,
          panels: [panel],
          storyboardName: 'Active storyboard',
          onBack: () {},
          onRefresh: () async => refreshes++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2100));

    expect(refreshes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('panel animation prompt fits mobile and desktop viewports', (
    tester,
  ) async {
    final controller = _controller();
    final panel = StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'A courier reaches the station.',
      characterIds: const {},
    );
    addTearDown(controller.dispose);
    addTearDown(panel.dispose);

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: IiOsTheme.light(),
          home: Scaffold(
            body: StoryboardPanelAnimationScreen(
              controller: controller,
              storyboardId: 'storyboard-1',
              panel: panel,
              panelNumber: 1,
              templates: const [_videoTemplate],
              loadingTemplates: false,
              canEdit: true,
              onBack: () {},
              onViewScenes: () {},
              onStoryboardChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Animate panel 1'), findsWidgets);
      expect(find.text('Motion prompt'), findsOneWidget);
      expect(find.text('View scenes'), findsOneWidget);
      expect(find.textContaining('About 2 minutes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('animate action sits on only the selected panel on mobile', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _SelectablePanelGrid(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Animate panel'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('storyboard-panel-panel-1')),
        matching: find.text('Animate panel'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Panel 2'));
    await tester.pump();

    expect(find.text('Animate panel'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('storyboard-panel-panel-2')),
        matching: find.text('Animate panel'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('panels require a one-second hold before reordering', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: IiOsTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _SelectablePanelGrid(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    final first = find.byKey(const ValueKey('storyboard-panel-panel-1'));
    final second = find.byKey(const ValueKey('storyboard-panel-panel-2'));
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(
      storyboardPanelReorderDelay - const Duration(milliseconds: 1),
    );
    expect(find.text('Panel 1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    expect(find.text('Panel 1'), findsNWidgets(2));

    final secondRect = tester.getRect(second);
    await gesture.moveTo(Offset(secondRect.center.dx, secondRect.bottom - 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: second, matching: find.text('Panel 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('Panel 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('Animate panel')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

StoryboardPanelDraft _animatedPanel(String id) => StoryboardPanelDraft(
  id: id,
  prompt: 'Animated scene $id.',
  characterIds: const {},
  videoJobId: 'video-$id',
  videoJob: {
    'status': 'completed',
    'artifacts': [
      {
        'path': 'workspaces/workspace-1/runs/video-$id/scene.mp4',
        'generation': '1',
        'content_type': 'video/mp4',
      },
    ],
  },
);

class _SelectablePanelGrid extends StatefulWidget {
  const _SelectablePanelGrid({required this.controller});

  final AppController controller;

  @override
  State<_SelectablePanelGrid> createState() => _SelectablePanelGridState();
}

class _SelectablePanelGridState extends State<_SelectablePanelGrid> {
  late final List<StoryboardPanelDraft> _panels = [
    StoryboardPanelDraft(
      id: 'panel-1',
      prompt: 'A courier reaches the station.',
      characterIds: const {},
    ),
    StoryboardPanelDraft(
      id: 'panel-2',
      prompt: 'The train pulls away.',
      characterIds: const {},
    ),
  ];
  var _selected = 0;

  @override
  void dispose() {
    for (final panel in _panels) {
      panel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoryboardPanelGrid(
      controller: widget.controller,
      workspaceId: 'workspace-1',
      panels: _panels,
      selected: _selected,
      generatingPanelId: null,
      canAnimateSelected: true,
      onSelect: (index) => setState(() => _selected = index),
      onAnimateSelected: () {},
      onReorder: _reorder,
    );
  }

  void _reorder(int oldIndex, int destinationIndex) {
    var newIndex = destinationIndex.clamp(0, _panels.length);
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;
    final selectedId = _panels[_selected].id;
    setState(() {
      final panel = _panels.removeAt(oldIndex);
      _panels.insert(newIndex, panel);
      _selected = _panels.indexWhere((panel) => panel.id == selectedId);
    });
  }
}

AppController _controller() =>
    AppController()
      ..selectedAccess = const WorkspaceAccess(
        workspace: WorkspaceModel(
          id: 'workspace-1',
          name: 'Example workspace',
          environment: 'dev',
          githubInstallationId: null,
          repositories: [],
          projects: [],
          workflows: [],
          artifactStorage: null,
        ),
        membership: MembershipModel(
          workspaceId: 'workspace-1',
          uid: 'user-1',
          email: 'user@example.com',
          role: 'owner',
          roleLabel: 'Owner',
          featureClaims: {},
          capabilities: {'jobs.read', 'jobs.trigger'},
        ),
      );

const _videoTemplate = WorkflowTemplateModel(
  id: 'video',
  workflowId: 'image-to-video',
  version: '1',
  displayName: 'Image to video',
  model: 'Video model',
  repository: 'acme/media',
  enabled: true,
  disabledReason: '',
  runtimeEstimates: [
    WorkflowRuntimeEstimateModel(
      selector: {},
      durationInput: 'duration_seconds',
      baselineOutputSeconds: 5,
      baselineRuntimeSeconds: 113,
      hardware: '24 GB GPU',
      measuredAt: '2026-08-06',
    ),
  ],
);
