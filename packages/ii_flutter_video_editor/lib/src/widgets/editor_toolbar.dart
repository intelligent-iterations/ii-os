import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/transition.dart';

/// What a chosen entry in the transition menu asks for.
sealed class EditorTransitionChoice {
  const EditorTransitionChoice();
}

final class EditorTransitionKindChoice extends EditorTransitionChoice {
  const EditorTransitionKindChoice(this.kind);
  final EditorTransitionKind kind;
}

final class EditorTransitionLengthChoice extends EditorTransitionChoice {
  const EditorTransitionLengthChoice(this.duration);
  final MediaTime duration;
}

final class EditorTransitionRemovalChoice extends EditorTransitionChoice {
  const EditorTransitionRemovalChoice();
}

const _kindLabels = <EditorTransitionKind, String>{
  EditorTransitionKind.dissolve: 'Cross dissolve',
  EditorTransitionKind.dipToColor: 'Dip to black',
  EditorTransitionKind.slideFromLeft: 'Slide in from the left',
  EditorTransitionKind.slideFromRight: 'Slide in from the right',
  EditorTransitionKind.slideFromTop: 'Slide in from the top',
  EditorTransitionKind.slideFromBottom: 'Slide in from the bottom',
};

const _lengthLabels = <int, String>{
  250: 'Quick \u2014 a quarter second',
  500: 'Short \u2014 half a second',
  1000: 'Steady \u2014 1 second',
  2000: 'Slow \u2014 2 seconds',
};

/// The row of tools above the preview. Every control is a command; the editor
/// owns the state each one changes.
final class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    required this.theme,
    required this.playheadLabel,
    required this.spanLabel,
    required this.snappingEnabled,
    required this.transitionDuration,
    required this.longestTransition,
    required this.onUndo,
    required this.onCut,
    required this.onSlice,
    required this.onDetachAudio,
    required this.onRemoveClip,
    required this.onTransitionChoice,
    required this.onMarkSpanStart,
    required this.onMarkSpanEnd,
    required this.onRemoveSpan,
    required this.onClearSpan,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onSnapToggle,
    this.onRenderRequested,
    this.onAddCaptionRequested,
    this.onAddImageOverlayRequested,
    super.key,
  });

  final EditorThemeData theme;
  final String playheadLabel;
  final String? spanLabel;
  final bool snappingEnabled;
  final MediaTime transitionDuration;
  final MediaTime longestTransition;
  final VoidCallback? onUndo;
  final VoidCallback? onCut;
  final VoidCallback? onSlice;
  final VoidCallback? onDetachAudio;
  final VoidCallback? onRemoveClip;
  final ValueChanged<EditorTransitionChoice> onTransitionChoice;
  final VoidCallback onMarkSpanStart;
  final VoidCallback onMarkSpanEnd;
  final VoidCallback? onRemoveSpan;
  final VoidCallback onClearSpan;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onSnapToggle;
  final VoidCallback? onRenderRequested;
  final VoidCallback? onAddCaptionRequested;
  final VoidCallback? onAddImageOverlayRequested;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    color: theme.surfaceColor,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('editor-undo'),
            tooltip: 'Undo last change (Ctrl/Command+Z)',
            onPressed: onUndo,
            icon: const Icon(Icons.undo),
          ),
          const VerticalDivider(width: 12),
          IconButton(
            key: const ValueKey('editor-cut'),
            tooltip: 'Split selected clip at playhead',
            onPressed: onCut,
            icon: const Icon(Icons.content_cut),
          ),
          IconButton(
            key: const ValueKey('editor-slice'),
            tooltip: 'Cut every lane at the playhead',
            onPressed: onSlice,
            icon: const Icon(Icons.vertical_split_outlined),
          ),
          _transitionMenu(),
          IconButton(
            key: const ValueKey('editor-detach-audio'),
            tooltip: 'Separate this picture from its sound',
            onPressed: onDetachAudio,
            icon: const Icon(Icons.link_off),
          ),
          IconButton(
            key: const ValueKey('editor-remove-clip'),
            tooltip: 'Remove selected clip (Delete)',
            onPressed: onRemoveClip,
            icon: const Icon(Icons.delete_outline),
          ),
          const VerticalDivider(width: 12),
          IconButton(
            key: const ValueKey('editor-mark-span-start'),
            tooltip: 'Start a span here',
            onPressed: onMarkSpanStart,
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            key: const ValueKey('editor-mark-span-end'),
            tooltip: 'End the span here',
            onPressed: onMarkSpanEnd,
            icon: const Icon(Icons.last_page),
          ),
          if (onRemoveSpan != null)
            IconButton(
              key: const ValueKey('editor-remove-span'),
              tooltip: 'Take the marked span out and close the gap',
              onPressed: onRemoveSpan,
              icon: const Icon(Icons.content_cut_outlined),
            ),
          const VerticalDivider(width: 12),
          if (onAddImageOverlayRequested != null) ...[
            IconButton(
              key: const ValueKey('editor-add-image-overlay'),
              tooltip: 'Add image overlay',
              onPressed: onAddImageOverlayRequested,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          ],
          if (onAddCaptionRequested != null) ...[
            IconButton(
              key: const ValueKey('editor-add-caption'),
              tooltip: 'Add caption at playhead',
              onPressed: onAddCaptionRequested,
              icon: const Icon(Icons.subtitles_outlined),
            ),
          ],
          if (onAddImageOverlayRequested != null ||
              onAddCaptionRequested != null)
            const VerticalDivider(width: 12),
          IconButton(
            key: const ValueKey('editor-zoom-out'),
            tooltip: 'Zoom timeline out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            key: const ValueKey('editor-zoom-in'),
            tooltip: 'Zoom timeline in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            key: const ValueKey('editor-snap-toggle'),
            tooltip: snappingEnabled
                ? 'Disable timeline snapping'
                : 'Enable timeline snapping',
            isSelected: snappingEnabled,
            onPressed: onSnapToggle,
            icon: const Icon(Icons.vertical_align_center),
            selectedIcon: const Icon(Icons.vertical_align_center),
          ),
          const VerticalDivider(width: 12),
          Center(
            child: Text(
              playheadLabel,
              key: const ValueKey('editor-playhead-label'),
              style: TextStyle(
                color: theme.textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (onRenderRequested != null)
            Center(
              child: FilledButton.icon(
                key: const ValueKey('editor-render'),
                onPressed: onRenderRequested,
                icon: const Icon(Icons.movie_creation_outlined, size: 18),
                label: const Text('Render'),
              ),
            ),
          const SizedBox(width: 12),
          if (spanLabel case final label?)
            Center(
              child: InputChip(
                key: const ValueKey('editor-span-label'),
                label: Text(label),
                onDeleted: onClearSpan,
                deleteButtonTooltipMessage: 'Clear the marked span',
              ),
            ),
          const SizedBox(width: 12),
          Center(
            child: Text(
              'Drag to move \u2022 handles trim \u2022 hold or right-click for options',
              key: const ValueKey('editor-timeline-hint'),
              style: TextStyle(color: theme.mutedTextColor, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _transitionMenu() => PopupMenuButton<Object>(
    key: const ValueKey('editor-transition'),
    enabled: longestTransition > MediaTime.zero,
    tooltip: 'Choose how this clip arrives',
    icon: const Icon(Icons.animation_outlined),
    onSelected: (value) => onTransitionChoice(value as EditorTransitionChoice),
    itemBuilder: (context) => [
      for (final entry in _kindLabels.entries)
        PopupMenuItem<Object>(
          value: EditorTransitionKindChoice(entry.key),
          child: Text(entry.value),
        ),
      const PopupMenuDivider(),
      for (final entry in _lengthLabels.entries)
        PopupMenuItem<Object>(
          value: EditorTransitionLengthChoice(
            MediaTime.milliseconds(entry.key),
          ),
          enabled: MediaTime.milliseconds(entry.key) <= longestTransition,
          child: Text(
            entry.value,
            style: TextStyle(
              fontWeight:
                  MediaTime.milliseconds(entry.key) == transitionDuration
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<Object>(
        value: EditorTransitionRemovalChoice(),
        child: Text('Cut straight in'),
      ),
    ],
  );
}
