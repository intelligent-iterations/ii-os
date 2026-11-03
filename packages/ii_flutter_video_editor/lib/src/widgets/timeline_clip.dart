import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/src/editor_builders.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/layer_edits.dart';
import 'package:ii_flutter_video_editor/src/model.dart';

final class EditorTimelineClip extends StatelessWidget {
  const EditorTimelineClip({
    required this.lane,
    required this.clip,
    required this.selected,
    required this.builders,
    required this.theme,
    required this.onSelected,
    required this.onActionsRequested,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onMoveCancel,
    required this.onTrimStart,
    required this.onTrimUpdate,
    required this.onTrimEnd,
    required this.onTrimCancel,
    super.key,
  });

  final EditorLane lane;
  final EditorClip clip;
  final bool selected;
  final EditorBuilders builders;
  final EditorThemeData theme;
  final VoidCallback onSelected;
  final VoidCallback onActionsRequested;
  final GestureDragStartCallback? onMoveStart;
  final GestureDragUpdateCallback? onMoveUpdate;
  final GestureDragEndCallback? onMoveEnd;
  final VoidCallback? onMoveCancel;
  final void Function(DragStartDetails, bool startEdge)? onTrimStart;
  final GestureDragUpdateCallback? onTrimUpdate;
  final GestureDragEndCallback? onTrimEnd;
  final VoidCallback? onTrimCancel;

  @override
  Widget build(BuildContext context) {
    final canEdit = !lane.locked;
    final moveInset = selected && canEdit ? 13.0 : 0.0;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        RepaintBoundary(
          child:
              builders.clipBuilder?.call(context, lane, clip, selected) ??
              _defaultClip(),
        ),
        Positioned(
          left: moveInset,
          right: moveInset,
          top: 0,
          bottom: 0,
          child: Semantics(
            button: true,
            selected: selected,
            label:
                '${lane.kind.name} clip ${clip.id}. '
                '${canEdit ? 'Drag to move. Hold for options.' : 'Locked.'}',
            child: MouseRegion(
              cursor: canEdit
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                key: ValueKey('editor-clip-${clip.id}'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTap: onSelected,
                onLongPress: onActionsRequested,
                onSecondaryTap: onActionsRequested,
                onPanStart: canEdit ? onMoveStart : null,
                onPanUpdate: canEdit ? onMoveUpdate : null,
                onPanEnd: canEdit ? onMoveEnd : null,
                onPanCancel: canEdit ? onMoveCancel : null,
              ),
            ),
          ),
        ),
        if (selected && canEdit) ...[
          _TrimHandle(
            key: ValueKey('editor-clip-trim-start-${clip.id}'),
            startEdge: true,
            clipId: clip.id,
            color: theme.selectedColor,
            onStart: onTrimStart!,
            onUpdate: onTrimUpdate!,
            onEnd: onTrimEnd!,
            onCancel: onTrimCancel!,
          ),
          _TrimHandle(
            key: ValueKey('editor-clip-trim-end-${clip.id}'),
            startEdge: false,
            clipId: clip.id,
            color: theme.selectedColor,
            onStart: onTrimStart!,
            onUpdate: onTrimUpdate!,
            onEnd: onTrimEnd!,
            onCancel: onTrimCancel!,
          ),
        ],
      ],
    );
  }

  Widget _defaultClip() {
    final color = switch (lane.kind) {
      EditorLaneKind.video => theme.videoClipColor,
      EditorLaneKind.audio => theme.audioClipColor,
      EditorLaneKind.captions => theme.captionClipColor,
    };
    final icon = switch (lane.kind) {
      EditorLaneKind.video =>
        isEditorImageClip(clip) ? Icons.image_outlined : Icons.movie_outlined,
      EditorLaneKind.audio => Icons.graphic_eq,
      EditorLaneKind.captions => Icons.subtitles_outlined,
    };
    final label = clip is EditorCaptionClip
        ? (clip as EditorCaptionClip).text
        : clip.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(theme.clipRadius),
        border: Border.all(
          color: selected ? theme.selectedColor : color,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: theme.selectedColor.withValues(alpha: 0.22),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Icon(icon, color: theme.textColor, size: 13),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textColor, fontSize: 11),
              ),
            ),
            if (constraints.maxWidth >= 130)
              Text(
                _durationLabel(clip.duration.inSeconds),
                style: TextStyle(
                  color: theme.textColor.withValues(alpha: 0.72),
                  fontSize: 10,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _durationLabel(double seconds) => seconds >= 10
      ? '${seconds.toStringAsFixed(1)}s'
      : '${seconds.toStringAsFixed(2)}s';
}

final class _TrimHandle extends StatelessWidget {
  const _TrimHandle({
    required this.startEdge,
    required this.clipId,
    required this.color,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    super.key,
  });

  final bool startEdge;
  final String clipId;
  final Color color;
  final void Function(DragStartDetails, bool startEdge) onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: startEdge ? -2 : null,
      right: startEdge ? null : -2,
      top: -2,
      bottom: -2,
      width: 18,
      child: Semantics(
        button: true,
        label: 'Trim ${startEdge ? 'start' : 'end'} of clip $clipId',
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (details) => onStart(details, startEdge),
            onHorizontalDragUpdate: onUpdate,
            onHorizontalDragEnd: onEnd,
            onHorizontalDragCancel: onCancel,
            child: Align(
              alignment: startEdge
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
