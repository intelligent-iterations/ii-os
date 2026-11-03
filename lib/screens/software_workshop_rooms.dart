import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/models.dart';
import '../models/workshop_room.dart';
import '../models/workshop_worker_summary.dart';
import '../models/workshop_ticket.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/common.dart';

/// The accent for [token], read from the palette so it answers to the mode.
///
/// `IiOsColors.identity` is the light map and has one value per token, so
/// naming it here painted a light hue on a dark rail.
Color workshopRoomColor(BuildContext context, String token) {
  final palette = IiOsPalette.of(context);
  return palette.identity[token] ?? palette.info.text;
}

class WorkshopRoomEmptyState extends StatelessWidget {
  const WorkshopRoomEmptyState({required this.onConfigure, super.key});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) => Card(
    child: EmptyState(
      title: 'Connect the workshop',
      message:
          'Choose at least one GitHub repository and Project before creating rooms.',
      icon: LucideIcons.wrench,
      action: FilledButton(
        onPressed: onConfigure,
        child: const Text('Configure workspace'),
      ),
    ),
  );
}

class WorkshopRoomRail extends StatelessWidget {
  const WorkshopRoomRail({
    required this.rooms,
    required this.selected,
    required this.onSelected,
    required this.onAdd,
    required this.canManage,
    super.key,
  });

  final List<WorkshopRoomModel> rooms;
  final WorkshopRoomModel selected;
  final ValueChanged<WorkshopRoomModel> onSelected;
  final VoidCallback onAdd;
  final bool canManage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomRailHeading(
          compact: constraints.maxWidth < IiOsBreakpoints.compact,
          canManage: canManage,
          onAdd: onAdd,
        ),
        IiOsGap.vXs,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final room in rooms) ...[
                _RoomTab(
                  room: room,
                  selected: room.id == selected.id,
                  onTap: () => onSelected(room),
                ),
                if (room != rooms.last) IiOsGap.hXs,
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _RoomRailHeading extends StatelessWidget {
  const _RoomRailHeading({
    required this.compact,
    required this.canManage,
    required this.onAdd,
  });

  final bool compact;
  final bool canManage;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final title = Text('Rooms', style: Theme.of(context).textTheme.titleMedium);
    final detail = Text(
      'Separate repositories and agent access by team or purpose.',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: IiOsPalette.of(context).muted),
    );
    final add = TextButton.icon(
      onPressed: onAdd,
      icon: const Icon(LucideIcons.plus, size: 16),
      label: const Text('New room'),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [title, const Spacer(), if (canManage) add]),
          detail,
        ],
      );
    }
    return Row(
      children: [
        title,
        IiOsGap.hXs,
        Expanded(child: detail),
        if (canManage) add,
      ],
    );
  }
}

class _RoomTab extends StatelessWidget {
  const _RoomTab({
    required this.room,
    required this.selected,
    required this.onTap,
  });

  final WorkshopRoomModel room;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final color = workshopRoomColor(context, room.color);
    return Semantics(
      button: true,
      selected: selected,
      label: '${room.name}, ${room.repositories.length} repositories',
      child: Material(
        color: selected ? color.withValues(alpha: 0.08) : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IiOsRadii.md),
          side: BorderSide(
            color: selected ? color : palette.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IiOsRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IiOsSpacing.md,
              vertical: IiOsSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(LucideIcons.doorOpen, size: 18, color: color),
                IiOsGap.hXs,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${room.repositories.length} ${room.repositories.length == 1 ? 'repository' : 'repositories'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WorkshopRoomHeader extends StatelessWidget {
  const WorkshopRoomHeader({
    required this.room,
    required this.project,
    required this.repository,
    required this.healthLabel,
    required this.healthReady,
    required this.activeWorkers,
    required this.longestRunning,
    required this.onRepositoryChanged,
    required this.onSettings,
    required this.canManage,
    super.key,
  });

  final WorkshopRoomModel room;
  final ProjectConnection? project;
  final String repository;
  final String healthLabel;
  final bool healthReady;
  final int activeWorkers;
  final Duration? longestRunning;
  final ValueChanged<String?> onRepositoryChanged;
  final VoidCallback onSettings;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final color = workshopRoomColor(context, room.color);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(IiOsRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RoomHeading(
              room: room,
              project: project,
              healthLabel: healthLabel,
              healthReady: healthReady,
              activeWorkers: activeWorkers,
              longestRunning: longestRunning,
              canManage: canManage,
              onSettings: onSettings,
            ),
            if (room.repositories.length > 1) ...[
              IiOsGap.vSm,
              DropdownButtonFormField<String>(
                initialValue: repository,
                decoration: const InputDecoration(
                  labelText: 'Repository in this room',
                ),
                items: room.repositories
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: onRepositoryChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomHeading extends StatelessWidget {
  const _RoomHeading({
    required this.room,
    required this.project,
    required this.healthLabel,
    required this.healthReady,
    required this.activeWorkers,
    required this.longestRunning,
    required this.canManage,
    required this.onSettings,
  });

  final WorkshopRoomModel room;
  final ProjectConnection? project;
  final String healthLabel;
  final bool healthReady;
  final int activeWorkers;
  final Duration? longestRunning;
  final bool canManage;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        LucideIcons.doorOpen,
        color: workshopRoomColor(context, room.color),
        size: 24,
      ),
      IiOsGap.hSm,
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room.name, style: Theme.of(context).textTheme.titleLarge),
            IiOsGap.vXxs,
            Text(
              '${project?.title ?? 'No Project'} · ${workshopPermissionName(room.permissionProfile)} by default',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IiOsGap.vXxs,
            Text(
              workshopWorkerSummary(activeWorkers, longestRunning),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: activeWorkers == 0
                    ? IiOsPalette.of(context).muted
                    : IiOsPalette.of(context).brand.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      StatusPill(
        healthLabel,
        color: healthReady
            ? IiOsPalette.of(context).brand.text
            : IiOsPalette.of(context).warning.text,
      ),
      if (canManage) ...[
        IiOsGap.hXs,
        IconButton.outlined(
          tooltip: 'Room settings',
          onPressed: onSettings,
          icon: const Icon(LucideIcons.settings2, size: 17),
        ),
      ],
    ],
  );
}

class WorkshopTaskFilterBar extends StatelessWidget {
  const WorkshopTaskFilterBar({
    required this.selected,
    required this.counts,
    required this.onSelected,
    required this.onRefresh,
    required this.refreshing,
    super.key,
  });

  final WorkshopFilter selected;
  final Map<WorkshopFilter, int> counts;
  final ValueChanged<WorkshopFilter> onSelected;
  final VoidCallback onRefresh;
  final bool refreshing;

  static const shownFilters = [
    WorkshopFilter.active,
    WorkshopFilter.attention,
    WorkshopFilter.working,
    WorkshopFilter.qa,
    WorkshopFilter.done,
  ];

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in shownFilters) ...[
                FilterChip(
                  selected: selected == filter,
                  label: Text('${filter.label} ${counts[filter] ?? 0}'),
                  onSelected: (_) => onSelected(filter),
                ),
                if (filter != shownFilters.last) IiOsGap.hXs,
              ],
            ],
          ),
        ),
      ),
      IiOsGap.hXs,
      IconButton.outlined(
        tooltip: 'Refresh pending tasks',
        onPressed: refreshing ? null : onRefresh,
        icon: const Icon(LucideIcons.refreshCw, size: 17),
      ),
    ],
  );
}
