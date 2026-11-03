enum AppPage {
  home('home'),
  githubSetup('github-setup'),
  projectAdmin('project-admin'),
  workspaceResources('workspace-resources'),
  organizationResources('organization-resources'),
  tickets('tickets'),
  productionLine('production-line'),
  agentPermissions('agent-permissions'),
  agentUsage('agent-usage'),
  playground('playground'),
  characters('characters'),
  storyboards('storyboards'),
  generate('images'),
  imageEdit('image-edit'),
  videoGeneration('video-generation'),
  videoEditor('video-editor'),
  songGeneration('songs'),
  narration('narration'),
  history('history'),
  jobs('jobs'),
  terminalSessions('terminal-sessions'),
  people('people'),
  fleet('infrastructure');

  const AppPage(this.slug);

  final String slug;

  static AppPage? fromSlug(String value) {
    for (final page in values) {
      if (page.slug == value) return page;
    }
    return null;
  }
}

final class AppRouteState {
  const AppRouteState({
    this.workspaceId,
    this.page = AppPage.home,
    this.itemId,
    this.query = const {},
  });

  factory AppRouteState.fromUri(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length == 2 &&
        segments[0] == 'github' &&
        segments[1] == 'setup') {
      return const AppRouteState(page: AppPage.githubSetup);
    }
    if (segments.length < 2 || segments.first != 'workspaces') {
      return const AppRouteState();
    }
    final workspaceId = segments[1].trim();
    if (segments.length >= 3 && segments[2] == _retiredCreativeSlug) {
      // `/creative` was a tab shell holding six tools. Each tool is now its
      // own page, so the retired location maps onto the page it became. The
      // router redirects to `location`, so existing links, bookmarks, and
      // history entries resolve to the new URL instead of breaking.
      return AppRouteState(
        workspaceId: workspaceId.isEmpty ? null : workspaceId,
        page: _creativeToolPage(uri.queryParameters['tool']),
      );
    }
    final page = segments.length >= 3
        ? AppPage.fromSlug(segments[2]) ?? AppPage.home
        : AppPage.home;
    final itemId = segments.length >= 4 && _supportsItem(page)
        ? segments[3].trim()
        : null;
    return AppRouteState(
      workspaceId: workspaceId.isEmpty ? null : workspaceId,
      page: page,
      itemId: itemId?.isEmpty == true ? null : itemId,
      query: _routeQuery(page, itemId, uri.queryParameters),
    );
  }

  final String? workspaceId;
  final AppPage page;
  final String? itemId;
  final Map<String, String> query;

  String get location {
    final workspace = workspaceId;
    if (workspace == null || workspace.isEmpty) {
      return page == AppPage.githubSetup ? '/github/setup' : '/';
    }
    final segments = <String>['workspaces', workspace, page.slug];
    final item = itemId;
    if (item != null && item.isNotEmpty && _supportsItem(page)) {
      segments.add(item);
    }
    return Uri(
      pathSegments: ['', ...segments],
      queryParameters: query.isEmpty ? null : _routeQuery(page, item, query),
    ).toString();
  }

  AppRouteState withWorkspace(String? value) => AppRouteState(
    workspaceId: value,
    page: page,
    itemId: itemId,
    query: query,
  );

  AppRouteState withPage(AppPage value) =>
      AppRouteState(workspaceId: workspaceId, page: value);

  AppRouteState withItem(String? value) => AppRouteState(
    workspaceId: workspaceId,
    page: page,
    itemId: value,
    query: query,
  );

  AppRouteState withQuery(Map<String, String?> values) {
    final next = <String, String>{...query};
    for (final MapEntry(:key, :value) in values.entries) {
      if (value == null || value.isEmpty) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    }
    return AppRouteState(
      workspaceId: workspaceId,
      page: page,
      itemId: itemId,
      query: _routeQuery(page, itemId, next),
    );
  }
}

/// The slug `/creative` used to occupy, kept only so old links resolve.
const _retiredCreativeSlug = 'creative';

/// The page a retired `/creative?tool=` value became.
AppPage _creativeToolPage(String? tool) => switch (tool?.trim()) {
  'image-edit' => AppPage.imageEdit,
  'video' => AppPage.videoGeneration,
  'video-editor' => AppPage.videoEditor,
  'music' => AppPage.songGeneration,
  'narration' => AppPage.narration,
  _ => AppPage.generate,
};

bool _supportsItem(AppPage page) => const {
  AppPage.characters,
  AppPage.history,
  AppPage.storyboards,
  AppPage.jobs,
  AppPage.terminalSessions,
  AppPage.tickets,
}.contains(page);

Map<String, String> _queryFor(AppPage page, Map<String, String> parameters) {
  String? value(String key) {
    final result = parameters[key]?.trim();
    return result?.isEmpty == true ? null : result;
  }

  return switch (page) {
    AppPage.history => {
      if (_permissionRef.hasMatch(value('object') ?? ''))
        'object': value('object')!,
    },
    AppPage.githubSetup => {
      'repository': ?value('repository'),
      if (const {
        'repository',
        'agent',
        'codex',
        'complete',
      }.contains(value('step')))
        'step': value('step')!,
    },
    AppPage.projectAdmin => _projectAdminQuery(value),
    AppPage.workspaceResources => const {},
    AppPage.organizationResources => const {},
    AppPage.characters => {if (value('tab') == 'body') 'tab': 'body'},
    AppPage.storyboards => {
      'panel': ?value('panel'),
      if (const {'animate', 'scenes'}.contains(value('view')))
        'view': value('view')!,
    },
    AppPage.tickets => {
      'repository': ?value('repository'),
      'project': ?value('project'),
      if (const {
        'todo',
        'working',
        'attention',
        'qa',
        'done',
        'all',
      }.contains(value('filter')))
        'filter': value('filter')!,
      'ticket': ?value('ticket'),
    },
    AppPage.agentPermissions => {
      'repository': ?value('repository'),
      if (_permissionRef.hasMatch(value('ref') ?? '')) 'ref': value('ref')!,
      if (value('from') == 'setup') 'from': 'setup',
    },
    AppPage.agentUsage => {
      if (const {'7', '90'}.contains(value('days'))) 'days': value('days')!,
      if (const {'local', 'cloud', 'unknown'}.contains(value('origin')))
        'origin': value('origin')!,
    },
    AppPage.generate => {
      if (value('mode') == 'references') 'mode': 'references',
      'model': ?value('model'),
    },
    AppPage.imageEdit => {
      if (value('mode') == 'inpaint') 'mode': 'inpaint',
      'model': ?value('model'),
    },
    AppPage.videoGeneration => _videoGenerationQuery(
      value('mode'),
      value('source'),
    ),
    _ => const {},
  };
}

Map<String, String> _projectAdminQuery(String? Function(String key) value) => {
  if (value('from') == 'setup') 'from': 'setup',
  'repository': ?value('repository'),
};

Map<String, String> _videoGenerationQuery(String? mode, String? source) => {
  if (const {'video_edit', 'video_continue'}.contains(mode)) 'mode': mode!,
  if (_sourceAssetId.hasMatch(source ?? '')) 'source': source!,
};

Map<String, String> _routeQuery(
  AppPage page,
  String? itemId,
  Map<String, String> parameters,
) {
  final query = <String, String>{..._queryFor(page, parameters)};
  return query;
}

final RegExp _permissionRef = RegExp(
  r'^(?!/)(?!.*(?:\.\.|//))[A-Za-z0-9._/-]{1,200}$',
);

final RegExp _sourceAssetId = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-'
  r'[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
);
