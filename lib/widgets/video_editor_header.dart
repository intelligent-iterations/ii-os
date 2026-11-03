import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/video_project.dart';
import 'video_project_bar.dart';

/// Everything above the editing surface: which project is open, anything that
/// went wrong, and any render happening somewhere other than this tab.
final class VideoEditorHeader extends StatelessWidget {
  const VideoEditorHeader({
    required this.project,
    required this.unsavedChanges,
    required this.saving,
    required this.canUndo,
    required this.canRedo,
    required this.failure,
    required this.renderingInWorkspace,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onOpen,
    required this.onNew,
    required this.onHistory,
    required this.onDismissFailure,
    required this.onOpenLibrary,
    super.key,
  });

  final VideoProjectSummary? project;
  final int unsavedChanges;
  final bool saving;
  final bool canUndo;
  final bool canRedo;

  /// Why something the person asked for did not happen.
  final String? failure;

  /// Whether a workspace machine is rendering this edit right now.
  final bool renderingInWorkspace;

  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;
  final VoidCallback onOpen;
  final VoidCallback onNew;
  final VoidCallback? onHistory;
  final VoidCallback onDismissFailure;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      VideoProjectBar(
        project: project,
        unsavedChanges: unsavedChanges,
        saving: saving,
        canUndo: canUndo,
        canRedo: canRedo,
        onUndo: onUndo,
        onRedo: onRedo,
        onSave: onSave,
        onOpen: onOpen,
        onNew: onNew,
        onHistory: onHistory,
      ),
      if (failure case final message?) ...[
        IiOsGap.vSm,
        Semantics(
          key: const Key('video-editor-failure-live-region'),
          container: true,
          liveRegion: true,
          child: ErrorSurface(
            title: 'This project could not be handled',
            message: message,
            retryLabel: 'Dismiss',
            onRetry: onDismissFailure,
          ),
        ),
      ],
      if (renderingInWorkspace) ...[
        IiOsGap.vSm,
        BackgroundWorkCard(
          running: true,
          title: 'A workspace machine is rendering this edit',
          detail:
              'You can close this tab. The finished video appears in the '
              'media library when it is done.',
          onFollow: onOpenLibrary,
          followLabel: 'Open the media library',
        ),
      ],
    ],
  );
}

/// The one action that starts everything: bringing media in.
final class VideoEditorMediaButton extends StatelessWidget {
  const VideoEditorMediaButton({
    required this.importing,
    required this.onPressed,
    super.key,
  });

  final bool importing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: importing
        ? const SizedBox.square(
            dimension: IiOsSpacing.md,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(LucideIcons.filePlus2, size: IiOsSpacing.md),
    label: Text(importing ? 'Adding media\u2026' : 'Add media'),
  );
}
