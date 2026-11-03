import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../gallery_sections.dart';

/// The gallery's section list, shared by the wide rail and the narrow drawer.
class GalleryNav extends StatelessWidget {
  const GalleryNav({
    required this.selected,
    required this.onSelect,
    this.showTitle = false,
    super.key,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: IiOsSpacing.md),
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IiOsSpacing.lg,
              IiOsSpacing.xs,
              IiOsSpacing.lg,
              IiOsSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ii-os', style: text.titleLarge),
                Text('design system', style: text.bodySmall),
              ],
            ),
          ),
        for (final (index, section) in gallerySections.indexed)
          _NavTile(
            section: section,
            selected: index == selected,
            onTap: () => onSelect(index),
          ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final GallerySection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IiOsSpacing.sm,
        vertical: IiOsSpacing.xxs,
      ),
      child: Material(
        color: selected ? IiOsColors.canvas : IiOsColors.surface,
        borderRadius: IiOsRadii.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: IiOsRadii.mdAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IiOsSpacing.sm,
              vertical: IiOsSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 18,
                  color: selected ? IiOsColors.green : IiOsColors.muted,
                ),
                IiOsGap.hSm,
                Expanded(
                  child: Text(
                    section.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? IiOsColors.green : IiOsColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
