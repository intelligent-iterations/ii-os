import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/agent_usage.dart';
import '../models/image_edit_selection.dart';
import '../models/image_workflow_capabilities.dart';
import '../models/minimax_h3_generation_spec.dart';
import '../models/production_line.dart';
import '../models/workshop_ticket.dart';
import '../navigation/app_route_state.dart';
import '../services/bug_report_client.dart';
import '../services/generation_notification_service.dart';
import '../state/app_controller.dart';
import '../state/appearance_controller.dart';
import '../widgets/bug_report_button.dart';
import '../widgets/common.dart';
import '../widgets/invitation_dialogs.dart';
import '../widgets/ii_os_app_title.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import '../widgets/notification_bell.dart';
import '../widgets/workspace_creation_dialog.dart';
import 'agent_permissions_screen.dart';
import 'agent_usage_screen.dart';
import 'characters_screen.dart';
import 'data_plane_connection_screen.dart';
import 'fleet_screen.dart';
import 'generate_screen.dart';
import 'github_setup_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'image_edit_panel.dart';
import 'jobs_screen.dart';
import 'interactive_sessions_screen.dart';
import 'narration_generation_screen.dart';
import 'no_workspace_screen.dart';
import 'organization_resources_screen.dart';
import 'people_screen.dart';
import 'playground_screen.dart';
import 'production_line_screen.dart';
import 'project_admin_page.dart';
import 'software_workshop_screen.dart';
import 'song_generation_screen.dart';
import 'storyboards_screen.dart';
import 'video_generation_screen.dart';
import 'video_editor_screen.dart';
import 'workspace_resource_selection_screen.dart';

part 'operator_shell_support.dart';
part 'operator_shell_workshop.dart';

class OperatorShell extends StatefulWidget {
  const OperatorShell({required this.user, required this.route, super.key});

  final User user;
  final AppRouteState route;

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AppController _controller;
  late final GenerationNotificationService _notifications;
  late final StreamSubscription<String> _notificationOpenSubscription;
  bool _railExpanded = true;
  bool _syncingWorkspace = false;
  bool _ghostMode = false;
  String? _pendingLocation;

  @override
  void initState() {
    super.initState();
    _controller = AppController()
      ..initialize(preferredWorkspaceId: widget.route.workspaceId);
    _notifications = GenerationNotificationService(api: _controller.api);
    _notificationOpenSubscription = _notifications.openedDeepLinks.listen(
      _openNotification,
    );
    unawaited(_notifications.start());
  }

  @override
  void didUpdateWidget(covariant OperatorShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pendingLocation == widget.route.location) _pendingLocation = null;
    if (oldWidget.route.workspaceId != widget.route.workspaceId) {
      _ghostMode = false;
      unawaited(_selectWorkspaceFromRoute());
    }
  }

  @override
  void dispose() {
    unawaited(_notificationOpenSubscription.cancel());
    _notifications.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.loading || _syncingWorkspace) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_controller.session == null) {
          return DataPlaneConnectionScreen(controller: _controller);
        }
        if (_controller.workspace == null) {
          return NoWorkspaceScreen(controller: _controller);
        }
        _canonicalizeWorkspace();
        final organization = _controller.session?.organizationFor(
          _controller.workspace?.id,
        );
        if (_controller.connection == null &&
            _controller.workspace!.resourceGrantVersion == 1) {
          if (organization?.resources.gcp.any((item) => item.active) == true) {
            return WorkspaceResourceSelectionScreen(controller: _controller);
          }
          return OrganizationResourcesScreen(controller: _controller);
        }
        if (_controller.connection == null) {
          return DataPlaneConnectionScreen(controller: _controller);
        }
        // Consuming the onboarding flag is a state change, so it happens after
        // the frame rather than inside build(). Reading it here is fine;
        // clearing it here would mutate the controller mid-render.
        final requestedPage = _controller.openWorkspaceResourceSelection
            ? AppPage.workspaceResources
            : widget.route.page;
        if (_controller.openWorkspaceResourceSelection) {
          _consumeOnboardingFlag();
        }
        final page = _canOpen(requestedPage) ? requestedPage : AppPage.home;
        if (page != widget.route.page) {
          _replaceRoute(widget.route.withPage(page));
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final palette = IiOsPalette.of(context);
            final compact = constraints.maxWidth < 900;
            return Scaffold(
              key: _scaffoldKey,
              drawer: compact
                  ? Drawer(
                      width: 280,
                      child: SafeArea(
                        child: OperatorNavigation(
                          controller: _controller,
                          page: page,
                          itemId: widget.route.itemId,
                          onSelect: _selectNavDestination,
                        ),
                      ),
                    )
                  : null,
              appBar: _AppBar(
                controller: _controller,
                currentRoute: widget.route.location,
                notifications: _notifications,
                onOpenNotification: _openNotification,
                onWorkspaceSelected: _selectWorkspace,
                onCreateWorkspace: _createWorkspace,
                onMenu: () {
                  if (compact) {
                    _scaffoldKey.currentState?.openDrawer();
                  } else {
                    setState(() => _railExpanded = !_railExpanded);
                  }
                },
              ),
              body: Column(
                children: [
                  if (_controller.errorMessage != null)
                    MaterialBanner(
                      content: Text(_controller.errorMessage!),
                      leading: Icon(
                        LucideIcons.triangleAlert,
                        color: palette.danger.text,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => _controller.refresh(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!compact)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: _railExpanded ? 228 : 68,
                            decoration: BoxDecoration(
                              color: palette.surface,
                              border: Border(
                                right: BorderSide(color: palette.border),
                              ),
                            ),
                            child: OperatorNavigation(
                              controller: _controller,
                              page: page,
                              itemId: widget.route.itemId,
                              expanded: _railExpanded,
                              onSelect: _selectNavDestination,
                            ),
                          ),
                        Expanded(child: _currentPage(page)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Clears the one-shot onboarding flag once the current frame is on screen.
  void _consumeOnboardingFlag() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.openWorkspaceResourceSelection = false;
    });
  }

  Widget _currentPage(AppPage page) {
    final route = page == widget.route.page
        ? widget.route
        : widget.route.withPage(page);
    // Keyed on workspace and page only. Including the selected item id here
    // made every selection a different widget, so Flutter tore the page's
    // State down and initState refetched the whole list -- a round-trip and a
    // lost scroll position per click. Pages read the selected id from their
    // widget fields, so a plain rebuild is enough.
    final key = ValueKey('${_controller.workspace!.id}:${route.page.name}');
    return switch (route.page) {
      AppPage.home => HomeScreen(key: key, controller: _controller),
      AppPage.githubSetup => GitHubSetupScreen(
        key: key,
        controller: _controller,
        repository: route.query['repository'],
        step: route.query['step'],
        onRepositoryChanged: (value) =>
            _setQuery({'repository': value, 'step': 'repository'}),
        onStepChanged: (value) => _setQuery({'step': value}),
        onOpenWorkshop: () => _goRoute(
          widget.route.withPage(AppPage.tickets).withQuery({
            'repository': route.query['repository'],
          }),
        ),
      ),
      AppPage.projectAdmin => _withSetupReturn(
        route,
        ProjectAdminPage(
          key: key,
          controller: _controller,
          tab: ProjectAdminTab.parse(route.query['tab']),
          onTabChanged: (tab) => _setQuery({'tab': tab.query, 'days': null}),
          onManageOrganizationResources: () =>
              _selectPage(AppPage.organizationResources),
          onManageWorkspaceAccess: () =>
              _selectPage(AppPage.workspaceResources),
          onOpenGitHubSetup: () => _selectPage(AppPage.githubSetup),
        ),
      ),
      AppPage.workspaceResources => WorkspaceResourceSelectionScreen(
        key: key,
        controller: _controller,
        embedded: true,
        onOpenWorkspaceSetup: () => _selectPage(AppPage.projectAdmin),
      ),
      AppPage.organizationResources => OrganizationResourcesScreen(
        key: key,
        controller: _controller,
        embedded: true,
      ),
      AppPage.tickets => SoftwareWorkshopScreen(
        key: key,
        controller: _controller,
        roomId: route.itemId,
        repository: route.query['repository'],
        projectId: route.query['project'],
        filter: route.query['filter'],
        selectedTicketId: route.query['ticket'],
        onSelectionChanged: _selectWorkshop,
        onRoomChanged: _selectWorkshopRoom,
        onManagePermissions: _openWorkshopPermissions,
        onReviewSetup: () => _openGitHubSetup(route.query['repository']),
        onConfigureProjects: () => _selectPage(AppPage.projectAdmin),
      ),
      AppPage.productionLine => ProductionLineScreen(
        key: key,
        controller: _controller,
        lineId: route.itemId ?? '',
        onOpenGitHub: _openExternal,
        onManagePermissions: _openWorkshopPermissions,
      ),
      AppPage.agentPermissions => _withSetupReturn(
        route,
        AgentPermissionsScreen(
          key: key,
          controller: _controller,
          repository: route.query['repository'],
          ref: route.query['ref'],
          onSelectionChanged: _selectAgentPermissionView,
        ),
      ),
      AppPage.agentUsage => AgentUsageScreen(
        key: key,
        controller: _controller,
        days: int.tryParse(route.query['days'] ?? '') ?? 30,
        origin: AgentExecutionOrigin.parse(route.query['origin']),
        onFilterChanged: (days, origin) => _setQuery({
          'days': days == 30 ? null : '$days',
          'origin': origin == AgentExecutionOrigin.all ? null : origin.value,
        }),
      ),
      AppPage.playground => PlaygroundScreen(key: key, controller: _controller),
      AppPage.characters => CharactersScreen(
        key: key,
        controller: _controller,
        selectedCharacterId: route.itemId,
        onSelectCharacter: _selectCharacter,
        onCloseCharacter: _closeItem,
      ),
      AppPage.storyboards => StoryboardsScreen(
        key: key,
        controller: _controller,
        selectedStoryboardId: route.itemId,
        selectedPanelId: route.query['panel'],
        selectedView: route.query['view'],
        onSelectStoryboard: _selectStoryboard,
        onCloseStoryboard: _closeItem,
        onPanelChanged: (value) => _replaceQuery({'panel': value}),
        onViewChanged: (value) => _setQuery({'view': value}),
      ),
      AppPage.generate => GenerateScreen(
        key: key,
        controller: _controller,
        ghostMode: _ghostMode,
        onGhostModeChanged: _setGhostMode,
        initialMode: route.query['mode'] == 'references'
            ? ImageGenerationMode.references
            : ImageGenerationMode.prompt,
        initialTemplateId: route.query['model'],
        onModeChanged: (mode) => _setQuery({
          'mode': mode == ImageGenerationMode.references ? 'references' : null,
          'model': null,
        }),
        onTemplateChanged: (value) => _setQuery({'model': value}),
      ),
      AppPage.imageEdit => ImageEditScreen(
        key: key,
        controller: _controller,
        ghostMode: _ghostMode,
        onGhostModeChanged: _setGhostMode,
        initialMode: route.query['mode'] == 'inpaint'
            ? ImageEditMode.inpaint
            : ImageEditMode.revision,
        initialTemplateId: route.query['model'],
        onModeChanged: (mode) => _setQuery({
          'mode': mode == ImageEditMode.inpaint ? 'inpaint' : null,
          'model': null,
        }),
        onTemplateChanged: (value) => _setQuery({'model': value}),
      ),
      AppPage.videoGeneration => VideoGenerationScreen(
        key: key,
        controller: _controller,
        ghostMode: _ghostMode,
        onGhostModeChanged: _setGhostMode,
        initialH3Mode: switch (route.query['mode']) {
          'video_edit' => MiniMaxH3GenerationMode.videoEdit,
          'video_continue' => MiniMaxH3GenerationMode.videoContinue,
          _ => null,
        },
        initialH3SourceAssetId: route.query['source'],
      ),
      AppPage.videoEditor => VideoEditorScreen(
        key: key,
        controller: _controller,
        ghostMode: _ghostMode,
        onGhostModeChanged: _setGhostMode,
      ),
      AppPage.songGeneration => SongGenerationScreen(
        key: key,
        controller: _controller,
        ghostMode: _ghostMode,
        onGhostModeChanged: _setGhostMode,
      ),
      AppPage.narration => NarrationGenerationScreen(
        key: key,
        controller: _controller,
        ghostMode: _ghostMode,
        onGhostModeChanged: _setGhostMode,
      ),
      AppPage.history => HistoryScreen(
        key: key,
        controller: _controller,
        selectedJobId: route.itemId,
        selectedObject: route.query['object'],
        onJobViewed: (jobId) => unawaited(_notifications.markReadForJob(jobId)),
      ),
      AppPage.jobs => JobsScreen(
        key: key,
        controller: _controller,
        selectedJobId: route.itemId,
        onSelectJob: _selectJob,
        onCloseJob: _closeItem,
        onJobViewed: (jobId) => unawaited(_notifications.markReadForJob(jobId)),
      ),
      AppPage.terminalSessions => InteractiveSessionsScreen(
        key: key,
        controller: _controller,
        selectedSessionId: route.itemId,
        onSelectSession: _selectTerminalSession,
        onCloseSession: _closeItem,
      ),
      AppPage.people => PeopleScreen(key: key, controller: _controller),
      AppPage.fleet => FleetScreen(key: key, controller: _controller),
    };
  }

  Widget _withSetupReturn(AppRouteState route, Widget child) {
    if (route.query['from'] != 'setup') return child;
    return Column(
      children: [
        Material(
          color: IiOsPalette.of(context).info.container,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                const Icon(LucideIcons.wandSparkles, size: 18),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'You\u2019re completing Software Workshop setup.',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openGitHubSetup(route.query['repository']),
                  icon: const Icon(LucideIcons.arrowLeft, size: 16),
                  label: const Text('Back to setup'),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  void _selectPage(AppPage page) {
    _goRoute(widget.route.withPage(page));
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  /// Opens a sidebar destination, carrying the resource id when the entry is
  /// one of several sharing a page -- a production line, for instance.
  void _selectNavDestination(AppPage page, {String? itemId}) {
    if (itemId == null) {
      _selectPage(page);
      return;
    }
    _goRoute(widget.route.withPage(page).withItem(itemId));
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openExternal(String url) async {
    if (url.isEmpty) return;
    final target = Uri.tryParse(url);
    if (target == null) return;
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  void _openNotification(String location) {
    if (!mounted || location == widget.route.location) return;
    context.go(location);
  }

  bool _canOpen(AppPage page) => switch (page) {
    AppPage.home || AppPage.githubSetup => true,
    AppPage.projectAdmin => _controller.can('workspace.manage'),
    AppPage.workspaceResources =>
      _controller.can('workspace.manage') ||
          _canInOrganization(_controller, 'org.integrations.manage'),
    AppPage.organizationResources =>
      _canInOrganization(_controller, 'org.integrations.manage') ||
          _canInOrganization(_controller, 'org.runners.manage'),
    AppPage.tickets => _controller.can('tickets.read'),
    AppPage.productionLine => _controller.can('lines.read'),
    AppPage.agentPermissions => _controller.can('agent.permissions.read'),
    AppPage.agentUsage => _controller.can('audit.read'),
    AppPage.playground => _controller.can('jobs.trigger'),
    AppPage.characters => _controller.can('characters.read'),
    AppPage.storyboards || AppPage.history =>
      _controller.can('jobs.read') || _controller.can('jobs.trigger'),
    AppPage.generate ||
    AppPage.imageEdit ||
    AppPage.videoGeneration ||
    AppPage.videoEditor ||
    AppPage.songGeneration ||
    AppPage.narration => _controller.can('jobs.trigger'),
    AppPage.jobs => _controller.can('jobs.read'),
    AppPage.terminalSessions => _controller.can('interactive.sessions.read'),
    AppPage.people =>
      _controller.can('members.manage') ||
          _canInOrganization(_controller, 'org.workspaces.access.manage'),
    // Tenant tier: no project role implies this one.
    AppPage.fleet => _canInOrganization(_controller, 'org.audit.read'),
  };

  void _selectCharacter(String characterId) {
    _goRoute(widget.route.withItem(characterId));
  }

  void _selectStoryboard(String storyboardId) {
    _goRoute(widget.route.withItem(storyboardId));
  }

  void _selectJob(String jobId) {
    _goRoute(widget.route.withItem(jobId));
  }

  void _selectTerminalSession(String sessionId) {
    _goRoute(widget.route.withItem(sessionId));
  }

  void _closeItem() {
    _goRoute(
      widget.route.withItem(null).withQuery({
        'tab': null,
        'panel': null,
        'view': null,
      }),
    );
  }

  void _openWorkshopPermissions(String repository) {
    _goRoute(
      widget.route.withPage(AppPage.agentPermissions).withQuery({
        'repository': repository,
        'ref': 'dev',
      }),
    );
  }

  void _openGitHubSetup(String? repository) {
    _goRoute(
      widget.route.withPage(AppPage.githubSetup).withQuery({
        'repository': repository,
      }),
    );
  }

  void _selectAgentPermissionView(String? repository, String ref) {
    _goRoute(widget.route.withQuery({'repository': repository, 'ref': ref}));
  }

  void _setQuery(Map<String, String?> values) {
    _goRoute(widget.route.withQuery(values));
  }

  void _setGhostMode(bool value) {
    if (_ghostMode == value) return;
    setState(() => _ghostMode = value);
  }

  void _replaceQuery(Map<String, String?> values) {
    _replaceRoute(widget.route.withQuery(values));
  }

  Future<void> _selectWorkspace(String workspaceId) async {
    if (_controller.workspace?.id == workspaceId) return;
    setState(() => _syncingWorkspace = true);
    try {
      await _controller.selectWorkspace(workspaceId);
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _syncingWorkspace = false);
    }
    if (!mounted) return;
    final selectedId = _controller.workspace?.id;
    if (selectedId != null) {
      _goRoute(widget.route.withWorkspace(selectedId));
    }
  }

  Future<void> _createWorkspace() async {
    final organization = _controller.session?.organizationFor(
      _controller.workspace?.id,
    );
    if (organization == null || !organization.can('org.workspaces.create')) {
      return;
    }
    final request = await showWorkspaceCreationDialog(
      context: context,
      organization: organization,
    );
    if (request == null || !mounted) return;
    try {
      final workspaceId = await _controller.createWorkspace(
        request.name,
        request.environment,
        organizationId: organization.id,
      );
      if (mounted) {
        _goRoute(
          widget.route
              .withWorkspace(workspaceId)
              .withPage(AppPage.workspaceResources),
        );
      }
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _selectWorkspaceFromRoute() async {
    final requested = widget.route.workspaceId;
    if (requested == null || requested == _controller.workspace?.id) return;
    setState(() => _syncingWorkspace = true);
    try {
      await _controller.selectWorkspace(requested);
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _syncingWorkspace = false);
    }
    if (!mounted) return;
    _canonicalizeWorkspace();
  }

  void _canonicalizeWorkspace() {
    final selectedId = _controller.workspace?.id;
    if (selectedId == null || selectedId == widget.route.workspaceId) return;
    _replaceRoute(widget.route.withWorkspace(selectedId));
  }

  void _goRoute(AppRouteState route) {
    final location = route.location;
    if (location == widget.route.location || location == _pendingLocation) {
      return;
    }
    _pendingLocation = location;
    context.go(location);
  }

  void _replaceRoute(AppRouteState route) {
    final location = route.location;
    if (location == widget.route.location || location == _pendingLocation) {
      return;
    }
    _pendingLocation = location;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingLocation == location) context.replace(location);
    });
  }
}
