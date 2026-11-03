import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ii_os/navigation/app_route_state.dart';
import 'package:ii_os/navigation/app_router.dart';

void main() {
  test('a generated asset keeps its address through a round trip', () {
    // The run identifies the asset; the object name disambiguates a run that
    // produced more than one. Both have to survive being turned into a URL and
    // read back, or a shared link lands on the wrong thing.
    const route = AppRouteState(
      workspaceId: 'workspace-1',
      page: AppPage.history,
      itemId: 'job-42',
      query: {'object': 'workspaces/w/runs/job-42/video/clip.mp4'},
    );
    final parsed = AppRouteState.fromUri(Uri.parse(route.location));

    expect(parsed.page, AppPage.history);
    expect(parsed.itemId, 'job-42');
    expect(parsed.query['object'], 'workspaces/w/runs/job-42/video/clip.mp4');
  });

  test('history without an item is still the history page', () {
    final parsed = AppRouteState.fromUri(
      Uri.parse('/workspaces/workspace-1/history'),
    );
    expect(parsed.page, AppPage.history);
    expect(parsed.itemId, isNull);
    expect(parsed.query.containsKey('object'), isFalse);
  });

  test('an object name that could escape its prefix is refused', () {
    // The object rides in the URL, so it is attacker-controlled input.
    final parsed = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/workspace-1/history/job-42?object=../../etc/passwd',
      ),
    );
    expect(parsed.itemId, 'job-42');
    expect(parsed.query.containsKey('object'), isFalse);
  });

  test(
    'canonical route retains workspace, resource, and bounded view state',
    () {
      final route = AppRouteState.fromUri(
        Uri.parse(
          '/workspaces/workspace-1/characters/character-7'
          '?tab=body&token=must-not-survive',
        ),
      );

      expect(route.workspaceId, 'workspace-1');
      expect(route.page, AppPage.characters);
      expect(route.itemId, 'character-7');
      expect(route.query, {'tab': 'body'});
      expect(
        route.location,
        '/workspaces/workspace-1/characters/character-7?tab=body',
      );
    },
  );

  test('route values are encoded and unsupported state is discarded', () {
    const route = AppRouteState(
      workspaceId: 'workspace one',
      page: AppPage.storyboards,
      itemId: 'story/7',
      query: {'panel': 'panel one', 'prompt': 'private draft'},
    );

    expect(
      route.location,
      '/workspaces/workspace%20one/storyboards/story%2F7?panel=panel+one',
    );
    expect(
      AppRouteState.fromUri(Uri.parse('/workspaces/w/home?tab=body')).location,
      '/workspaces/w/home',
    );
  });

  test('storyboard animation and scenes have bounded canonical URLs', () {
    final animation = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/w/storyboards/story-1?panel=panel-2&view=animate&prompt=private',
      ),
    );

    expect(animation.query, {'panel': 'panel-2', 'view': 'animate'});
    expect(
      animation.location,
      '/workspaces/w/storyboards/story-1?panel=panel-2&view=animate',
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/storyboards/story-1?view=scenes'),
      ).query,
      {'view': 'scenes'},
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/storyboards/story-1?view=unknown'),
      ).query,
      isEmpty,
    );
  });

  test('software workshop links preserve only durable ticket state', () {
    final route = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/w/tickets?repository=org%2Frepo&project=project-7'
        '&filter=attention&ticket=item-42&draft=private',
      ),
    );

    expect(route.query, {
      'repository': 'org/repo',
      'project': 'project-7',
      'filter': 'attention',
      'ticket': 'item-42',
    });
    expect(
      route.location,
      '/workspaces/w/tickets?repository=org%2Frepo&project=project-7'
      '&filter=attention&ticket=item-42',
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/tickets?filter=unknown&prompt=private'),
      ).query,
      isEmpty,
    );
  });

  test('software workshop rooms have durable sub-page links', () {
    final route = AppRouteState.fromUri(
      Uri.parse('/workspaces/w/tickets/mobile?repository=org%2Fapp'),
    );

    expect(route.page, AppPage.tickets);
    expect(route.itemId, 'mobile');
    expect(route.location, '/workspaces/w/tickets/mobile?repository=org%2Fapp');
  });

  test('image reference mode and model round-trip through the URL', () {
    final route = AppRouteState.fromUri(
      Uri.parse('/workspaces/w/images?mode=references&model=qwen-reference'),
    );

    expect(route.page, AppPage.generate);
    expect(route.query, {'mode': 'references', 'model': 'qwen-reference'});
    expect(
      route.location,
      '/workspaces/w/images?mode=references&model=qwen-reference',
    );
  });

  test('legacy GitHub setup URL remains directly addressable', () {
    final route = AppRouteState.fromUri(Uri.parse('/github/setup'));

    expect(route.page, AppPage.githubSetup);
    expect(route.workspaceId, isNull);
    expect(route.location, '/github/setup');
  });

  test('every retired creative tab resolves to the page it became', () {
    // `/creative` was a tab shell. Each tool is its own page now, so a link
    // someone shared or bookmarked has to land on that page rather than on a
    // dead route or silently on Home.
    for (final (tool, page, location) in const <(String, AppPage, String)>[
      ('images', AppPage.generate, '/workspaces/workspace-1/images'),
      ('image-edit', AppPage.imageEdit, '/workspaces/workspace-1/image-edit'),
      (
        'video',
        AppPage.videoGeneration,
        '/workspaces/workspace-1/video-generation',
      ),
      (
        'video-editor',
        AppPage.videoEditor,
        '/workspaces/workspace-1/video-editor',
      ),
      ('music', AppPage.songGeneration, '/workspaces/workspace-1/songs'),
      ('narration', AppPage.narration, '/workspaces/workspace-1/narration'),
    ]) {
      final route = AppRouteState.fromUri(
        Uri.parse('/workspaces/workspace-1/creative?tool=$tool'),
      );
      expect(route.page, page, reason: tool);
      expect(route.location, location, reason: tool);
    }
  });

  test('a retired creative link with no usable tool lands on Images', () {
    for (final suffix in const ['', '?tool=unknown', '?tool=&prompt=private']) {
      expect(
        AppRouteState.fromUri(
          Uri.parse('/workspaces/workspace-1/creative$suffix'),
        ).location,
        '/workspaces/workspace-1/images',
        reason: suffix,
      );
    }
  });

  test('video editor H3 handoff keeps only a bounded source reference', () {
    final route = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/workspace-1/video-generation?mode=video_continue'
        '&source=33449737-9e39-4d53-8040-f39d5f7bc3ce'
        '&prompt=private&url=https%3A%2F%2Fevil.example',
      ),
    );

    expect(route.query, {
      'mode': 'video_continue',
      'source': '33449737-9e39-4d53-8040-f39d5f7bc3ce',
    });
    expect(route.location, isNot(contains('prompt')));
    expect(
      AppRouteState.fromUri(
        Uri.parse(
          '/workspaces/w/video-generation?mode=video_edit&source=../asset',
        ),
      ).query,
      {'mode': 'video_edit'},
    );
  });

  test('agent usage keeps only bounded time and origin filters', () {
    final route = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/workspace-1/agent-usage?days=90&origin=cloud&model=private',
      ),
    );

    expect(route.page, AppPage.agentUsage);
    expect(route.query, {'days': '90', 'origin': 'cloud'});
    expect(
      route.location,
      '/workspaces/workspace-1/agent-usage?days=90&origin=cloud',
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/workspace-1/agent-usage?days=365&origin=host'),
      ).query,
      isEmpty,
    );
  });

  test('GitHub setup URL preserves repository and bounded wizard step', () {
    final route = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/w/github-setup?repository=acme-co%2Fexample-app&step=agent&token=private',
      ),
    );

    expect(route.query, {'repository': 'acme-co/example-app', 'step': 'agent'});
    expect(
      route.location,
      '/workspaces/w/github-setup?repository=acme-co%2Fexample-app&step=agent',
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/github-setup?step=unknown&token=private'),
      ).query,
      isEmpty,
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/github-setup?step=complete'),
      ).query,
      {'step': 'complete'},
    );
  });

  test('onboarding handoffs retain a bounded return path', () {
    final admin = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/w/project-admin?from=setup&repository=acme-co%2Fexample-app&return=https%3A%2F%2Fevil.example',
      ),
    );
    final permissions = AppRouteState.fromUri(
      Uri.parse(
        '/workspaces/w/agent-permissions?from=setup&repository=acme-co%2Fexample-app&ref=dev&token=private',
      ),
    );

    expect(admin.query, {'from': 'setup', 'repository': 'acme-co/example-app'});
    expect(permissions.query, {
      'repository': 'acme-co/example-app',
      'ref': 'dev',
      'from': 'setup',
    });
  });

  test('every application page has a canonical workspace URL', () {
    for (final page in AppPage.values) {
      final location = AppRouteState(
        workspaceId: 'workspace-1',
        page: page,
      ).location;

      expect(
        AppRouteState.fromUri(Uri.parse(location)).page,
        page,
        reason: location,
      );
    }
  });

  test('invalid and private query state is removed from shared URLs', () {
    expect(
      AppRouteState.fromUri(
        Uri.parse(
          '/workspaces/w/image-edit?mode=revision&token=secret&prompt=draft',
        ),
      ).location,
      '/workspaces/w/image-edit',
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/characters/c?tab=unknown&panel=p'),
      ).location,
      '/workspaces/w/characters/c',
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/characters/c?tab=head'),
      ).location,
      '/workspaces/w/characters/c',
    );
    expect(
      AppRouteState.fromUri(
        Uri.parse('/workspaces/w/agent-permissions?ref=../main&token=secret'),
      ).location,
      '/workspaces/w/agent-permissions',
    );
  });

  testWidgets(
    'direct links restore state and navigation preserves shell state',
    (tester) async {
      final router = createAppRouter(
        initialLocation:
            '/workspaces/workspace-1/characters/character-7?tab=body',
        builder: (context, route) => _RouteHarness(route: route),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('characters:character-7:body'), findsOneWidget);
      await tester.tap(find.text('Increment'));
      await tester.tap(find.text('Open tickets'));
      await tester.pumpAndSettle();

      expect(find.text('tickets:none:none'), findsOneWidget);
      expect(find.text('Count 1'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/workspaces/workspace-1/tickets?repository=org%2Frepo',
      );
    },
  );

  testWidgets('panel query replacement preserves unsaved editor state', (
    tester,
  ) async {
    final router = createAppRouter(
      initialLocation:
          '/workspaces/workspace-1/storyboards/story-1?panel=panel-1',
      builder: (context, route) => _PanelRouteHarness(route: route),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Unsaved scene prompt');
    await tester.tap(find.text('Select panel 2'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved scene prompt'), findsOneWidget);
    expect(find.text('Selected panel-2'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/workspaces/workspace-1/storyboards/story-1?panel=panel-2',
    );
    expect(tester.takeException(), isNull);
  });
}

class _PanelRouteHarness extends StatefulWidget {
  const _PanelRouteHarness({required this.route});

  final AppRouteState route;

  @override
  State<_PanelRouteHarness> createState() => _PanelRouteHarnessState();
}

class _PanelRouteHarnessState extends State<_PanelRouteHarness> {
  final _prompt = TextEditingController();

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('Selected ${widget.route.query['panel']}'),
          TextField(controller: _prompt),
          TextButton(
            onPressed: () => context.replace(
              widget.route.withQuery({'panel': 'panel-2'}).location,
            ),
            child: const Text('Select panel 2'),
          ),
        ],
      ),
    );
  }
}

class _RouteHarness extends StatefulWidget {
  const _RouteHarness({required this.route});

  final AppRouteState route;

  @override
  State<_RouteHarness> createState() => _RouteHarnessState();
}

class _RouteHarnessState extends State<_RouteHarness> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text(
            '${widget.route.page.slug}:${widget.route.itemId ?? 'none'}:'
            '${widget.route.query['tab'] ?? 'none'}',
          ),
          Text('Count $_count'),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: const Text('Increment'),
          ),
          TextButton(
            onPressed: () => context.go(
              const AppRouteState(
                workspaceId: 'workspace-1',
                page: AppPage.tickets,
                query: {'repository': 'org/repo'},
              ).location,
            ),
            child: const Text('Open tickets'),
          ),
        ],
      ),
    );
  }
}
