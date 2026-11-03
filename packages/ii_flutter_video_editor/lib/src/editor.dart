import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ii_flutter_video_editor/src/editor_builders.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/edits.dart';
import 'package:ii_flutter_video_editor/src/layer_edits.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/timeline_tools.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';
import 'package:ii_flutter_video_editor/src/transition_edits.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';
import 'package:ii_flutter_video_editor/src/widgets/clip_actions_sheet.dart';
import 'package:ii_flutter_video_editor/src/widgets/default_preview.dart';
import 'package:ii_flutter_video_editor/src/widgets/editor_helpers.dart';
import 'package:ii_flutter_video_editor/src/widgets/editor_toolbar.dart';
import 'package:ii_flutter_video_editor/src/widgets/lane_header.dart';
import 'package:ii_flutter_video_editor/src/widgets/timeline.dart';
import 'package:ii_flutter_video_editor/src/widgets/visual_transform_overlay.dart';

final class IiFlutterVideoEditor extends StatefulWidget {
  const IiFlutterVideoEditor({
    required this.project,
    required this.playhead,
    required this.selection,
    required this.onProjectChanged,
    required this.onPlayheadChanged,
    required this.onSelectionChanged,
    this.canUndo = false,
    this.onUndoRequested,
    this.previewBuilder,
    this.onRenderRequested,
    this.onAddCaptionRequested,
    this.onAddImageOverlayRequested,
    this.onEditError,
    this.builders = const EditorBuilders(),
    this.editorTheme,
    this.limits = const EditorLimits(),
    this.initialPixelsPerSecond = 60,
    this.minPixelsPerSecond = 12,
    this.maxPixelsPerSecond = 240,
    super.key,
  });

  final EditorProject project;
  final MediaTime playhead;
  final EditorSelection? selection;
  final ValueChanged<EditorProject> onProjectChanged;
  final ValueChanged<MediaTime> onPlayheadChanged;
  final ValueChanged<EditorSelection?> onSelectionChanged;
  final bool canUndo;
  final VoidCallback? onUndoRequested;
  final EditorPreviewBuilder? previewBuilder;
  final VoidCallback? onRenderRequested;
  final VoidCallback? onAddCaptionRequested;
  final VoidCallback? onAddImageOverlayRequested;
  final ValueChanged<EditorValidationException>? onEditError;
  final EditorBuilders builders;
  final EditorThemeData? editorTheme;
  final EditorLimits limits;
  final double initialPixelsPerSecond;
  final double minPixelsPerSecond;
  final double maxPixelsPerSecond;

  @override
  State<IiFlutterVideoEditor> createState() => _IiFlutterVideoEditorState();
}

final class _IiFlutterVideoEditorState extends State<IiFlutterVideoEditor> {
  static const _historyLimit = 50;

  late double _pixelsPerSecond;
  final FocusNode _editorFocusNode = FocusNode(debugLabel: 'video editor');
  final List<_EditorHistoryEntry> _undoHistory = [];
  EditorProject? _lastEmittedProject;
  bool _snappingEnabled = true;
  MediaTime? _spanStart;
  MediaTime? _spanEnd;
  MediaTime _transitionDuration = MediaTime.seconds(1);

  @override
  void initState() {
    super.initState();
    _pixelsPerSecond = widget.initialPixelsPerSecond.clamp(
      widget.minPixelsPerSecond,
      widget.maxPixelsPerSecond,
    );
  }

  @override
  void didUpdateWidget(IiFlutterVideoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minPixelsPerSecond != widget.minPixelsPerSecond ||
        oldWidget.maxPixelsPerSecond != widget.maxPixelsPerSecond) {
      _pixelsPerSecond = _pixelsPerSecond.clamp(
        widget.minPixelsPerSecond,
        widget.maxPixelsPerSecond,
      );
    }
    if (widget.onUndoRequested == null &&
        !identical(oldWidget.project, widget.project)) {
      if (!identical(widget.project, _lastEmittedProject)) {
        _undoHistory.clear();
      }
      _lastEmittedProject = null;
    }
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    validateEditorControlledState(
      project: widget.project,
      playhead: widget.playhead,
      selection: widget.selection,
      limits: widget.limits,
      initialPixelsPerSecond: widget.initialPixelsPerSecond,
      minPixelsPerSecond: widget.minPixelsPerSecond,
      maxPixelsPerSecond: widget.maxPixelsPerSecond,
    );
    final theme =
        widget.editorTheme ??
        EditorThemeData.fromColorScheme(Theme.of(context).colorScheme);
    validateEditorTheme(theme);
    final canRemove = canRemoveEditorClip(widget.project, widget.selection);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (_canUndo)
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        if (_canUndo)
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        if (canRemove)
          const SingleActivator(LogicalKeyboardKey.delete): _removeSelectedClip,
        if (canRemove)
          const SingleActivator(LogicalKeyboardKey.backspace):
              _removeSelectedClip,
      },
      child: Focus(
        focusNode: _editorFocusNode,
        autofocus: true,
        child: Material(
          color: theme.backgroundColor,
          child: Column(
            children: [
              _toolbar(theme),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _preview(context, theme),
                  ),
                ),
              ),
              Flexible(
                flex: 4,
                child: SingleChildScrollView(
                  child: EditorTimeline(
                    project: widget.project,
                    playhead: widget.playhead,
                    selection: widget.selection,
                    pixelsPerSecond: _pixelsPerSecond,
                    snappingEnabled: _snappingEnabled,
                    onProjectChanged: _commitProject,
                    onPlayheadChanged: widget.onPlayheadChanged,
                    onSelectionChanged: _select,
                    onLaneAction: _handleLaneAction,
                    onClipActionsRequested: _showClipActions,
                    onEditError: _handleEditError,
                    builders: widget.builders,
                    theme: theme,
                    limits: widget.limits,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context, EditorThemeData theme) {
    final selected = _selectedClip();
    final selection = widget.selection;
    final lane = selection == null
        ? null
        : widget.project.laneById(selection.laneId);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.previewBuilder?.call(
              context,
              widget.project,
              widget.playhead,
              widget.selection,
            ) ??
            EditorDefaultPreview(
              project: widget.project,
              playhead: widget.playhead,
              theme: theme,
            ),
        if (selected is EditorVideoClip &&
            isEditorImageClip(selected) &&
            selection != null &&
            lane != null)
          EditorVisualTransformOverlay(
            destination: selected.destination,
            enabled: !lane.locked,
            theme: theme,
            onCommitted: (destination) => _edit(
              () => setEditorVisualDestination(
                project: widget.project,
                selection: selection,
                destination: destination,
                limits: widget.limits,
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolbar(EditorThemeData theme) {
    final selection = widget.selection;
    final canCut = canSplitEditorSelection(
      widget.project,
      selection,
      widget.playhead,
    );
    final span = _markedSpan();
    return EditorToolbar(
      theme: theme,
      playheadLabel: formatEditorTime(widget.playhead),
      spanLabel: _spanLabel(),
      snappingEnabled: _snappingEnabled,
      transitionDuration: _transitionDuration,
      longestTransition: maxEditorTransitionDuration(widget.project, selection),
      onUndo: _canUndo ? _undo : null,
      onCut: canCut ? () => _cut(selection!) : null,
      onSlice: canSliceEditorProject(widget.project, widget.playhead)
          ? _slice
          : null,
      onDetachAudio: canDetachEditorClipAudio(widget.project, selection)
          ? () => _detachAudio(selection!)
          : null,
      onRemoveClip: canRemoveEditorClip(widget.project, selection)
          ? _removeSelectedClip
          : null,
      onTransitionChoice: _chooseTransition,
      onMarkSpanStart: () => setState(() {
        _spanStart = widget.playhead;
        if (_spanEnd != null && _spanEnd! <= widget.playhead) _spanEnd = null;
      }),
      onMarkSpanEnd: () => setState(() {
        _spanEnd = widget.playhead;
        if (_spanStart != null && _spanStart! >= widget.playhead) {
          _spanStart = null;
        }
      }),
      onRemoveSpan: span == null ? null : () => _removeSpan(span),
      onClearSpan: _clearSpan,
      onZoomIn: _pixelsPerSecond < widget.maxPixelsPerSecond
          ? () => _zoom(1.25)
          : null,
      onZoomOut: _pixelsPerSecond > widget.minPixelsPerSecond
          ? () => _zoom(0.8)
          : null,
      onSnapToggle: () => setState(() => _snappingEnabled = !_snappingEnabled),
      onRenderRequested: widget.onRenderRequested,
      onAddCaptionRequested: widget.onAddCaptionRequested,
      onAddImageOverlayRequested: widget.onAddImageOverlayRequested,
    );
  }

  ({MediaTime from, MediaTime to})? _markedSpan() {
    final from = _spanStart;
    final to = _spanEnd;
    if (from == null || to == null || to <= from) return null;
    return (from: from, to: to);
  }

  String? _spanLabel() {
    final from = _spanStart;
    final to = _spanEnd;
    if (from == null && to == null) return null;
    final left = from == null ? 'start' : formatEditorTime(from);
    final right = to == null ? 'end' : formatEditorTime(to);
    return '$left \u2192 $right';
  }

  void _clearSpan() => setState(() {
    _spanStart = null;
    _spanEnd = null;
  });

  void _slice() => _edit(
    () => sliceEditorProject(
      project: widget.project,
      at: widget.playhead,
      limits: widget.limits,
    ),
  );

  void _detachAudio(EditorSelection selection) => _edit(
    () => detachEditorClipAudio(
      project: widget.project,
      selection: selection,
      limits: widget.limits,
    ),
  );

  void _removeSpan(({MediaTime from, MediaTime to}) span) {
    final removed = _edit(
      () => removeEditorSpan(
        project: widget.project,
        from: span.from,
        to: span.to,
        limits: widget.limits,
      ),
    );
    if (!removed) return;
    _clearSpan();
    widget.onSelectionChanged(null);
    widget.onPlayheadChanged(span.from);
  }

  void _chooseTransition(EditorTransitionChoice choice) {
    final selection = widget.selection;
    if (selection == null) return;
    switch (choice) {
      case EditorTransitionKindChoice(:final kind):
        _edit(
          () => setEditorClipTransition(
            project: widget.project,
            selection: selection,
            transition: EditorTransition(
              kind: kind,
              duration: _fittedTransitionDuration(selection),
            ),
            limits: widget.limits,
          ),
        );
      case EditorTransitionLengthChoice(:final duration):
        setState(() => _transitionDuration = duration);
        final current = _selectedTransition();
        if (current == null) return;
        _edit(
          () => setEditorClipTransition(
            project: widget.project,
            selection: selection,
            transition: current.copyWith(
              duration: _fittedTransitionDuration(selection, wanted: duration),
            ),
            limits: widget.limits,
          ),
        );
      case EditorTransitionRemovalChoice():
        _edit(
          () => clearEditorClipTransition(
            project: widget.project,
            selection: selection,
            limits: widget.limits,
          ),
        );
    }
  }

  MediaTime _fittedTransitionDuration(
    EditorSelection selection, {
    MediaTime? wanted,
  }) {
    final longest = maxEditorTransitionDuration(widget.project, selection);
    final asked = wanted ?? _transitionDuration;
    return asked <= longest ? asked : longest;
  }

  EditorTransition? _selectedTransition() {
    final clip = _selectedClip();
    return clip is EditorVideoClip ? clip.transition : null;
  }

  bool _edit(EditorProject Function() run) {
    try {
      _commitProject(run());
      return true;
    } on EditorValidationException catch (error) {
      _handleEditError(error);
      return false;
    }
  }

  EditorClip? _selectedClip() {
    final selection = widget.selection;
    if (selection == null) return null;
    final lane = widget.project.laneById(selection.laneId);
    if (lane == null) return null;
    for (final clip in lane.clips) {
      if (clip.id == selection.clipId) return clip;
    }
    return null;
  }

  void _cut(EditorSelection selection) {
    try {
      final result = splitEditorClip(
        project: widget.project,
        selection: selection,
        at: widget.playhead,
        limits: widget.limits,
      );
      _commitProject(result.project);
      widget.onSelectionChanged(result.selection);
    } on EditorValidationException catch (error) {
      _handleEditError(error);
    }
  }

  void _select(EditorSelection? selection) {
    _editorFocusNode.requestFocus();
    widget.onSelectionChanged(selection);
  }

  void _commitProject(EditorProject next) {
    validateEditorProject(next, limits: widget.limits);
    if (widget.onUndoRequested != null) {
      _lastEmittedProject = next;
      widget.onProjectChanged(next);
      return;
    }
    final entry = _EditorHistoryEntry(
      project: widget.project,
      selection: widget.selection,
    );
    setState(() {
      _undoHistory.add(entry);
      if (_undoHistory.length > _historyLimit) _undoHistory.removeAt(0);
      _lastEmittedProject = next;
    });
    widget.onProjectChanged(next);
  }

  void _undo() {
    final externalUndo = widget.onUndoRequested;
    if (externalUndo != null) {
      if (widget.canUndo) externalUndo();
      return;
    }
    if (_undoHistory.isEmpty) return;
    late final _EditorHistoryEntry entry;
    setState(() {
      entry = _undoHistory.removeLast();
      _lastEmittedProject = entry.project;
    });
    widget.onProjectChanged(entry.project);
    final selection = entry.selection;
    widget.onSelectionChanged(
      selection != null &&
              entry.project
                      .laneById(selection.laneId)
                      ?.clips
                      .any((clip) => clip.id == selection.clipId) ==
                  true
          ? selection
          : null,
    );
  }

  bool get _canUndo =>
      widget.onUndoRequested == null ? _undoHistory.isNotEmpty : widget.canUndo;

  void _removeSelectedClip() {
    final selection = widget.selection;
    if (!canRemoveEditorClip(widget.project, selection)) return;
    _removeClip(selection!);
  }

  void _removeClip(EditorSelection selection) {
    final removed = _edit(
      () => removeEditorClip(
        project: widget.project,
        selection: selection,
        limits: widget.limits,
      ),
    );
    if (removed) widget.onSelectionChanged(null);
  }

  Future<void> _showClipActions(
    BuildContext context,
    EditorSelection selection,
  ) async {
    final lane = widget.project.laneById(selection.laneId);
    final clip = lane?.clips
        .where((candidate) => candidate.id == selection.clipId)
        .firstOrNull;
    if (lane == null || clip == null) return;
    final action = await showEditorClipActions(
      context,
      clip: clip,
      canSplit: canSplitEditorSelection(
        widget.project,
        selection,
        widget.playhead,
      ),
      canDetachAudio: canDetachEditorClipAudio(widget.project, selection),
      canRemove: canRemoveEditorClip(widget.project, selection),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case EditorClipAction.split:
        _cut(selection);
      case EditorClipAction.detachAudio:
        _detachAudio(selection);
      case EditorClipAction.remove:
        _removeClip(selection);
    }
  }

  void _handleLaneAction(String laneId, EditorLaneAction action) {
    final lane = widget.project.laneById(laneId);
    if (lane == null) return;
    final laneIndex = widget.project.lanes.indexOf(lane);
    _edit(
      () => switch (action) {
        EditorLaneAction.toggleLock => updateEditorLane(
          project: widget.project,
          laneId: laneId,
          locked: !lane.locked,
          limits: widget.limits,
        ),
        EditorLaneAction.toggleVisibility => updateEditorLane(
          project: widget.project,
          laneId: laneId,
          hidden: !lane.hidden,
          limits: widget.limits,
        ),
        EditorLaneAction.toggleMute => updateEditorLane(
          project: widget.project,
          laneId: laneId,
          muted: !lane.muted,
          limits: widget.limits,
        ),
        EditorLaneAction.moveUp => moveEditorLane(
          project: widget.project,
          laneId: laneId,
          toIndex: laneIndex + 1,
          limits: widget.limits,
        ),
        EditorLaneAction.moveDown => moveEditorLane(
          project: widget.project,
          laneId: laneId,
          toIndex: laneIndex - 1,
          limits: widget.limits,
        ),
      },
    );
  }

  void _handleEditError(EditorValidationException error) {
    // Edits are immutable and validated before emission, so retaining the
    // current controlled project is the rollback for a failed command.
    final handler = widget.onEditError;
    if (handler != null) {
      handler(error);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  }

  void _zoom(double factor) {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond * factor).clamp(
        widget.minPixelsPerSecond,
        widget.maxPixelsPerSecond,
      );
    });
  }
}

final class _EditorHistoryEntry {
  const _EditorHistoryEntry({required this.project, required this.selection});

  final EditorProject project;
  final EditorSelection? selection;
}
