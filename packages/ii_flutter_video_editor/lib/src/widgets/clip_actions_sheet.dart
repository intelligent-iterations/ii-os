import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/src/layer_edits.dart';
import 'package:ii_flutter_video_editor/src/model.dart';

enum EditorClipAction { split, detachAudio, remove }

Future<EditorClipAction?> showEditorClipActions(
  BuildContext context, {
  required EditorClip clip,
  required bool canSplit,
  required bool canDetachAudio,
  required bool canRemove,
}) => showModalBottomSheet<EditorClipAction>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 480),
  builder: (context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clip actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 3),
              Text(
                '${_clipLabel(clip)} · ${_durationLabel(clip.duration.inSeconds)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (isEditorImageClip(clip)) ...[
                const SizedBox(height: 10),
                const Text(
                  'Drag the image in the preview to position it. '
                  'Drag its corner handle to resize.',
                ),
              ],
            ],
          ),
        ),
        ListTile(
          key: const ValueKey('editor-clip-action-split'),
          enabled: canSplit,
          leading: const Icon(Icons.content_cut),
          title: const Text('Split at playhead'),
          onTap: canSplit
              ? () => Navigator.pop(context, EditorClipAction.split)
              : null,
        ),
        if (clip is EditorVideoClip)
          ListTile(
            key: const ValueKey('editor-clip-action-detach-audio'),
            enabled: canDetachAudio,
            leading: const Icon(Icons.link_off),
            title: const Text('Separate sound'),
            onTap: canDetachAudio
                ? () => Navigator.pop(context, EditorClipAction.detachAudio)
                : null,
          ),
        const Divider(),
        ListTile(
          key: const ValueKey('editor-clip-action-remove'),
          enabled: canRemove,
          leading: Icon(
            Icons.delete_outline,
            color: canRemove ? Theme.of(context).colorScheme.error : null,
          ),
          title: Text(
            'Remove clip',
            style: canRemove
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null,
          ),
          subtitle: Text(
            canRemove
                ? clip.linkGroupId == null
                      ? 'Leaves a gap in the timeline'
                      : 'Also removes linked media'
                : 'Unlock the lane to remove this clip',
          ),
          onTap: canRemove
              ? () => Navigator.pop(context, EditorClipAction.remove)
              : null,
        ),
      ],
    ),
  ),
);

String _clipLabel(EditorClip clip) => switch (clip) {
  EditorVideoClip() when isEditorImageClip(clip) => 'Image overlay',
  EditorVideoClip() => 'Video clip',
  EditorAudioClip() => 'Audio clip',
  EditorCaptionClip() => 'Caption',
};

String _durationLabel(double seconds) => seconds >= 10
    ? '${seconds.toStringAsFixed(1)}s'
    : '${seconds.toStringAsFixed(2)}s';
