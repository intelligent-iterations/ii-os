import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ii_flutter_video_editor/src/editor_builders.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';
import 'package:ii_flutter_video_editor/src/selection.dart';
import 'package:ii_flutter_video_editor/src/timeline_edits.dart';
import 'package:ii_flutter_video_editor/src/validation.dart';
import 'package:ii_flutter_video_editor/src/widgets/lane_header.dart';
import 'package:ii_flutter_video_editor/src/widgets/timeline_clip.dart';
import 'package:ii_flutter_video_editor/src/widgets/timeline_ruler.dart';

final class EditorTimeline extends StatefulWidget {
  const EditorTimeline({
    required this.project,
    required this.playhead,
    required this.selection,
    required this.pixelsPerSecond,
    required this.snappingEnabled,
    required this.onProjectChanged,
    required this.onPlayheadChanged,
    required this.onSelectionChanged,
    required this.onLaneAction,
    required this.onClipActionsRequested,
    required this.builders,
    required this.theme,
    required this.limits,
    this.onEditError,
    super.key,
  });

  final EditorProject project;
  final MediaTime playhead;
  final EditorSelection? selection;
  final double pixelsPerSecond;
  final bool snappingEnabled;
  final ValueChanged<EditorProject> onProjectChanged;
  final ValueChanged<MediaTime> onPlayheadChanged;
  final ValueChanged<EditorSelection?> onSelectionChanged;
  final void Function(String laneId, EditorLaneAction action) onLaneAction;
  final void Function(BuildContext context, EditorSelection selection)
  onClipActionsRequested;
  final ValueChanged<EditorValidationException>? onEditError;
  final EditorBuilders builders;
  final EditorThemeData theme;
  final EditorLimits limits;

  @override
  State<EditorTimeline> createState() => _EditorTimelineState();
}

final class _EditorTimelineState extends State<EditorTimeline> {
  _TimelineGesture? _gesture;
  EditorProject? _previewProject;
  MediaTime? _snapGuide;
  String? _previewTargetLaneId;

  EditorProject get _displayProject => _previewProject ?? widget.project;

  double get _contentHeight =>
      widget.theme.rulerHeight +
      _displayProject.lanes.length * widget.theme.laneHeight;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.theme.backgroundColor,
      child: SizedBox(
        height: _contentHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: widget.theme.headerWidth, child: _headers(context)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.max(
                    constraints.maxWidth,
                    _displayProject.duration.inSeconds * widget.pixelsPerSecond,
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _timeline(context, width),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headers(BuildContext context) {
    return Column(
      children: [
        Container(
          height: widget.theme.rulerHeight,
          color: widget.theme.rulerColor,
          alignment: Alignment.center,
          child: Tooltip(
            message: 'Clip body: move \u2022 highlighted edges: trim',
            child: Icon(
              Icons.layers_outlined,
              color: widget.theme.mutedTextColor,
              size: 17,
            ),
          ),
        ),
        for (
          var laneIndex = 0;
          laneIndex < _displayProject.lanes.length;
          laneIndex++
        )
          Container(
            height: widget.theme.laneHeight,
            decoration: BoxDecoration(
              color: widget.theme.surfaceColor,
              border: Border(
                top: BorderSide(color: widget.theme.dividerColor, width: 0.5),
                right: BorderSide(color: widget.theme.dividerColor),
              ),
            ),
            child:
                widget.builders.laneHeaderBuilder?.call(
                  context,
                  _displayProject.lanes[laneIndex],
                ) ??
                EditorLaneHeader(
                  lane: _displayProject.lanes[laneIndex],
                  laneIndex: laneIndex,
                  laneCount: _displayProject.lanes.length,
                  theme: widget.theme,
                  onAction: (action) => widget.onLaneAction(
                    _displayProject.lanes[laneIndex].id,
                    action,
                  ),
                ),
          ),
      ],
    );
  }

  Widget _timeline(BuildContext context, double width) {
    return SizedBox(
      key: const ValueKey('editor-timeline'),
      width: width,
      height: _contentHeight,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: widget.theme.rulerHeight,
            child: GestureDetector(
              key: const ValueKey('editor-timeline-ruler'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _scrub(details.localPosition.dx),
              onHorizontalDragUpdate: (details) =>
                  _scrub(details.localPosition.dx),
              child: EditorTimelineRuler(
                durationSeconds: _displayProject.duration.inSeconds,
                pixelsPerSecond: widget.pixelsPerSecond,
                theme: widget.theme,
              ),
            ),
          ),
          for (
            var laneIndex = 0;
            laneIndex < _displayProject.lanes.length;
            laneIndex++
          )
            _lane(context, _displayProject.lanes[laneIndex], laneIndex, width),
          if (_snapGuide case final snapGuide?)
            Positioned(
              left: _timeX(snapGuide, width),
              top: widget.theme.rulerHeight,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('editor-snap-guide'),
                  width: 2,
                  color: widget.theme.selectedColor,
                ),
              ),
            ),
          Positioned(
            left: _timeX(widget.playhead, width),
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('editor-playhead'),
                width: 2,
                color: widget.theme.playheadColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lane(
    BuildContext context,
    EditorLane lane,
    int laneIndex,
    double width,
  ) {
    return Positioned(
      left: 0,
      right: 0,
      top: widget.theme.rulerHeight + laneIndex * widget.theme.laneHeight,
      height: widget.theme.laneHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: laneIndex.isEven
              ? widget.theme.backgroundColor
              : widget.theme.surfaceColor.withValues(alpha: 0.35),
          border: Border(
            top: BorderSide(color: widget.theme.dividerColor, width: 0.5),
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: ValueKey('editor-lane-background-${lane.id}'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _scrub(details.localPosition.dx),
                onHorizontalDragUpdate: (details) =>
                    _scrub(details.localPosition.dx),
              ),
            ),
            for (final clip in lane.clips) _clip(context, lane, clip, width),
          ],
        ),
      ),
    );
  }

  Widget _clip(
    BuildContext context,
    EditorLane lane,
    EditorClip clip,
    double timelineWidth,
  ) {
    final left = clip.timelineStart.inSeconds * widget.pixelsPerSecond;
    final width = math.max(
      2.0,
      clip.duration.inSeconds * widget.pixelsPerSecond,
    );
    final selected =
        widget.selection == EditorSelection(laneId: lane.id, clipId: clip.id) ||
        (_gesture?.selection.clipId == clip.id &&
            (_previewTargetLaneId ?? lane.id) == lane.id);
    return Positioned(
      left: left,
      top: 5,
      width: math.max(2, math.min(width, timelineWidth - left)),
      bottom: 5,
      child: EditorTimelineClip(
        lane: lane,
        clip: clip,
        selected: selected,
        builders: widget.builders,
        theme: widget.theme,
        onSelected: () => widget.onSelectionChanged(
          EditorSelection(laneId: lane.id, clipId: clip.id),
        ),
        onActionsRequested: () {
          final selection = EditorSelection(laneId: lane.id, clipId: clip.id);
          widget.onSelectionChanged(selection);
          widget.onClipActionsRequested(context, selection);
        },
        onMoveStart: lane.locked
            ? null
            : (_) => _startGesture(lane, clip, null),
        onMoveUpdate: _updateGesture,
        onMoveEnd: (_) => _finishGesture(),
        onMoveCancel: _cancelGesture,
        onTrimStart: (details, startEdge) => _startGesture(
          lane,
          clip,
          startEdge ? EditorTrimEdge.start : EditorTrimEdge.end,
        ),
        onTrimUpdate: _updateGesture,
        onTrimEnd: (_) => _finishGesture(),
        onTrimCancel: _cancelGesture,
      ),
    );
  }

  void _startGesture(
    EditorLane lane,
    EditorClip clip,
    EditorTrimEdge? trimEdge,
  ) {
    final selection = EditorSelection(laneId: lane.id, clipId: clip.id);
    widget.onSelectionChanged(selection);
    setState(() {
      _gesture = _TimelineGesture(
        project: widget.project,
        selection: selection,
        trimEdge: trimEdge,
      );
      _previewProject = widget.project;
      _previewTargetLaneId = lane.id;
      _snapGuide = null;
    });
  }

  void _updateGesture(DragUpdateDetails details) {
    final gesture = _gesture;
    if (gesture == null) return;
    gesture.dx += details.delta.dx;
    gesture.dy += details.delta.dy;
    try {
      if (gesture.trimEdge case final edge?) {
        _updateTrim(gesture, edge);
      } else {
        _updateMove(gesture);
      }
    } on EditorValidationException catch (error) {
      _reportEditError(error);
      _cancelGesture();
    }
  }

  void _updateMove(_TimelineGesture gesture) {
    final anchor = gesture.project.clipById(gesture.selection.clipId)!;
    final proposedMicroseconds = math.max(
      0,
      anchor.timelineStart.microseconds +
          (gesture.dx / widget.pixelsPerSecond * Duration.microsecondsPerSecond)
              .round(),
    );
    final targetLaneId = _targetLane(gesture);
    final resolution = resolveEditorClipMove(
      project: gesture.project,
      selection: gesture.selection,
      targetLaneId: targetLaneId,
      proposedTimelineStart: MediaTime.microseconds(proposedMicroseconds),
      playhead: widget.playhead,
      snapThreshold: _snapThreshold,
      limits: widget.limits,
    );
    final preview = moveEditorClip(
      project: gesture.project,
      selection: gesture.selection,
      targetLaneId: resolution.targetLaneId,
      timelineStart: resolution.timelineStart,
      limits: widget.limits,
    );
    setState(() {
      _previewProject = preview;
      _previewTargetLaneId = resolution.targetLaneId;
      _snapGuide = resolution.snapGuide;
      gesture.changed =
          resolution.timelineStart != anchor.timelineStart ||
          resolution.targetLaneId != gesture.selection.laneId;
    });
  }

  void _updateTrim(_TimelineGesture gesture, EditorTrimEdge edge) {
    final anchor = gesture.project.clipById(gesture.selection.clipId)!;
    final originalEdge = edge == EditorTrimEdge.start
        ? anchor.timelineStart
        : anchor.timelineEnd;
    final proposed = math.max(
      0,
      originalEdge.microseconds +
          (gesture.dx / widget.pixelsPerSecond * Duration.microsecondsPerSecond)
              .round(),
    );
    final resolution = resolveEditorClipTrim(
      project: gesture.project,
      selection: gesture.selection,
      edge: edge,
      proposedEdgeTime: MediaTime.microseconds(proposed),
      playhead: widget.playhead,
      snapThreshold: _snapThreshold,
      limits: widget.limits,
    );
    final preview = trimEditorClip(
      project: gesture.project,
      selection: gesture.selection,
      edge: edge,
      edgeTime: resolution.edgeTime,
      limits: widget.limits,
    );
    setState(() {
      _previewProject = preview;
      _snapGuide = resolution.snapGuide;
      gesture.changed = resolution.edgeTime != originalEdge;
    });
  }

  String _targetLane(_TimelineGesture gesture) {
    final sourceIndex = gesture.project.lanes.indexWhere(
      (lane) => lane.id == gesture.selection.laneId,
    );
    final index = (sourceIndex + gesture.dy / widget.theme.laneHeight)
        .round()
        .clamp(0, gesture.project.lanes.length - 1);
    final source = gesture.project.lanes[sourceIndex];
    final candidate = gesture.project.lanes[index];
    return candidate.kind == source.kind && !candidate.locked
        ? candidate.id
        : source.id;
  }

  MediaTime get _snapThreshold {
    final bypass = HardwareKeyboard.instance.isShiftPressed;
    if (!widget.snappingEnabled || bypass) return MediaTime.zero;
    return MediaTime.seconds(10 / widget.pixelsPerSecond);
  }

  void _finishGesture() {
    final gesture = _gesture;
    final preview = _previewProject;
    final targetLaneId = _previewTargetLaneId;
    _clearGesture();
    if (gesture == null || preview == null || !gesture.changed) return;
    widget.onProjectChanged(preview);
    if (targetLaneId != null && targetLaneId != gesture.selection.laneId) {
      widget.onSelectionChanged(
        EditorSelection(laneId: targetLaneId, clipId: gesture.selection.clipId),
      );
    }
  }

  void _cancelGesture() => _clearGesture();

  void _clearGesture() {
    if (!mounted) return;
    setState(() {
      _gesture = null;
      _previewProject = null;
      _previewTargetLaneId = null;
      _snapGuide = null;
    });
  }

  void _reportEditError(EditorValidationException error) {
    final handler = widget.onEditError;
    if (handler == null) throw error;
    handler(error);
  }

  void _scrub(double x) {
    final clamped = x.clamp(
      0.0,
      _displayProject.duration.inSeconds * widget.pixelsPerSecond,
    );
    widget.onPlayheadChanged(
      MediaTime.seconds(clamped / widget.pixelsPerSecond),
    );
  }

  double _timeX(MediaTime time, double width) =>
      math.min(width - 2, math.max(0, time.inSeconds * widget.pixelsPerSecond));
}

final class _TimelineGesture {
  _TimelineGesture({
    required this.project,
    required this.selection,
    required this.trimEdge,
  });

  final EditorProject project;
  final EditorSelection selection;
  final EditorTrimEdge? trimEdge;
  double dx = 0;
  double dy = 0;
  bool changed = false;
}
