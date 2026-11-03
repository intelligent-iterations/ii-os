import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ii_ffmpeg_universal/ii_ffmpeg_universal.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show ErrorSurface, GhostModeControl;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:stacked/stacked.dart';
import 'package:uuid/uuid.dart';

import '../services/editor_media_source.dart';
import '../services/editor_media_import_batch.dart';
import '../services/editor_renderer.dart';
import '../services/generated_editor_media.dart';
import '../services/local_editor_export.dart';
import '../services/local_editor_file_saver.dart';
import '../services/source_asset_uploader.dart';
import '../services/video_editor_ffmpeg.dart';
import '../services/video_editor_export_recovery.dart';
import '../services/video_editor_project.dart';
import '../services/video_editor_render_readiness.dart';
import '../services/video_project_media_gateway.dart';
import '../repositories/editor_render_repository.dart';
import '../repositories/source_asset_repository.dart';
import '../repositories/video_project_repository.dart';
import '../services/editor_render_dispatcher.dart';
import '../services/editor_render_status_watcher.dart';
import '../view_models/video_editor_projects_view_model.dart';
import '../models/minimax_h3_generation_spec.dart';
import '../models/picked_media.dart';
import '../models/editor_export_target.dart';
import '../models/video_project.dart';
import '../models/workshop_ticket_draft.dart';
import '../navigation/app_route_state.dart';
import '../state/app_controller.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';
import '../widgets/media_picker.dart';
import '../widgets/local_editor_export_preview.dart';
import '../widgets/local_video_preview.dart';
import '../widgets/video_editor_controls.dart';
import '../widgets/video_editor_header.dart';
import '../widgets/video_editor_stage.dart';
import '../widgets/video_project_history.dart';
import '../widgets/video_project_picker.dart';
import '../widgets/video_editor_progress_surface.dart';
import 'video_project_open_presentation.dart';

part 'video_editor_screen_output.dart';
part 'video_editor_screen_import.dart';

enum _OutputPhase { idle, rendering, uploading, ready, failed }

final class VideoEditorScreen extends StatelessWidget {
  const VideoEditorScreen({
    required this.controller,
    this.ghostMode = false,
    this.onGhostModeChanged,
    super.key,
  });

  final AppController controller;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<VideoEditorProjectsViewModel>.reactive(
      viewModelBuilder: () => VideoEditorProjectsViewModel(
        projects: VideoProjectApiRepository(controller.api),
        mediaGateway: WorkspaceVideoProjectMediaGateway(
          sourceAssets: SourceAssetApiRepository(controller.api),
          media: controller.media,
        ),
        renderDispatcher: WorkspaceEditorRenderDispatcher(
          renders: EditorRenderApiRepository(controller.api),
          sourceAssets: SourceAssetApiRepository(controller.api),
          compiler: videoEditorCompiler,
        ),
        renderWatcher: PollingEditorRenderStatusWatcher(
          EditorRenderApiRepository(controller.api),
        ),
        workspaceId: controller.workspace?.id ?? '',
        expectedBucket: controller.connection?.bucket ?? '',
        renderReadiness: videoEditorRenderReadiness,
        ghostMode: ghostMode,
      ),
      onViewModelReady: (model) => model.load(),
      builder: (context, model, _) => _VideoEditorSurface(
        controller: controller,
        projects: model,
        ghostMode: ghostMode,
        onGhostModeChanged: onGhostModeChanged,
      ),
    );
  }
}

final class _VideoEditorSurface extends StatefulWidget {
  const _VideoEditorSurface({
    required this.controller,
    required this.projects,
    required this.ghostMode,
    this.onGhostModeChanged,
  });

  final AppController controller;
  final VideoEditorProjectsViewModel projects;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;

  @override
  State<_VideoEditorSurface> createState() => _VideoEditorScreenState();
}

final class _VideoEditorScreenState extends State<_VideoEditorSurface> {
  static const _uuid = Uuid();

  UniversalFfmpeg? _ffmpeg;
  final VideoProjectOpenPresentation _openPresentation =
      VideoProjectOpenPresentation();
  Map<String, LocalEditorMedia> get _media => _openPresentation.media;
  Map<String, VideoProjectMediaOrigin> get _mediaOrigins =>
      _openPresentation.mediaOrigins;
  MediaTime _playhead = MediaTime.zero;
  EditorSelection? _selection;
  EditorRenderCancellationToken? _cancellation;
  Future<void>? _activeRenderSettled;
  LocalEditorExportArtifact? _artifact;
  Uint8List? _renderedBytes;
  _OutputPhase _phase = _OutputPhase.idle;
  String _stage = '';
  String? _outputError;
  double? _progress;
  bool _importing = false;
  bool _savingCopy = false;
  int _videoBitrate = 4 * 1000 * 1000;
  EditorExportTarget _exportTarget = EditorExportTarget.thisDevice;

  EditorProject? get _project => widget.projects.timeline;

  bool get _busy =>
      _importing ||
      widget.projects.isOpening ||
      widget.projects.isSaving ||
      widget.projects.isDeleting ||
      widget.projects.isDispatching ||
      widget.projects.isPersistingRender ||
      _phase == _OutputPhase.rendering ||
      _phase == _OutputPhase.uploading;

  @override
  void dispose() {
    final engine = _ffmpeg;
    final cancellation = _cancellation;
    final activeRender = _activeRenderSettled;
    final artifact = _artifact;
    final cleanup = <Future<void>>[
      if (engine != null)
        disposeEditorEngineAfterActiveRender(
          engine: engine,
          cancellation: cancellation,
          activeRender: activeRender,
        ),
      if (artifact != null) artifact.dispose(),
    ];
    if (cleanup.isNotEmpty) {
      unawaited(
        Future.wait<void>(cleanup).then<void>((_) {}).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'ii-os local video editor',
              context: ErrorDescription('while releasing local media'),
            ),
          );
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return PageFrame(
      title: 'Local video editor',
      subtitle: widget.ghostMode
          ? 'Cut, layer, caption, and compress locally; the final video stays on this device.'
          : 'Cut, layer, caption, and compress on this device; only the final video uploads directly to workspace GCS.',
      actions: [
        if (widget.onGhostModeChanged != null)
          GhostModeControl(
            key: const Key('generation-ghost-mode'),
            enabled: widget.ghostMode,
            onChanged: widget.onGhostModeChanged!,
          ),
        VideoEditorMediaButton(
          importing: _importing,
          onPressed: _busy ? null : _importMedia,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VideoEditorHeader(
            project: widget.projects.current?.summary,
            unsavedChanges: widget.projects.unsavedChanges.length,
            saving: widget.projects.isSaving,
            canUndo: widget.projects.canUndo && !_busy,
            canRedo: widget.projects.canRedo && !_busy,
            failure: widget.projects.failure,
            renderingInWorkspace: widget.projects.renderJobId != null,
            onUndo: _undoEdit,
            onRedo: _redoEdit,
            onSave: _busy || _project == null ? null : _saveProject,
            onOpen: _showProjectPicker,
            onNew: _startProject,
            onHistory: widget.projects.current == null
                ? null
                : _showProjectHistory,
            onDismissFailure: widget.projects.clearFailure,
            onOpenLibrary: _openMediaLibrary,
          ),
          IiOsGap.vSm,
          VideoEditorSummary(
            sourceCount: _media.length,
            duration: project?.duration ?? MediaTime.zero,
            bitrate: _videoBitrate,
            enabled: !_busy,
            onBitrateChanged: _setBitrate,
            exportTarget: _exportTarget,
            onExportTargetChanged: (value) =>
                setState(() => _exportTarget = value),
            workspaceRenderAvailable: widget.projects.canRenderOnWorkspace,
          ),
          IiOsGap.vSm,
          if (project == null)
            VideoEditorEmptyStage(ghostMode: widget.ghostMode)
          else
            VideoEditorStage(
              project: project,
              playhead: _playhead,
              selection: _selection,
              busy: _busy,
              canUndo: widget.projects.canUndo,
              onUndoRequested: _undoEdit,
              onProjectChanged: _acceptProject,
              onPlayheadChanged: (value) => setState(() => _playhead = value),
              onSelectionChanged: (value) => setState(() => _selection = value),
              onAddCaptionRequested: _addCaption,
              onRenderRequested: _render,
              onEditError: (error) => showFailure(context, error),
              previewBuilder: (context, project, playhead, selection) =>
                  _outputSurface(project, playhead),
            ),
          IiOsGap.vSm,
          Text(
            'Local limits: $editorLocalLimitsDescription',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  UniversalFfmpeg get _engine => _ffmpeg ??= createVideoEditorFfmpeg();

  void _updateFromImport(VoidCallback update) => setState(update);

  void _refresh(VoidCallback update) => setState(update);

  void _acceptProject(EditorProject project) {
    if (_busy) return;
    widget.projects.applyTimeline(project);
    setState(() {
      _dropOutput();
      _phase = _OutputPhase.idle;
      _outputError = null;
    });
  }

  void _setBitrate(int value) {
    final project = _project;
    try {
      final next = project == null
          ? null
          : withEditorVideoBitrate(project, value);
      if (next != null) widget.projects.applyTimeline(next);
      setState(() {
        _dropOutput();
        _videoBitrate = value;
        _phase = _OutputPhase.idle;
        _outputError = null;
      });
    } on Object catch (error) {
      showFailure(context, error);
    }
  }

  Future<void> _addCaption() async {
    final requestedPlayhead = _playhead;
    try {
      await runEditorAdditionRequest<EditorCaptionRequest>(
        request: () => showEditorCaptionDialog(context),
        currentProject: () => _project,
        unavailable: () => !mounted || _busy,
        buildCandidate: (project, request) => addEditorCaption(
          project: project,
          playhead: requestedPlayhead,
          laneId: 'caption-lane-${_uuid.v4()}',
          clipId: 'caption-clip-${_uuid.v4()}',
          text: request.text,
          subtitle: request.subtitle,
        ),
        admit: widget.projects.applyStructurallyFeasibleAddition,
        onAccepted: () => setState(() {
          _dropOutput();
          _phase = _OutputPhase.idle;
          _outputError = null;
        }),
      );
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _render() async {
    final project = _project;
    if (project == null || _busy) return;
    if (_exportTarget == EditorExportTarget.workspaceMachine) {
      return _renderInWorkspace();
    }
    final engine = widget.projects.afterLocalRenderAdmission(() => _engine);
    if (engine == null) return;
    _cancellation?.cancel();
    final cancellation = EditorRenderCancellationToken();
    _cancellation = cancellation;
    final prior = _artifact;
    setState(() {
      _artifact = null;
      _renderedBytes = null;
      _phase = _OutputPhase.rendering;
      _stage = 'Preparing local media\u2026';
      _progress = null;
      _outputError = null;
    });
    await Future<void>.delayed(Duration.zero);
    await prior?.dispose();
    Future<void>? renderSettled;
    try {
      final renderOperation =
          EditorRenderer(engine: engine, compiler: videoEditorCompiler).render(
            project,
            cancellation: cancellation,
            onStage: (stage) {
              if (!mounted || !identical(_cancellation, cancellation)) return;
              setState(() {
                _stage = switch (stage) {
                  EditorRenderStage.preparingLocalMedia =>
                    'Preparing local media\u2026',
                  EditorRenderStage.renderingMedia =>
                    'Rendering and compressing on this device\u2026',
                };
              });
            },
            onProgress: (progress) {
              if (!mounted || !identical(_cancellation, cancellation)) return;
              setState(() => _progress = progress.fraction);
            },
          );
      renderSettled = renderOperation.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _activeRenderSettled = renderSettled;
      final result = await renderOperation;
      final bytes = result.outputBytes;
      if (!result.isSuccess || bytes == null) {
        throw StateError(_localExportFailure(result.engineResult));
      }
      final artifact = await LocalEditorExportArtifact.create(
        bytes: bytes,
        duration: Duration(microseconds: project.duration.microseconds),
        contentType: result.mediaType,
      );
      if (cancellation.isCancelled || !identical(_cancellation, cancellation)) {
        await artifact.dispose();
        throw const EditorRenderCancelledException();
      }
      if (!mounted) {
        await artifact.dispose();
        return;
      }
      setState(() {
        _artifact = artifact;
        _renderedBytes = bytes;
      });
      if (widget.ghostMode) {
        setState(() {
          _phase = _OutputPhase.ready;
          _stage = 'Kept only on this device.';
          _progress = 1;
        });
      } else {
        await _uploadRendered();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _OutputPhase.failed;
        _outputError = error is EditorRenderCancelledException
            ? 'Local rendering was cancelled.'
            : '$error';
      });
    } finally {
      if (identical(_activeRenderSettled, renderSettled)) {
        _activeRenderSettled = null;
      }
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  Future<void> _uploadRendered() async {
    final bytes = _renderedBytes;
    final artifact = _artifact;
    if (bytes == null || artifact == null || _phase == _OutputPhase.uploading) {
      return;
    }
    setState(() {
      _phase = _OutputPhase.uploading;
      _stage = 'Uploading directly to the workspace GCS bucket\u2026';
      _progress = null;
      _outputError = null;
    });
    try {
      final extension = switch (artifact.contentType) {
        'video/mp4' => 'mp4',
        'video/webm' => 'webm',
        _ => throw StateError(
          'Unsupported local editor output type: ${artifact.contentType}',
        ),
      };
      final assetId = await SourceAssetUploader(widget.controller.api).upload(
        workspaceId: widget.controller.workspace!.id,
        expectedBucket: widget.controller.connection?.bucket ?? '',
        filename: 'ii-os-local-edit-${_uuid.v4()}.$extension',
        bytes: bytes,
        contentType: artifact.contentType,
      );
      if (!mounted || !identical(artifact, _artifact)) return;
      artifact.attachAssetId(assetId);
      setState(() {
        _phase = _OutputPhase.ready;
        _stage = 'Uploaded directly to workspace storage.';
        _progress = 1;
      });
    } on Object catch (error) {
      if (mounted && identical(artifact, _artifact)) {
        setState(() {
          _phase = _OutputPhase.failed;
          _outputError = '$error';
        });
      }
    }
  }

  Future<void> _saveRendered() async {
    final bytes = _renderedBytes;
    final artifact = _artifact;
    if (bytes == null || artifact == null || _savingCopy) return;
    setState(() => _savingCopy = true);
    try {
      final saved = await saveLocalEditorVideo(
        bytes: bytes,
        contentType: artifact.contentType,
        name: 'ii-os-edited-video',
      );
      if (saved == null) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved a local video copy.')),
        );
      }
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _savingCopy = false);
    }
  }

  void _openInH3(MiniMaxH3GenerationMode mode) {
    final artifact = _artifact;
    final assetId = artifact?.assetId;
    if (artifact == null || assetId == null || assetId.isEmpty) {
      showFailure(
        context,
        const FormatException(
          'Export and upload this edit before sending it to MiniMax H3.',
        ),
      );
      return;
    }
    if (artifact.duration < const Duration(seconds: 2) ||
        artifact.duration > const Duration(seconds: 15)) {
      showFailure(
        context,
        const FormatException(
          'MiniMax H3 source videos must be between 2 and 15 seconds. Trim '
          'this timeline and export it again.',
        ),
      );
      return;
    }
    final workspaceId = widget.controller.workspace?.id;
    if (workspaceId == null || workspaceId.isEmpty) return;
    context.go(
      AppRouteState(
        workspaceId: workspaceId,
        page: AppPage.videoGeneration,
        query: {'mode': mode.wireValue, 'source': assetId},
      ).location,
    );
  }

  void _cancelRender() {
    _stage = 'Cancelling local render\u2026';
    _cancellation?.cancel();
    setState(() {});
  }

  void _dropOutput() {
    final artifact = _artifact;
    _artifact = null;
    _renderedBytes = null;
    if (artifact != null) {
      unawaited(
        Future<void>.delayed(Duration.zero).then((_) => artifact.dispose()),
      );
    }
  }
}

/// Builds the operator-facing reason a local export stopped.
///
/// FFmpeg writes its version and build configuration banner first, so the
/// leading log lines are always boilerplate and never the cause. The cause is
/// at the tail. Cancellation and timeouts also surface as exit code 255, so
/// they are reported as themselves instead of as an engine failure.
String _localExportFailure(FfmpegResult result) {
  if (result.cancelled) return 'Local rendering was cancelled.';

  const tailLines = 8;
  final logs = result.logs;
  final tail = logs.length <= tailLines
      ? logs
      : logs.sublist(logs.length - tailLines);
  final detail = tail.isEmpty
      ? 'The engine produced no logs.'
      : tail.join(' | ');

  if (result.timedOut) {
    return 'Local FFmpeg export timed out after '
        '${result.elapsed.inSeconds}s: $detail';
  }
  return 'Local FFmpeg export failed (${result.exitCode}): $detail';
}
