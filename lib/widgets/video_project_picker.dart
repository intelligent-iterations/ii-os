import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/video_project.dart';

/// The list of saved projects in a workspace, and the way to start another.
final class VideoProjectPicker extends StatelessWidget {
  const VideoProjectPicker({
    required this.projects,
    required this.openProjectId,
    required this.loading,
    required this.failure,
    required this.onOpen,
    required this.onCreate,
    required this.onDelete,
    super.key,
  });

  final List<VideoProjectSummary> projects;
  final String? openProjectId;
  final bool loading;

  /// Why the list is unavailable, written for the reader.
  final String? failure;
  final ValueChanged<VideoProjectSummary> onOpen;
  final VoidCallback onCreate;
  final ValueChanged<VideoProjectSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text('Projects', style: text.titleMedium)),
            FilledButton.icon(
              key: const ValueKey('video-project-create'),
              onPressed: onCreate,
              icon: const Icon(LucideIcons.plus, size: IiOsSpacing.md),
              label: const Text('New project'),
            ),
          ],
        ),
        IiOsGap.vSm,
        if (failure case final message?)
          InlineFormError(message: message)
        else if (loading && projects.isEmpty)
          const Padding(
            padding: EdgeInsets.all(IiOsSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (projects.isEmpty)
          const EmptyState(
            icon: LucideIcons.clapperboard,
            title: 'No projects yet',
            message:
                'A project keeps a timeline, its media, and everything that '
                'has been changed in it, so you can close the tab and come '
                'back to the same edit.',
          )
        else
          for (final project in projects)
            _ProjectRow(
              project: project,
              open: project.id == openProjectId,
              onOpen: () => onOpen(project),
              onDelete: () => onDelete(project),
            ),
      ],
    );
  }
}

final class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.open,
    required this.onOpen,
    required this.onDelete,
  });

  final VideoProjectSummary project;
  final bool open;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return Card(
      color: open ? palette.brand.container : palette.surface,
      child: ListTile(
        key: ValueKey('video-project-row-${project.id}'),
        onTap: onOpen,
        title: Text(project.name),
        subtitle: Text(_describe(project)),
        trailing: IconButton(
          key: ValueKey('video-project-delete-${project.id}'),
          tooltip: 'Remove ${project.name}',
          onPressed: onDelete,
          icon: const Icon(LucideIcons.trash2, size: IiOsSpacing.md),
        ),
      ),
    );
  }

  String _describe(VideoProjectSummary project) {
    if (project.isEmpty) return 'Empty \u2014 nothing on the timeline yet';
    final seconds = project.duration.inMilliseconds / 1000;
    final clips = project.clipCount == 1
        ? '1 clip'
        : '${project.clipCount} clips';
    return '$clips over ${seconds.toStringAsFixed(1)}s · '
        '${project.mediaCount} in the media list';
  }
}
