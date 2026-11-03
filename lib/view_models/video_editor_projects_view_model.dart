import 'dart:async';

import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:stacked/stacked.dart';

import '../models/editor_change_description.dart';
import '../models/editor_timeline_codec.dart';
import '../models/editor_timeline_migrations.dart';
import '../models/video_project.dart';
import '../repositories/video_project_repository.dart';
import '../services/editor_media_source.dart';
import '../services/editor_render_dispatcher.dart';
import '../services/editor_render_publisher.dart';
import '../services/editor_render_status_watcher.dart';
import '../services/video_editor_ffmpeg.dart';
import '../services/video_editor_render_readiness.dart';
import '../services/video_project_media_gateway.dart';

part 'video_editor_workspace_render.dart';
part 'video_editor_render_feasibility.dart';
part 'video_editor_project_open.dart';
part 'video_editor_project_lifecycle.dart';

abstract final class VideoProjectBusy {
  static const list = 'video-project-list';
  static const open = 'video-project-open';
  static const save = 'video-project-save';
  static const delete = 'video-project-delete';
  static const dispatch = 'video-project-dispatch';
  static const persistRender = 'video-project-persist-render';
}

/// How many steps back a person can go before the editor stops remembering.
const videoEditorUndoDepth = 60;

/// Owns which project is open, what has changed in it, and how it is saved.
///
/// The timeline lives here rather than on the screen so that undo, save, and
/// the history a project carries are all reachable from a test without
/// rendering anything.
final class VideoEditorProjectsViewModel extends BaseViewModel {
  VideoEditorProjectsViewModel({
    required VideoProjectRepository projects,
    required VideoProjectMediaGateway mediaGateway,
    required String workspaceId,
    required String expectedBucket,
    required EditorRenderStatusWatcher renderWatcher,
    EditorRenderDispatcher? renderDispatcher,
    VideoEditorRenderReadinessService? renderReadiness,
    bool ghostMode = false,
  }) : this._(
         projects,
         mediaGateway,
         renderDispatcher,
         renderWatcher,
         renderReadiness ?? videoEditorRenderReadiness,
         workspaceId: workspaceId,
         expectedBucket: expectedBucket,
         ghostMode: ghostMode,
       );

  VideoEditorProjectsViewModel._(
    this._projects,
    this._mediaGateway,
    this._renderDispatcher,
    this._renderWatcher,
    this._renderReadiness, {
    required this.workspaceId,
    required this.expectedBucket,
    required this.ghostMode,
  });

  final VideoProjectRepository _projects;
  final VideoProjectMediaGateway _mediaGateway;
  final EditorRenderDispatcher? _renderDispatcher;
  final EditorRenderStatusWatcher _renderWatcher;
  final VideoEditorRenderReadinessService _renderReadiness;
  final String workspaceId;
  final String expectedBucket;
  final bool ghostMode;

  final List<EditorProject> _undo = [];
  final List<EditorProject> _redo = [];
  final List<String> _pending = [];

  List<VideoProjectSummary> _saved = const [];
  VideoProject? _open;
  EditorProject? _timeline;
  String? _failure;
  String? _renderFeasibilityFailure;
  EditorRenderFeasibility? _renderFeasibility;
  String? _listFailure;
  String? _renderJobId;
  var _renderJobGeneration = 0;
  Future<void> _projectWriteTail = Future<void>.value();
  bool _dirty = false;
  EditorRenderCapability _renderCapability = const EditorRenderCapability(
    EditorRenderCapabilityStatus.unknown,
  );

  /// Every project in this workspace, newest change first.
  List<VideoProjectSummary> get saved => _saved;

  /// The project being edited, or null while the editor is on a scratch
  /// timeline that has never been named.
  VideoProject? get current => _open;

  /// What the person will be shown if something they asked for went wrong,
  /// already written as a sentence.
  String? get failure => _failure ?? _renderFeasibilityFailure;

  /// The latest pure target accounting for the in-memory timeline.
  EditorRenderFeasibility? get renderFeasibility => _renderFeasibility;

  /// Why the project list is unavailable. This one belongs beside the list
  /// rather than on the page: nobody asked for it, so it must not take over
  /// the editor before any work has started.
  String? get listFailure => _listFailure;

  EditorProject? get timeline => _timeline;

  bool get isDirty => _dirty;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  bool get isSaving => busy(VideoProjectBusy.save);

  bool get isDeleting => busy(VideoProjectBusy.delete);

  /// Whether this workspace can hand an export to one of its own machines.
  bool get canRenderOnWorkspace =>
      _renderDispatcher != null && _renderCapability.isAvailable;

  bool get isDispatching => busy(VideoProjectBusy.dispatch);

  bool get isPersistingRender => busy(VideoProjectBusy.persistRender);

  bool get _hasProjectOperation =>
      isOpening ||
      isSaving ||
      isDeleting ||
      isDispatching ||
      isPersistingRender;

  /// The job now rendering this edit somewhere other than here.
  ///
  /// Opening a project copies its persisted job id here and immediately
  /// re-arms the completion watcher, so closing the tab does not lose work.
  String? get renderJobId => _renderJobId;

  bool get isOpening => busy(VideoProjectBusy.open);

  /// The changes made since the last save, newest last.
  List<String> get unsavedChanges => List.unmodifiable(_pending);

  /// The project's own history, plus anything not saved yet.
  List<VideoProjectChange> get history => _open?.history ?? const [];

  Future<void> load() async {
    _listFailure = null;
    setBusyForObject(VideoProjectBusy.list, true);
    try {
      final listing = await _projects.list(workspaceId);
      _saved = listing.projects;
      _renderCapability = listing.renderCapability;
    } on Object {
      _listFailure =
          'The projects saved in this workspace could not be listed.';
    } finally {
      setBusyForObject(VideoProjectBusy.list, false);
    }
  }

  /// Records a timeline the editor produced and names what changed.
  void applyTimeline(EditorProject next) {
    if (isOpening || isSaving) return;
    final previous = _timeline;
    if (previous != null) {
      if (identical(previous, next)) return;
      _undo.add(previous);
      if (_undo.length > videoEditorUndoDepth) _undo.removeAt(0);
      _redo.clear();
      _pending.add(describeEditorChange(previous, next));
      if (_pending.length > videoEditorUndoDepth) _pending.removeAt(0);
    } else {
      _pending.add('Started a timeline');
    }
    _timeline = next;
    _dirty = true;
    _refreshRenderFeasibility();
    notifyListeners();
  }

  /// Puts a timeline in place without treating it as an edit.
  void adoptTimeline(EditorProject? next, {bool dirty = false}) {
    if (isOpening || isSaving) return;
    _adoptTimeline(next, dirty: dirty);
  }

  void _adoptTimeline(EditorProject? next, {bool dirty = false}) {
    _timeline = next;
    _undo.clear();
    _redo.clear();
    _pending.clear();
    _dirty = dirty;
    _refreshRenderFeasibility();
    notifyListeners();
  }

  EditorProject? undo() {
    if (isOpening || isSaving) return null;
    if (_undo.isEmpty) return null;
    final previous = _undo.removeLast();
    final current = _timeline;
    if (current != null) _redo.add(current);
    if (_pending.isNotEmpty) _pending.removeLast();
    _timeline = previous;
    _dirty = true;
    _refreshRenderFeasibility();
    notifyListeners();
    return previous;
  }

  EditorProject? redo() {
    if (isOpening || isSaving) return null;
    if (_redo.isEmpty) return null;
    final next = _redo.removeLast();
    final current = _timeline;
    if (current != null) _undo.add(current);
    _pending.add(describeEditorChange(current ?? next, next));
    _timeline = next;
    _dirty = true;
    _refreshRenderFeasibility();
    notifyListeners();
    return next;
  }

  Future<VideoProject?> createProject({String? name}) async {
    if (_hasProjectOperation) return null;
    if (_timeline != null &&
        !requireStructurallyFeasible(VideoEditorRenderIntent.save)) {
      return null;
    }
    _failure = null;
    final openAtStart = _open;
    final timelineAtStart = _timeline;
    setBusyForObject(VideoProjectBusy.save, true);
    try {
      final created = await _projects.create(workspaceId, name: name);
      if (!identical(_open, openAtStart) ||
          !identical(_timeline, timelineAtStart)) {
        _failure = 'The editor changed while that project was being created.';
        return null;
      }
      _open = created;
      _replaceRenderJob(created.summary.renderJobId);
      _saved = [created.summary, ..._saved];
      _dirty = _timeline != null;
      notifyListeners();
      return created;
    } on Object {
      _failure = 'That project could not be created.';
      return null;
    } finally {
      setBusyForObject(VideoProjectBusy.save, false);
    }
  }

  /// Writes the open project. Returns false and leaves [failure] set when the
  /// write did not happen.
  Future<bool> save({
    required List<LocalEditorMedia> media,
    Map<String, VideoProjectMediaOrigin> origins = const {},
    String? name,
  }) async {
    if (_hasProjectOperation) return false;
    final project = _open;
    final timeline = _timeline;
    if (project == null || timeline == null) {
      _failure = 'Add some media before saving this project.';
      notifyListeners();
      return false;
    }
    if (!requireStructurallyFeasible(VideoEditorRenderIntent.save)) {
      return false;
    }
    _failure = null;
    setBusyForObject(VideoProjectBusy.save, true);
    try {
      return await _serializeProjectWrite(() async {
        final renderGeneration = _renderJobGeneration;
        final records = await _mediaGateway.publish(
          workspaceId: workspaceId,
          expectedBucket: expectedBucket,
          media: media,
          knownOrigins: origins,
          alreadyStored: {for (final item in project.media) item.id: item},
          ghostMode: ghostMode,
        );
        final saved = await _projects.save(
          workspaceId: workspaceId,
          projectId: project.id,
          timeline: encodeEditorTimeline(timeline),
          media: records,
          change: _changeSummary(),
          revision: project.revision,
          name: name,
        );
        if (!identical(_open, project) || !identical(_timeline, timeline)) {
          _failure = 'The editor changed while this project was being saved.';
          return false;
        }
        _open = saved;
        if (_renderJobGeneration == renderGeneration) {
          _renderJobId = saved.summary.renderJobId;
        }
        _saved = [
          saved.summary,
          ..._saved.where((entry) => entry.id != saved.id),
        ];
        _pending.clear();
        _dirty = false;
        return true;
      });
    } on VideoProjectConflict {
      _failure =
          'Someone else saved this project while you were working. Open it '
          'again to pick up their version.';
      return false;
    } on Object {
      _failure = 'This project could not be saved.';
      return false;
    } finally {
      setBusyForObject(VideoProjectBusy.save, false);
    }
  }

  void clearFailure() {
    if (_failure == null && _renderFeasibilityFailure == null) return;
    if (_failure != null) {
      _failure = null;
    } else {
      _renderFeasibilityFailure = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _renderWatcher.dispose();
    super.dispose();
  }

  String _changeSummary() {
    if (_pending.isEmpty) return 'Saved the project';
    if (_pending.length == 1) return _pending.single;
    final last = _pending.last;
    return '$last, and ${_pending.length - 1} more '
        '${_pending.length == 2 ? 'change' : 'changes'}';
  }
}
