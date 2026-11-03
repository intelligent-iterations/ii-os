import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/src/editor_theme.dart';
import 'package:ii_flutter_video_editor/src/edits.dart';
import 'package:ii_flutter_video_editor/src/media.dart';
import 'package:ii_flutter_video_editor/src/model.dart';

final class EditorDefaultPreview extends StatelessWidget {
  const EditorDefaultPreview({
    required this.project,
    required this.playhead,
    required this.theme,
    super.key,
  });

  final EditorProject project;
  final MediaTime playhead;
  final EditorThemeData theme;

  @override
  Widget build(BuildContext context) {
    final captions = activeEditorClips(
      project,
      playhead,
    ).whereType<EditorCaptionClip>().toList(growable: false);
    return ColoredBox(
      color: Color(int.parse('ff${project.backgroundColor}', radix: 16)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(
              Icons.play_circle_outline,
              color: theme.mutedTextColor,
              size: 52,
            ),
          ),
          for (final caption in captions)
            Align(
              alignment: Alignment(
                caption.destination.x * 2 + caption.destination.width - 1,
                caption.destination.y * 2 + caption.destination.height - 1,
              ),
              child: FractionallySizedBox(
                widthFactor: caption.destination.width,
                child: Text(
                  caption.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(caption.style.textColor),
                    backgroundColor: Color(caption.style.backgroundColor),
                    fontSize: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
