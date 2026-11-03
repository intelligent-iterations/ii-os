part of 'software_workshop_screen.dart';

extension _SoftwareWorkshopActions on _SoftwareWorkshopScreenState {
  WorkshopApiRepository get _workshopRepository =>
      WorkshopApiRepository(widget.controller.api);

  Widget _ticketDetail(WorkshopTicket ticket) {
    final readiness = _ticketReadiness(ticket);
    final deploying = _deployment.deploying(ticket.itemId);
    final resetting = _deployment.resetting(ticket.itemId);
    if (ticket.hasPullRequest &&
        !_pullRequests.containsKey(ticket.itemId) &&
        !_pullRequestErrors.containsKey(ticket.itemId) &&
        !_loadingPullRequests.contains(ticket.itemId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPullRequest(ticket);
      });
    }
    return WorkshopTicketDetail(
      ticket: ticket,
      readiness: readiness,
      profile: _profilesVerified ? ticket.installedProfile(_profiles) : null,
      statusOptions: _statusOptions,
      canWrite: widget.controller.can('tickets.write'),
      busy: _busyTicketIds.contains(ticket.itemId) || deploying || resetting,
      deploying: deploying,
      onEdit: () => _edit(ticket),
      onDelete: () => _delete(ticket),
      onReset: ticket.canReset
          ? () => resetWorkshopTicket(
              context: context,
              ticket: ticket,
              workspaceId: widget.controller.workspace!.id,
              projectId: _projectId!,
              deployment: _deployment,
              reload: _load,
            )
          : null,
      onReview: () => _review(ticket, readiness),
      onPause: () => _pause(ticket),
      onStatusChanged: (optionId) => _setStatus(ticket, optionId),
      onOpenGitHub: () => openWorkshopUrl(ticket.url),
      onManagePermissions: () => widget.onManagePermissions(ticket.repository),
      pullRequest: _pullRequests[ticket.itemId],
      pullRequestLoading: _loadingPullRequests.contains(ticket.itemId),
      pullRequestError: _pullRequestErrors[ticket.itemId],
      canMergePullRequest: widget.controller.can('pull_requests.merge'),
      onOpenPullRequest: ticket.hasPullRequest
          ? () => openWorkshopUrl(ticket.finalPullRequestUrl)
          : null,
      onRefreshPullRequest: ticket.hasPullRequest
          ? () => _loadPullRequest(ticket, refresh: true)
          : null,
      onApproveAndMerge: _pullRequests[ticket.itemId]?.canRequestMerge == true
          ? () => _approveAndMergePullRequest(
              ticket,
              _pullRequests[ticket.itemId]!,
            )
          : null,
      onResolvePullRequestConflicts:
          _pullRequests[ticket.itemId]?.hasMergeConflicts == true
          ? () => _review(
              ticket,
              readiness,
              conflictedPullRequest: _pullRequests[ticket.itemId],
            )
          : null,
    );
  }

  Future<void> _loadPullRequest(
    WorkshopTicket ticket, {
    bool refresh = false,
  }) async {
    if (_loadingPullRequests.contains(ticket.itemId)) return;
    if (!refresh && _pullRequests.containsKey(ticket.itemId)) return;
    _update(() {
      _loadingPullRequests.add(ticket.itemId);
      _pullRequestErrors.remove(ticket.itemId);
    });
    try {
      final pullRequest = await _workshopRepository.pullRequest(
        workspaceId: widget.controller.workspace!.id,
        itemId: ticket.itemId,
      );
      if (!mounted) return;
      _update(() => _pullRequests[ticket.itemId] = pullRequest);
    } on Object {
      if (mounted) {
        _update(
          () => _pullRequestErrors[ticket.itemId] =
              'Pull request details are temporarily unavailable. Refresh the PR to try again.',
        );
      }
    } finally {
      if (mounted) _update(() => _loadingPullRequests.remove(ticket.itemId));
    }
  }

  Future<void> _approveAndMergePullRequest(
    WorkshopTicket ticket,
    WorkshopPullRequestModel pullRequest,
  ) async {
    if (!widget.controller.can('pull_requests.merge') ||
        !pullRequest.canRequestMerge) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Approve and merge #${pullRequest.number}?'),
        content: Text(
          '${pullRequest.title}\n\n'
          'ii-os will record your approval and ask GitHub to merge the exact '
          '${pullRequest.headSha.substring(0, 8)} commit into dev. GitHub '
          'branch protection and required checks still apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(LucideIcons.gitMerge, size: 17),
            label: const Text('Approve & merge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _update(() {
      _busyTicketIds.add(ticket.itemId);
      _pullRequestErrors.remove(ticket.itemId);
    });
    try {
      final merged = await _workshopRepository.approveAndMergePullRequest(
        workspaceId: widget.controller.workspace!.id,
        itemId: ticket.itemId,
        expectedHeadSha: pullRequest.headSha,
      );
      if (!mounted) return;
      _update(() => _pullRequests[ticket.itemId] = merged);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pull request #${merged.number} merged to dev. Ready for QA will appear after the dev deployment succeeds.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _update(() => _pullRequestErrors[ticket.itemId] = error.toString());
      showFailure(context, error);
    } finally {
      if (mounted) _update(() => _busyTicketIds.remove(ticket.itemId));
    }
  }

  Future<void> _load() async {
    final projectId = _projectId;
    final repository = _repository;
    if (projectId == null || repository == null) {
      if (mounted) _update(() => _loading = false);
      return;
    }
    final cacheKey = WorkshopSessionCacheKey(
      workspaceId: widget.controller.workspace!.id,
      projectId: projectId,
      repository: repository,
    );
    _update(() => _loading = true);
    try {
      final snapshot = await loadWorkshopSessionSnapshot(
        loadProject: () => widget.controller.api.get(
          'v1/workspaces/${widget.controller.workspace!.id}/projects',
          query: {'projectId': projectId, 'repository': repository},
        ),
        loadProfiles: () => widget.controller.api.get(
          'v1/workspaces/${widget.controller.workspace!.id}/agent-permissions',
          query: {'repository': repository, 'ref': 'dev'},
        ),
        loadReadiness: () => widget.controller.api.get(
          'v1/workspaces/${widget.controller.workspace!.id}/agent-readiness',
          query: {'repository': repository},
        ),
      );
      if (!mounted) return;
      widget.controller.workshopSessions.put(cacheKey, snapshot);
      _applySnapshot(snapshot);
      _update(() {
        final loadedIds = workshopNodes(
          asJsonMap(_project?['items'])['nodes'],
        ).map((item) => item['id']).whereType<String>().toSet();
        _createdTicketCache.removeWhere((id, _) => loadedIds.contains(id));
      });
      final selectedPullRequest = _allTickets
          .where(
            (ticket) =>
                ticket.itemId == widget.selectedTicketId &&
                ticket.hasPullRequest,
          )
          .firstOrNull;
      if (selectedPullRequest != null) {
        await _loadPullRequest(selectedPullRequest, refresh: true);
      }
      _schedulePendingHealingDraft();
    } on Object catch (error) {
      if (mounted) _update(() => _error = error.toString());
    } finally {
      if (mounted) _update(() => _loading = false);
    }
  }

  Future<void> _create([WorkshopTicketDraft? draft]) async {
    final repository = _repository;
    if (repository == null) return;
    final value = await showDialog<TicketEditData>(
      context: context,
      builder: (context) => TicketDialog(
        heading: draft == null
            ? 'Create workshop ticket'
            : 'Create healing ticket',
        repository: repository,
        draft: draft,
        projectId: _projectId,
        projects: widget.controller.workspace!.projects,
        permissionProfiles: _profiles,
        initialPermissionProfile: _room?.permissionProfile,
      ),
    );
    if (value == null || !mounted) return;
    await _save(value, repository: repository);
  }

  void _schedulePendingHealingDraft() {
    if (_pendingDraftScheduled || !widget.controller.can('tickets.write')) {
      return;
    }
    final workspace = widget.controller.workspace;
    final room = _room;
    final repository = _repository;
    final projectId = _projectId;
    final pending = widget.controller.workshopTicketDrafts.pending;
    if (workspace == null ||
        room == null ||
        repository == null ||
        projectId == null ||
        pending == null ||
        pending.workspaceId != workspace.id ||
        pending.roomId != room.id ||
        pending.repository != repository ||
        pending.projectId != projectId) {
      return;
    }
    _pendingDraftScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _pendingDraftScheduled = false;
      if (!mounted) return;
      final draft = widget.controller.workshopTicketDrafts.take(
        workspaceId: workspace.id,
        roomId: room.id,
        repository: repository,
        projectId: projectId,
      );
      if (draft != null) await _create(draft);
    });
  }

  Future<void> _editRoom([WorkshopRoomModel? initial]) async {
    final workspace = widget.controller.workspace!;
    final value = await showDialog<WorkshopRoomEditData>(
      context: context,
      builder: (context) => WorkshopRoomDialog(
        repositories: workspace.repositories,
        projects: workspace.projects,
        permissionProfiles: _profiles,
        initial: initial,
      ),
    );
    if (value == null || !mounted) return;
    final room = WorkshopRoomModel(
      id: initial?.id ?? _roomId(value.name),
      name: value.name,
      color: value.color,
      repositories: value.repositories,
      projectId: value.projectId,
      permissionProfile: value.permissionProfile,
    );
    final rooms = [..._rooms];
    final index = rooms.indexWhere((item) => item.id == room.id);
    index < 0 ? rooms.add(room) : rooms[index] = room;
    try {
      await WorkshopApiRepository(
        widget.controller.api,
      ).saveRooms(workspace.id, rooms);
      await widget.controller.refresh();
      if (!mounted) return;
      widget.onRoomChanged(
        room.id,
        room.repositories.firstOrNull,
        room.projectId,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(initial == null ? 'Room created.' : 'Room updated.'),
        ),
      );
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  String _roomId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safe = base.isEmpty
        ? 'room'
        : base.substring(0, base.length > 40 ? 40 : base.length);
    if (_rooms.every((room) => room.id != safe)) return safe;
    var suffix = 2;
    while (_rooms.any((room) => room.id == '$safe-$suffix')) {
      suffix++;
    }
    return '$safe-$suffix';
  }

  Future<void> _edit(WorkshopTicket ticket) async {
    final value = await showDialog<TicketEditData>(
      context: context,
      builder: (context) => TicketDialog(
        heading: 'Edit ticket #${ticket.number}',
        repository: ticket.repository,
        initial: ticket.toTicketModel(),
        permissionProfiles: _profiles,
      ),
    );
    if (value == null || !mounted) return;
    await _save(value, repository: ticket.repository, ticket: ticket);
  }

  Future<void> _save(
    TicketEditData value, {
    required String repository,
    WorkshopTicket? ticket,
  }) async {
    final body = <String, Object?>{
      'repository': repository,
      'title': value.title,
      'definitionOfDone': value.definitionOfDone,
      'howToTest': value.howToTest,
      'permissions': {
        'profile': value.permissionProfile,
        'ref': value.permissionRef,
      },
      'context': value.context,
      'state': value.state,
      if (ticket == null) 'projectId': value.projectId ?? _projectId,
    };
    try {
      final path =
          'v1/workspaces/${widget.controller.workspace!.id}/tickets${ticket == null ? '' : '/${ticket.number}'}';
      final response = ticket == null
          ? await widget.controller.api.post(path, body: body)
          : await widget.controller.api.patch(path, body: body);
      if (!mounted) return;
      if (ticket == null) {
        final todoOption = _statusOptions
            .where((option) => option['name'] == 'Todo')
            .firstOrNull;
        final item = workshopProjectItemFromCreatedIssue(
          response,
          repository: repository,
          statusFieldId: _statusField?['id'] as String?,
          statusOptionId: todoOption?['id'] as String?,
          statusName: todoOption == null ? '' : 'Todo',
        );
        final itemId = item['id'] as String?;
        if (itemId != null) _update(() => _createdTicketCache[itemId] = item);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ticket == null
                ? 'Ticket created. Review it before deploying.'
                : 'Ticket brief updated.',
          ),
        ),
      );
      await _load();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _review(
    WorkshopTicket ticket,
    WorkshopTicketReadiness readiness, {
    WorkshopPullRequestModel? conflictedPullRequest,
    String initialResponse = '',
  }) async {
    final result = await showDialog<WorkshopTicketReviewResult>(
      context: context,
      builder: (context) => WorkshopTicketReviewDialog(
        ticket: ticket,
        readiness: readiness,
        profile: ticket.installedProfile(_profiles),
        permissionProfiles: _profiles,
        conflictedPullRequest: conflictedPullRequest,
        initialResponse: initialResponse,
      ),
    );
    if (result == null || !mounted) return;
    if (!result.deploy) {
      try {
        await _deployment.selectProfile(
          workspaceId: widget.controller.workspace!.id,
          ticket: ticket,
          permissionProfile: result.permissionProfile,
          permissionRef: result.permissionRef,
        );
        await _load();
      } on Object catch (error) {
        if (mounted) showFailure(context, error);
        return;
      }
      if (!mounted) return;
      final updated = _allTickets
          .where((candidate) => candidate.itemId == ticket.itemId)
          .firstOrNull;
      if (updated == null ||
          updated.permissionProfile != result.permissionProfile ||
          updated.permissionRef != result.permissionRef) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The model choice could not be rechecked. Refresh the '
              'Workshop and review the ticket again.',
            ),
          ),
        );
        return;
      }
      await _review(
        updated,
        _ticketReadiness(updated),
        conflictedPullRequest: conflictedPullRequest,
        initialResponse: result.response,
      );
      return;
    }
    await _setActivation(ticket, ready: true, response: result.response);
  }

  Future<void> _delete(WorkshopTicket ticket) async {
    final projectId = _projectId;
    if (projectId == null || ticket.agentReady || ticket.agentWorking) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => WorkshopTicketDeleteDialog(ticket: ticket),
    );
    if (confirmed != true || !mounted) return;
    _update(() => _busyTicketIds.add(ticket.itemId));
    try {
      await widget.controller.api.delete(
        'v1/workspaces/${widget.controller.workspace!.id}/tickets/${ticket.number}',
        body: {
          'repository': ticket.repository,
          'projectId': projectId,
          'itemId': ticket.itemId,
        },
      );
      if (!mounted) return;
      _notify(ticketId: null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ticket.issueOpen
                ? 'Ticket #${ticket.number} deleted from this Workshop. The GitHub issue was closed.'
                : 'Ticket #${ticket.number} deleted from this Workshop.',
          ),
        ),
      );
      await _load();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) _update(() => _busyTicketIds.remove(ticket.itemId));
    }
  }

  Future<void> _pause(WorkshopTicket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel deployment?'),
        content: Text(
          'Ticket #${ticket.number} stays in the workshop, but it will leave the runner queue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel deployment'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _setActivation(ticket, ready: false);
    }
  }

  Future<void> _setActivation(
    WorkshopTicket ticket, {
    required bool ready,
    String response = '',
  }) async {
    if (ready) {
      final projectId = _projectId;
      if (projectId == null) return;
      try {
        await _deployment.deploy(
          workspaceId: widget.controller.workspace!.id,
          projectId: projectId,
          ticket: ticket,
          response: response,
        );
        await _load();
      } on Object catch (error) {
        if (mounted) showFailure(context, error);
      } finally {
        if (mounted) _deployment.confirm(ticket.itemId);
      }
      return;
    }
    _update(() => _busyTicketIds.add(ticket.itemId));
    try {
      await widget.controller.api.patch(
        'v1/workspaces/${widget.controller.workspace!.id}/projects/items/${ticket.itemId}/agent-activation',
        body: {
          'projectId': _projectId,
          'repository': ticket.repository,
          'ready': false,
        },
      );
      await _load();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) _update(() => _busyTicketIds.remove(ticket.itemId));
    }
  }

  Future<bool> _setStatus(WorkshopTicket ticket, String optionId) async {
    final fieldId = _statusField?['id'] as String?;
    if (fieldId == null) return false;
    _update(() => _busyTicketIds.add(ticket.itemId));
    try {
      await widget.controller.api.patch(
        'v1/workspaces/${widget.controller.workspace!.id}/projects/items/${ticket.itemId}',
        body: {
          'projectId': _projectId,
          'repository': ticket.repository,
          'fieldId': fieldId,
          'value': {'singleSelectOptionId': optionId},
        },
      );
      await _load();
      return true;
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
      return false;
    } finally {
      if (mounted) _update(() => _busyTicketIds.remove(ticket.itemId));
    }
  }
}
