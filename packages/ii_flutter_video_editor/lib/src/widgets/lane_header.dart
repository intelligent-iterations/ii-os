import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/model.dart';

enum EditorLaneAction {
  toggleLock,
  toggleVisibility,
  toggleMute,
  moveUp,
  moveDown,
}

final class EditorLaneHeader extends StatelessWidget {
  const EditorLaneHeader({
    required this.lane,
    required this.laneIndex,
    required this.laneCount,
    required this.theme,
    required this.onAction,
    super.key,
  });

  final EditorLane lane;
  final int laneIndex;
  final int laneCount;
  final EditorThemeData theme;
  final ValueChanged<EditorLaneAction> onAction;

  @override
  Widget build(BuildContext context) {
    final icon = switch (lane.kind) {
      EditorLaneKind.video => Icons.movie_outlined,
      EditorLaneKind.audio =>
        lane.muted ? Icons.volume_off_outlined : Icons.graphic_eq,
      EditorLaneKind.captions => Icons.subtitles_outlined,
    };
    final inactive = lane.hidden || lane.muted;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: theme.mutedTextColor.withValues(alpha: inactive ? 0.55 : 1),
            size: 15,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              lane.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.textColor.withValues(alpha: inactive ? 0.55 : 1),
                fontSize: 11,
              ),
            ),
          ),
          if (lane.locked)
            Icon(Icons.lock_outline, color: theme.mutedTextColor, size: 12),
          SizedBox(
            width: 32,
            child: PopupMenuButton<EditorLaneAction>(
              key: ValueKey('editor-lane-menu-${lane.id}'),
              tooltip: 'Edit ${lane.label} lane',
              padding: EdgeInsets.zero,
              iconSize: 17,
              icon: const Icon(Icons.more_horiz),
              onSelected: onAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: ValueKey('editor-lane-lock-${lane.id}'),
                  value: EditorLaneAction.toggleLock,
                  child: _MenuLabel(
                    icon: lane.locked
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                    label: lane.locked ? 'Unlock editing' : 'Lock editing',
                  ),
                ),
                if (lane.kind == EditorLaneKind.audio)
                  PopupMenuItem(
                    key: ValueKey('editor-lane-mute-${lane.id}'),
                    value: EditorLaneAction.toggleMute,
                    child: _MenuLabel(
                      icon: lane.muted
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                      label: lane.muted ? 'Unmute lane' : 'Mute lane',
                    ),
                  )
                else
                  PopupMenuItem(
                    key: ValueKey('editor-lane-visibility-${lane.id}'),
                    value: EditorLaneAction.toggleVisibility,
                    child: _MenuLabel(
                      icon: lane.hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      label: lane.hidden ? 'Show lane' : 'Hide lane',
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  key: ValueKey('editor-lane-up-${lane.id}'),
                  value: EditorLaneAction.moveUp,
                  enabled: laneIndex < laneCount - 1,
                  child: const _MenuLabel(
                    icon: Icons.arrow_upward,
                    label: 'Bring layer forward',
                  ),
                ),
                PopupMenuItem(
                  key: ValueKey('editor-lane-down-${lane.id}'),
                  value: EditorLaneAction.moveDown,
                  enabled: laneIndex > 0,
                  child: const _MenuLabel(
                    icon: Icons.arrow_downward,
                    label: 'Send layer backward',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19),
      const SizedBox(width: 12),
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
