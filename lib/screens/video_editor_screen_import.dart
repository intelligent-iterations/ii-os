part of 'video_editor_screen.dart';

extension _VideoEditorActions on _VideoEditorScreenState {
  Future<void> _importMedia() async {
    const mediaTypes = XTypeGroup(
      label: 'Video, audio, and images',
      extensions: [
        'mp4',
        'm4a',
        'webm',
        'mp3',
        'wav',
        'flac',
        'jpg',
        'jpeg',
        'png',
        'webp',
      ],
      mimeTypes: [
        'video/mp4',
        'audio/mp4',
        'video/webm',
        'audio/mpeg',
        'audio/wav',
        'audio/flac',
        'image/jpeg',
        'image/png',
        'image/webp',
      ],
    );
    final workspace = widget.controller.workspace;
    final connection = widget.controller.connection;
    if (workspace == null ||
        connection == null ||
        !connection.isBoundTo(
          workspaceId: workspace.id,
          organizationId: workspace.organizationId,
        ) ||
        connection.bucket.isEmpty ||
        _busy ||
        !widget.controller.can('jobs.read')) {
      return;
    }
    final history = widget.controller.media.history(
      workspaceId: workspace.id,
      retentionDays: workspace.artifactStorage?.retentionDays ?? 30,
    );
    final picked = await showMediaPickerMultiple(
      context: context,
      history: history,
      title: 'Add media',
      uploadTypes: const [mediaTypes],
      maxUploadBytes: maxEditorSourceBytes,
      maxTotalUploadBytes: maxEditorTotalSourceBytes,
      loadPreview: (entry) => widget.controller.readVerifiedArtifact(
        workspaceId: workspace.id,
        jobId: entry.jobId,
        artifact: entry.previewArtifact ?? entry.artifact,
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    _updateFromImport(() => _importing = true);
    try {
      await runEditorMediaImportBatch(
        choices: picked,
        captureTimelineStart: () => _playhead,
        importChoice: (choice, start) =>
            _importChoice(choice, workspace.id, connection.bucket, start),
      );
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) _updateFromImport(() => _importing = false);
    }
  }

  Future<bool> _importChoice(
    PickedMedia choice,
    String workspaceId,
    String expectedBucket,
    MediaTime timelineStart,
  ) async {
    if (!choice.isFromLibrary) {
      return _addMediaBytes(
        filename: choice.upload!.name,
        path: choice.upload!.path,
        bytes: choice.bytes!,
        timelineStart: timelineStart,
      );
    }
    final entry = choice.entry!;
    final grant = await widget.controller.readArtifactUrl(
      workspaceId: workspaceId,
      jobId: entry.jobId,
      artifact: entry.artifact,
    );
    final downloaded = await downloadGeneratedEditorMedia(
      api: widget.controller.api,
      grant: grant,
      entry: entry,
      workspaceId: workspaceId,
      expectedBucket: expectedBucket,
    );
    return _addMediaBytes(
      filename: downloaded.filename,
      path: '',
      bytes: downloaded.bytes,
      expectedContentType: downloaded.contentType,
      timelineStart: timelineStart,
      // Generated media is already in this workspace. The project will hold
      // it where it is rather than storing a second copy of the same bytes.
      origin: WorkspaceArtifactOrigin(
        jobId: entry.jobId,
        path: entry.objectName,
        generation: entry.generationId,
        sizeBytes: (entry.artifact['size_bytes'] as num?)?.toInt() ?? 0,
        sha256: '${entry.artifact['sha256']}'.toLowerCase(),
        contentType: entry.contentType,
      ),
    );
  }

  Future<bool> _addMediaBytes({
    required String filename,
    required String path,
    required Uint8List bytes,
    required MediaTime timelineStart,
    String? expectedContentType,
    VideoProjectMediaOrigin? origin,
  }) async {
    final priorTotal = _media.values.fold<int>(
      0,
      (sum, item) => sum + item.bytes.length,
    );
    if (bytes.isEmpty ||
        bytes.length > maxEditorSourceBytes ||
        priorTotal + bytes.length > maxEditorTotalSourceBytes) {
      throw const FormatException(
        'The selected media exceeds the local editor byte limits.',
      );
    }
    final id = 'media-${_VideoEditorScreenState._uuid.v4()}';
    final media = await prepareLocalEditorMedia(
      ffmpeg: _engine,
      id: id,
      filename: filename,
      path: path,
      bytes: bytes,
      expectedContentType: expectedContentType,
    );
    if (priorTotal + media.bytes.length > maxEditorTotalSourceBytes) {
      throw const FormatException(
        'Preparing this media would exceed the local editor byte limits.',
      );
    }
    if (!mounted) return false;
    final project = addLocalMediaToNewLanes(
      projectId: 'ii-os-${_VideoEditorScreenState._uuid.v4()}',
      project: _project,
      media: media,
      videoLaneId: 'video-lane-${_VideoEditorScreenState._uuid.v4()}',
      audioLaneId: 'audio-lane-${_VideoEditorScreenState._uuid.v4()}',
      videoClipId: 'video-clip-${_VideoEditorScreenState._uuid.v4()}',
      audioClipId: 'audio-clip-${_VideoEditorScreenState._uuid.v4()}',
      linkGroupId: 'link-${_VideoEditorScreenState._uuid.v4()}',
      timelineStart: timelineStart,
      videoBitrate: _videoBitrate,
    );
    if (!widget.projects.applyStructurallyFeasibleAddition(project)) {
      return false;
    }
    _media[id] = media;
    if (origin != null) _mediaOrigins[id] = origin;
    _updateFromImport(() {
      _dropOutput();
      _phase = _OutputPhase.idle;
      _outputError = null;
    });
    return true;
  }

  void _undoEdit() {
    if (_busy || widget.projects.undo() == null) return;
    _afterTimelineReplaced();
  }

  void _redoEdit() {
    if (_busy || widget.projects.redo() == null) return;
    _afterTimelineReplaced();
  }

  /// Brings the page back in line with a timeline that was replaced whole.
  void _afterTimelineReplaced() {
    final project = _project;
    _refresh(() {
      _dropOutput();
      _selection = null;
      _phase = _OutputPhase.idle;
      _outputError = null;
      if (project == null) {
        _playhead = MediaTime.zero;
      } else if (_playhead > project.duration) {
        _playhead = project.duration;
      }
    });
  }

  Future<void> _saveProject() async {
    final projects = widget.projects;
    if (!projects.requireStructurallyFeasible(VideoEditorRenderIntent.save)) {
      return;
    }
    if (projects.current == null) {
      final created = await projects.createProject(name: _suggestedName());
      if (created == null || !mounted) return;
    }
    await projects.save(media: _media.values.toList(growable: false));
    if (!mounted) return;
    if (projects.failure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${projects.current?.name ?? 'project'}.'),
        ),
      );
    }
  }

  String _suggestedName() {
    final first = _media.values.isEmpty ? null : _media.values.first.filename;
    if (first == null || first.trim().isEmpty) return 'Untitled project';
    final stem = first.split('.').first.trim();
    return stem.isEmpty ? 'Untitled project' : stem;
  }

  Future<void> _startProject() async {
    if (_busy) return;
    final keep = await _confirmLeavingUnsavedWork('Start a new project');
    if (!keep || !mounted) return;
    _openPresentation.clearIf(
      widget.projects.closeProject(),
      refresh: _refresh,
      afterTimelineReplaced: _afterTimelineReplaced,
    );
  }

  Future<void> _showProjectPicker() async {
    if (_busy) return;
    await widget.projects.load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.md),
          child: SingleChildScrollView(
            child: VideoProjectPicker(
              projects: widget.projects.saved,
              openProjectId: widget.projects.current?.id,
              loading: widget.projects.busy(VideoProjectBusy.list),
              failure: widget.projects.listFailure,
              onCreate: () {
                Navigator.of(sheetContext).pop();
                unawaited(_startProject());
              },
              onOpen: (project) {
                Navigator.of(sheetContext).pop();
                unawaited(_openProject(project.id));
              },
              onDelete: (project) {
                Navigator.of(sheetContext).pop();
                unawaited(_deleteProject(project.id));
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteProject(String projectId) async {
    final deletesOpenProject = widget.projects.current?.id == projectId;
    final deleted = await widget.projects.deleteProject(projectId);
    if (!mounted) return;
    _openPresentation.clearIf(
      deleted && deletesOpenProject,
      refresh: _refresh,
      afterTimelineReplaced: _afterTimelineReplaced,
    );
  }

  Future<void> _showProjectHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IiOsSpacing.md),
          child: SingleChildScrollView(
            child: VideoProjectHistory(
              saved: widget.projects.history,
              unsaved: widget.projects.unsavedChanges,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openProject(String projectId) async {
    final keep = await _confirmLeavingUnsavedWork('Open another project');
    if (!keep || !mounted) return;
    final result = await widget.projects.openProject(projectId);
    if (!mounted) return;
    _openPresentation.apply(
      result,
      refresh: _refresh,
      afterTimelineReplaced: _afterTimelineReplaced,
    );
  }

  Future<bool> _confirmLeavingUnsavedWork(String action) async {
    if (!widget.projects.isDirty) return true;
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('There are changes you have not saved'),
        content: Text(
          '$action will leave this timeline behind. Save it first if you '
          'want to come back to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            key: const ValueKey('video-project-discard'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// Hands this timeline to a workspace machine and says so.
  Future<void> _renderInWorkspace() async {
    final jobId = await widget.projects.renderOnWorkspace(
      origins: _mediaOrigins,
    );
    if (!mounted) return;
    if (jobId == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'A workspace machine is rendering this edit. It will appear in the '
          'media library when it is done, and you can close this tab.',
        ),
      ),
    );
  }

  /// Opens where a finished workspace render actually lands.
  void _openMediaLibrary() {
    final workspaceId = widget.controller.workspace?.id;
    if (workspaceId == null || workspaceId.isEmpty) return;
    context.go(
      AppRouteState(
        workspaceId: workspaceId,
        page: AppPage.videoGeneration,
      ).location,
    );
  }
}
