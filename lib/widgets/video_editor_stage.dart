import 'package:flutter/material.dart';
import 'package:ii_flutter_video_editor/ii_flutter_video_editor.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Tall enough to hold a preview above a timeline of several lanes without
/// either one collapsing.
const _stageHeight = 720.0;

/// The editing surface itself: the preview, the toolbar, and the timeline.
final class VideoEditorStage extends StatelessWidget {
  const VideoEditorStage({
    required this.project,
    required this.playhead,
    required this.selection,
    required this.busy,
    required this.canUndo,
    required this.onUndoRequested,
    required this.onProjectChanged,
    required this.onPlayheadChanged,
    required this.onSelectionChanged,
    required this.onAddCaptionRequested,
    required this.onRenderRequested,
    required this.onEditError,
    required this.previewBuilder,
    super.key,
  });

  final EditorProject project;
  final MediaTime playhead;
  final EditorSelection? selection;
  final bool busy;
  final bool canUndo;
  final VoidCallback onUndoRequested;
  final ValueChanged<EditorProject> onProjectChanged;
  final ValueChanged<MediaTime> onPlayheadChanged;
  final ValueChanged<EditorSelection?> onSelectionChanged;
  final VoidCallback? onAddCaptionRequested;
  final VoidCallback? onRenderRequested;
  final ValueChanged<EditorValidationException> onEditError;
  final EditorPreviewBuilder previewBuilder;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      height: _stageHeight,
      child: IiFlutterVideoEditor(
        project: project,
        playhead: playhead,
        selection: selection,
        // Keep the package's broader editing limits here. Platform render
        // targets are deliberately stricter, but an over-target stored
        // timeline must stay open so a person can repair it.
        onProjectChanged: busy ? (_) {} : onProjectChanged,
        onPlayheadChanged: onPlayheadChanged,
        onSelectionChanged: onSelectionChanged,
        canUndo: canUndo && !busy,
        onUndoRequested: onUndoRequested,
        onAddCaptionRequested: busy ? null : onAddCaptionRequested,
        onRenderRequested: busy ? null : onRenderRequested,
        onEditError: onEditError,
        previewBuilder: previewBuilder,
      ),
    ),
  );
}

/// What the page shows before anything has been brought in to edit.
final class VideoEditorEmptyStage extends StatelessWidget {
  const VideoEditorEmptyStage({required this.ghostMode, super.key});

  final bool ghostMode;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.lg),
      child: Column(
        children: [
          const Icon(LucideIcons.clapperboard, size: IiOsSpacing.xl),
          IiOsGap.vSm,
          const Text(
            'Add a video, audio clip, or image from your workspace '
            'library or computer to begin.',
          ),
          IiOsGap.vXxs,
          Text(
            ghostMode
                ? 'Source and exported bytes stay inside this browser or app '
                      'unless you save a local copy.'
                : 'Generated assets download directly from workspace GCS. '
                      'Source bytes then stay inside this browser or app. '
                      'After local export, the frontend sends the video '
                      'straight to the selected workspace bucket.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
