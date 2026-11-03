import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/agent_permission.dart';
import '../models/github_setup_readiness.dart';
import '../models/models.dart';
import '../models/workshop_ticket.dart';
import '../models/workshop_room.dart';
import '../models/workshop_rooms.dart';
import '../models/workshop_ticket_draft.dart';
import '../models/workshop_pull_request.dart';
import '../state/app_controller.dart';
import '../repositories/workshop_repository.dart';
import '../services/workshop_session_cache.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../view_models/workshop_deployment_view_model.dart';
import '../widgets/common.dart';
import 'software_workshop_ticket_widgets.dart';
import 'software_workshop_rooms.dart';
import 'software_workshop_reset_action.dart';
import 'software_workshop_setup_task.dart';
import 'ticket_dialog.dart';
import 'workshop_room_dialog.dart';
import 'workshop_ticket_delete_dialog.dart';
import 'workshop_ticket_review_dialog.dart';

part 'software_workshop_screen_actions.dart';

typedef WorkshopSelectionChanged =
    void Function(
      String? repository,
      String? projectId,
      WorkshopFilter filter,
      String? ticketId,
    );

typedef WorkshopRoomChanged =
    void Function(String roomId, String? repository, String projectId);

class SoftwareWorkshopScreen extends StatefulWidget {
  const SoftwareWorkshopScreen({
    required this.controller,
    required this.onSelectionChanged,
    required this.onRoomChanged,
    required this.onManagePermissions,
    required this.onReviewSetup,
    required this.onConfigureProjects,
    this.repository,
    this.roomId,
    this.projectId,
    this.filter,
    this.selectedTicketId,
    super.key,
  });

  final AppController controller;
  final String? repository;
  final String? roomId;
  final String? projectId;
  final String? filter;
  final String? selectedTicketId;
  final WorkshopSelectionChanged onSelectionChanged;
  final WorkshopRoomChanged onRoomChanged;
  final ValueChanged<String> onManagePermissions;
  final VoidCallback onReviewSetup;
  final VoidCallback onConfigureProjects;

  @override
  State<SoftwareWorkshopScreen> createState() => _SoftwareWorkshopScreenState();
}

class _SoftwareWorkshopScreenState extends State<SoftwareWorkshopScreen> {
  JsonMap? _project;
  Map<String, JsonMap> _agentDispatches = const {};
  List<AgentPermissionModel> _profiles = const [];
  bool _profilesVerified = false;
  GitHubSetupReadinessModel? _automationReadiness;
  bool _loading = true;
  bool _canonicalSelectionScheduled = false;
  bool _pendingDraftScheduled = false;
  String? _error;
  String? _automationError;
  final Set<String> _busyTicketIds = {};
  final Map<String, WorkshopPullRequestModel> _pullRequests = {};
  final Map<String, String> _pullRequestErrors = {};
  final Set<String> _loadingPullRequests = {};
  final Map<String, JsonMap> _createdTicketCache = {};
  late final WorkshopDeploymentViewModel _deployment;

  List<WorkshopRoomModel> get _rooms =>
      widget.controller.workspace!.resolvedWorkshopRooms;

  WorkshopRoomModel? get _room =>
      _rooms.where((room) => room.id == widget.roomId).firstOrNull ??
      _rooms.firstOrNull;

  String? get _repository {
    final repositories =
        _room?.repositories
            .where(widget.controller.workspace!.repositories.contains)
            .toList() ??
        const [];
    return repositories.contains(widget.repository)
        ? widget.repository
        : repositories.firstOrNull;
  }

  String? get _projectId {
    final roomProject = _room?.projectId;
    return widget.controller.workspace!.projects.any(
          (project) => project.id == roomProject,
        )
        ? roomProject
        : null;
  }

  ProjectConnection? get _roomProject => widget.controller.workspace!.projects
      .where((project) => project.id == _projectId)
      .firstOrNull;

  WorkshopFilter get _filter => WorkshopFilter.fromValue(widget.filter);

  JsonMap? get _statusField => _projectFields.where((field) {
    return field['__typename'] == 'ProjectV2SingleSelectField' &&
        (field['name'] as String? ?? '').toLowerCase() == 'status';
  }).firstOrNull;

  List<JsonMap> get _projectFields =>
      workshopNodes(asJsonMap(_project?['fields'])['nodes']);

  List<JsonMap> get _statusOptions => workshopNodes(_statusField?['options']);

  bool get _projectSupportsTodo =>
      _statusOptions.any((option) => option['name'] == 'Todo');

  List<WorkshopTicket> get _roomTickets {
    final statusFieldId = _statusField?['id'] as String? ?? '';
    final projectItems = workshopNodes(asJsonMap(_project?['items'])['nodes']);
    final items = workshopProjectItemsWithCreatedCache(
      projectItems,
      _createdTicketCache,
    );
    return items
        .where((item) {
          return asJsonMap(item['content'])['__typename'] == 'Issue';
        })
        .map(
          (item) => WorkshopTicket.fromProjectItem(
            item,
            statusFieldId: statusFieldId,
            agentDispatch:
                _agentDispatches[item['id'] as String? ?? ''] ?? const {},
          ),
        )
        .where(
          (ticket) => _room?.repositories.contains(ticket.repository) ?? false,
        )
        .toList();
  }

  List<WorkshopTicket> get _allTickets =>
      _roomTickets.where((ticket) => ticket.repository == _repository).toList();

  List<WorkshopTicket> get _visibleTickets =>
      _allTickets.where(_filter.includes).toList();

  Map<WorkshopFilter, int> get _filterCounts => {
    for (final filter in WorkshopFilter.values)
      filter: _allTickets.where(filter.includes).length,
  };

  List<WorkshopTicket> get _workingTickets =>
      _roomTickets.where((ticket) => ticket.agentWorking).toList();

  Duration? get _longestAgentRun {
    final starts = _workingTickets
        .map((ticket) => ticket.agentStartedAt)
        .whereType<DateTime>()
        .toList();
    if (starts.isEmpty) return null;
    final earliest = starts.reduce(
      (left, right) => left.isBefore(right) ? left : right,
    );
    final elapsed = DateTime.now().toUtc().difference(earliest);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  @override
  void initState() {
    super.initState();
    _deployment = WorkshopDeploymentViewModel(
      WorkshopApiRepository(widget.controller.api),
    )..addListener(_deploymentChanged);
    _restoreOrLoad();
  }

  @override
  void dispose() {
    _deployment.dispose();
    super.dispose();
  }

  void _deploymentChanged() {
    if (mounted) setState(() {});
  }

  void _restoreOrLoad() {
    final key = workshopSessionCacheKey(
      workspaceId: widget.controller.workspace?.id,
      projectId: _projectId,
      repository: _repository,
    );
    final snapshot = key == null
        ? null
        : widget.controller.workshopSessions.get(key);
    if (snapshot == null) {
      _load();
      return;
    }
    _applySnapshot(snapshot);
    _schedulePendingHealingDraft();
  }

  void _applySnapshot(WorkshopSessionSnapshot snapshot) {
    final value = WorkshopSessionPresentation.fromSnapshot(snapshot);
    _update(() {
      _project = value.project;
      _agentDispatches = value.agentDispatches;
      _profiles = value.profiles;
      _profilesVerified = value.profilesVerified;
      _automationReadiness = value.automationReadiness;
      _automationError = value.automationError;
      _error = null;
      _loading = false;
    });
  }

  @override
  void didUpdateWidget(covariant SoftwareWorkshopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repositoryChanged = oldWidget.repository != widget.repository;
    final projectChanged = oldWidget.projectId != widget.projectId;
    final roomChanged = oldWidget.roomId != widget.roomId;
    if (repositoryChanged || projectChanged || roomChanged) {
      _createdTicketCache.clear();
      _restoreOrLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleCanonicalSelection();
    final canWrite = widget.controller.can('tickets.write');
    return PageFrame(
      title: 'Software Workshop',
      subtitle: 'Open a room and act on the work that needs you next',
      actions: [
        FilledButton.icon(
          onPressed: canWrite && _repository != null && _projectId != null
              ? _create
              : null,
          icon: const Icon(LucideIcons.plus, size: 17),
          label: const Text('Create ticket'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_room == null)
            WorkshopRoomEmptyState(onConfigure: widget.onConfigureProjects)
          else ...[
            WorkshopRoomRail(
              rooms: _rooms,
              selected: _room!,
              onSelected: (room) => widget.onRoomChanged(
                room.id,
                room.repositories.firstOrNull,
                room.projectId,
              ),
              onAdd: () => _editRoom(),
              canManage: widget.controller.can('workspace.manage'),
            ),
            IiOsGap.vMd,
            WorkshopRoomHeader(
              room: _room!,
              project: _roomProject,
              repository: _repository ?? '',
              healthLabel: _automationStatus,
              healthReady: _automationReady,
              activeWorkers: _workingTickets.length,
              longestRunning: _longestAgentRun,
              onRepositoryChanged: (value) =>
                  _notify(repository: value, ticketId: null),
              onSettings: () => _editRoom(_room),
              canManage: widget.controller.can('workspace.manage'),
            ),
            IiOsGap.vMd,
            if (!_automationReady || _automationError != null) ...[
              _automationCard(),
              IiOsGap.vMd,
            ],
            WorkshopTaskFilterBar(
              selected: _filter,
              counts: _filterCounts,
              onSelected: (filter) => _notify(filter: filter, ticketId: null),
              onRefresh: () => _load(),
              refreshing: _loading,
            ),
            IiOsGap.vSm,
            _body(),
          ],
        ],
      ),
    );
  }

  Widget _automationCard() {
    final checks = _selectedAutomationChecks;
    final ready = _automationReady;
    final blockers = checks.where((check) => !check.dispatchable).toList();
    final health = _selectedRepositoryHealth;
    final status = _automationStatus;
    final statusColor = ready
        ? IiOsColors.green
        : health?.unavailable == true
        ? IiOsColors.muted
        : IiOsColors.amber;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  ready ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                  color: statusColor,
                  size: 21,
                ),
                const SizedBox(width: 9),
                const Expanded(child: SectionTitle('Repository agent health')),
                StatusPill(status, color: statusColor),
              ],
            ),
            const SizedBox(height: 7),
            Text(_automationDetail),
            if (_automationError != null) ...[
              const SizedBox(height: 6),
              Text(
                _automationError!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: IiOsColors.amber),
              ),
            ],
            if (blockers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: IiOsSpacing.sm),
                child: WorkshopNextSetupTask(
                  blocker: blockers.first,
                  remaining: blockers.length - 1,
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _repository == null
                        ? null
                        : () => widget.onManagePermissions(_repository!),
                    icon: const Icon(LucideIcons.shieldCheck, size: 17),
                    label: const Text('Manage permissions'),
                  ),
                  TextButton(
                    onPressed: widget.onReviewSetup,
                    child: const Text('Review agent setup'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _project == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Card(
        child: EmptyState(
          title: 'Workshop could not be loaded',
          message: _error!,
          icon: LucideIcons.triangleAlert,
          action: FilledButton(onPressed: _load, child: const Text('Retry')),
        ),
      );
    }
    final tickets = _visibleTickets;
    if (tickets.isEmpty) {
      return Card(
        child: EmptyState(
          title: _allTickets.isEmpty
              ? 'Your workshop is clear'
              : 'No tickets in this view',
          message: _allTickets.isEmpty
              ? 'Create a focused ticket when you are ready to hand work to an agent.'
              : 'Choose another view to see the rest of this repository\u2019s workshop tickets.',
          icon: LucideIcons.ticketCheck,
          action: widget.controller.can('tickets.write')
              ? FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(LucideIcons.plus, size: 17),
                  label: const Text('Create ticket'),
                )
              : null,
        ),
      );
    }
    final selected = tickets
        .where((ticket) => ticket.itemId == widget.selectedTicketId)
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final list = Column(
          children: [
            for (var index = 0; index < tickets.length; index++) ...[
              WorkshopTicketListCard(
                ticket: tickets[index],
                selected: tickets[index].itemId == selected?.itemId,
                accentColor: workshopRoomColor(context, _room?.color ?? 'cyan'),
                onSelected: () => _notify(ticketId: tickets[index].itemId),
              ),
              if (index != tickets.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
        final detail = selected == null
            ? const Card(
                child: EmptyState(
                  title: 'Select a ticket',
                  message:
                      'Open a workshop ticket to review its brief, permissions, status, and agent handoff.',
                  icon: LucideIcons.panelRightOpen,
                ),
              )
            : _ticketDetail(selected);
        if (constraints.maxWidth < 920) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              list,
              if (selected != null) ...[const SizedBox(height: 14), detail],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 390, child: list),
            const SizedBox(width: 14),
            Expanded(child: detail),
          ],
        );
      },
    );
  }

  List<GitHubSetupCheckModel> get _selectedAutomationChecks {
    final repository = _repository;
    final readiness = _automationReadiness;
    if (readiness == null || repository == null) return const [];
    return [...readiness.workspace.checks, ...readiness.checksFor(repository)];
  }

  GitHubRepositoryHealthModel? get _selectedRepositoryHealth {
    final repository = _repository;
    return repository == null
        ? null
        : _automationReadiness?.healthFor(repository);
  }

  bool get _automationReady {
    final repository = _repository;
    return repository != null &&
        (_automationReadiness?.readyFor(repository) ?? false);
  }

  String get _automationStatus {
    if (_automationReadiness == null) return 'Not checked';
    if (!_automationReadiness!.workspace.ready) return 'Deployments paused';
    final health = _selectedRepositoryHealth;
    if (health != null) return health.label;
    return _automationReady ? 'Live verified' : 'Action required';
  }

  String get _automationDetail {
    if (_automationReadiness == null) {
      return 'Run the repository checks before deploying agent work.';
    }
    if (!_automationReadiness!.workspace.ready) {
      return 'This repository may be configured, but direct human deployment is unavailable.';
    }
    final health = _selectedRepositoryHealth;
    if (_automationReady) {
      return 'Live checks passed for the GitHub App, workflow, committed permission profile, protected environment, and Codex.';
    }
    if (health?.verificationRequired == true) {
      return 'The Codex credential is stored but has not passed a real request. Normal tickets remain blocked until the credential canary succeeds.';
    }
    if (health?.unavailable == true) {
      return 'ii-os could not prove the repository is healthy. Deployment fails closed until live checks are available again.';
    }
    return 'Finish the remaining repository setup before a ticket can be deployed.';
  }

  WorkshopTicketReadiness _ticketReadiness(WorkshopTicket ticket) =>
      ticket.readiness(
        profiles: _profiles,
        permissionProfilesVerified: _profilesVerified,
        projectSupportsTodo: _projectSupportsTodo,
        automationReady: _automationReady,
        automationDetail: _automationDetail,
      );

  void _notify({
    String? repository,
    String? projectId,
    WorkshopFilter? filter,
    String? ticketId,
  }) {
    widget.onSelectionChanged(
      repository ?? _repository,
      projectId ?? _projectId,
      filter ?? _filter,
      ticketId,
    );
  }

  void _update(VoidCallback update) => setState(update);

  void _scheduleCanonicalSelection() {
    final room = _room;
    if (room != null && widget.roomId != room.id) {
      if (_canonicalSelectionScheduled) return;
      _canonicalSelectionScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _canonicalSelectionScheduled = false;
        if (mounted) {
          widget.onRoomChanged(room.id, _repository, room.projectId);
        }
      });
      return;
    }
    final selectedExists =
        _project == null ||
        widget.selectedTicketId == null ||
        _visibleTickets.any(
          (ticket) => ticket.itemId == widget.selectedTicketId,
        );
    final canonical =
        widget.repository == _repository &&
        widget.projectId == _projectId &&
        (widget.filter == null || widget.filter == _filter.value) &&
        selectedExists;
    if (canonical || _canonicalSelectionScheduled) return;
    _canonicalSelectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _canonicalSelectionScheduled = false;
      if (mounted) {
        widget.onSelectionChanged(
          _repository,
          _projectId,
          _filter,
          selectedExists ? widget.selectedTicketId : null,
        );
      }
    });
  }
}

extension _FirstWorkshopOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
