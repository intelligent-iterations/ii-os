import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/video_project.dart';

/// Everything that has happened to a project, newest first, with the changes
/// that have not been saved yet marked as such.
final class VideoProjectHistory extends StatelessWidget {
  const VideoProjectHistory({
    required this.saved,
    required this.unsaved,
    super.key,
  });

  final List<VideoProjectChange> saved;
  final List<String> unsaved;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = IiOsPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('History', style: text.titleMedium),
        IiOsGap.vSm,
        if (saved.isEmpty && unsaved.isEmpty)
          const EmptyState(
            icon: LucideIcons.history,
            title: 'Nothing has changed yet',
            message:
                'Every cut, transition, and trim is written here once the '
                'project is saved.',
          ),
        for (final change in unsaved.reversed)
          _ChangeRow(
            description: change,
            detail: 'Not saved yet',
            color: palette.warning.text,
            icon: LucideIcons.circleDashed,
          ),
        for (final change in saved.reversed)
          _ChangeRow(
            description: change.description,
            detail: _when(change.at),
            color: palette.muted,
            icon: LucideIcons.circleCheck,
          ),
      ],
    );
  }

  String _when(DateTime at) {
    final date = '${at.year}-${_two(at.month)}-${_two(at.day)}';
    return '$date at ${_two(at.hour)}:${_two(at.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

final class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.description,
    required this.detail,
    required this.color,
    required this.icon,
  });

  final String description;
  final String detail;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: IiOsSpacing.xxs),
            child: Icon(icon, size: IiOsSpacing.md, color: color),
          ),
          IiOsGap.hXs,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: text.bodyMedium),
                Text(detail, style: text.bodySmall?.copyWith(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
