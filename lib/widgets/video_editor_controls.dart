import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';

import '../models/editor_export_target.dart';
import '../theme/ii_os_tokens.dart';

final class VideoEditorSummary extends StatelessWidget {
  const VideoEditorSummary({
    required this.sourceCount,
    required this.duration,
    required this.bitrate,
    required this.enabled,
    required this.onBitrateChanged,
    required this.exportTarget,
    required this.onExportTargetChanged,
    this.workspaceRenderAvailable = false,
    super.key,
  });

  final int sourceCount;
  final MediaTime duration;
  final int bitrate;
  final bool enabled;
  final ValueChanged<int> onBitrateChanged;

  /// Where the next export is compressed and written.
  final EditorExportTarget exportTarget;
  final ValueChanged<EditorExportTarget> onExportTargetChanged;

  /// Whether this workspace has a machine that can take the work.
  final bool workspaceRenderAvailable;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Chip(
        label: Text('$sourceCount local source${sourceCount == 1 ? '' : 's'}'),
      ),
      Chip(label: Text('${duration.inSeconds.toStringAsFixed(1)}s timeline')),
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: bitrate,
          decoration: const InputDecoration(labelText: 'Compression'),
          items: const [2, 4, 6, 10]
              .map(
                (mbps) => DropdownMenuItem(
                  value: mbps * 1000 * 1000,
                  child: Text('$mbps Mbps MPEG-4'),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (value) => onBitrateChanged(value ?? bitrate)
              : null,
        ),
      ),
      if (workspaceRenderAvailable)
        SegmentedButton<EditorExportTarget>(
          key: const ValueKey('editor-export-target'),
          segments: const [
            ButtonSegment(
              value: EditorExportTarget.thisDevice,
              label: Text('Export here'),
            ),
            ButtonSegment(
              value: EditorExportTarget.workspaceMachine,
              label: Text('Export in the workspace'),
            ),
          ],
          selected: {exportTarget},
          onSelectionChanged: enabled
              ? (value) => onExportTargetChanged(value.single)
              : null,
        ),
    ],
  );
}

final class EditorCaptionRequest {
  const EditorCaptionRequest({required this.text, required this.subtitle});

  final String text;
  final bool subtitle;
}

Future<EditorCaptionRequest?> showEditorCaptionDialog(
  BuildContext context,
) async {
  final controller = TextEditingController();
  var subtitle = true;
  try {
    return await showDialog<EditorCaptionRequest>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(subtitle ? 'Add subtitle' : 'Add text overlay'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Subtitle')),
                  ButtonSegment(value: false, label: Text('Text overlay')),
                ],
                selected: {subtitle},
                onSelectionChanged: (value) =>
                    setDialogState(() => subtitle = value.single),
              ),
              IiOsGap.vMd,
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  Navigator.pop(
                    context,
                    EditorCaptionRequest(text: text, subtitle: subtitle),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}
