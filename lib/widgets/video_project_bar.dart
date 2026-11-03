import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/video_project.dart';

/// The identity strip above the editor: which project is open, whether it is
/// saved, and the actions that change either answer.
final class VideoProjectBar extends StatelessWidget {
  const VideoProjectBar({
    required this.project,
    required this.unsavedChanges,
    required this.saving,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onOpen,
    required this.onNew,
    required this.onHistory,
    super.key,
  });

  final VideoProjectSummary? project;
  final int unsavedChanges;
  final bool saving;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSave;
  final VoidCallback onOpen;
  final VoidCallback onNew;
  final VoidCallback? onHistory;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(IiOsSpacing.sm),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        runSpacing: IiOsSpacing.xs,
        spacing: IiOsSpacing.sm,
        children: [
          _VideoProjectIdentity(
            name: project?.name ?? 'Not saved as a project',
            status: _status(),
            warning: unsavedChanges > 0,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('video-project-undo'),
                tooltip: 'Undo the last change',
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(LucideIcons.undo2, size: IiOsSpacing.md),
              ),
              IconButton(
                key: const ValueKey('video-project-redo'),
                tooltip: 'Redo the change you undid',
                onPressed: canRedo ? onRedo : null,
                icon: const Icon(LucideIcons.redo2, size: IiOsSpacing.md),
              ),
              IiOsGap.hXs,
              TextButton.icon(
                key: const ValueKey('video-project-history'),
                onPressed: onHistory,
                icon: const Icon(LucideIcons.history, size: IiOsSpacing.md),
                label: const Text('History'),
              ),
              TextButton.icon(
                key: const ValueKey('video-project-open'),
                onPressed: onOpen,
                icon: const Icon(LucideIcons.folderOpen, size: IiOsSpacing.md),
                label: const Text('Open'),
              ),
              TextButton.icon(
                key: const ValueKey('video-project-new'),
                onPressed: onNew,
                icon: const Icon(LucideIcons.filePlus, size: IiOsSpacing.md),
                label: const Text('New'),
              ),
              IiOsGap.hXs,
              FilledButton.icon(
                key: const ValueKey('video-project-save'),
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: IiOsSpacing.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.save, size: IiOsSpacing.md),
                label: Text(saving ? 'Saving\u2026' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _status() {
    if (saving) return 'Saving to this workspace\u2026';
    if (project == null) {
      return 'Save this timeline to keep it and come back to it later.';
    }
    if (unsavedChanges == 0) return 'Everything is saved.';
    return unsavedChanges == 1
        ? '1 change not saved yet'
        : '$unsavedChanges changes not saved yet';
  }
}

final class _VideoProjectIdentity extends StatelessWidget {
  const _VideoProjectIdentity({
    required this.name,
    required this.status,
    required this.warning,
  });
  final String name, status;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: text.titleSmall,
          key: const ValueKey('video-project-name'),
        ),
        Text(
          status,
          style: text.bodySmall?.copyWith(
            color: warning ? palette.warning.text : palette.muted,
          ),
          key: const ValueKey('video-project-status'),
        ),
      ],
    );
  }
}
