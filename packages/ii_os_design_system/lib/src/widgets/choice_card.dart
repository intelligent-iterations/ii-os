import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/palette.dart';
import '../tokens/icons.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import 'meta_chip.dart';

/// One option in a set someone is choosing between on the strength of what each
/// option *does*, not what it is called.
///
/// A dropdown is right when the options are interchangeable and their names say
/// everything -- a page size, an aspect ratio. It is wrong when choosing well
/// means knowing what each option is good at, because a dropdown shows one
/// option at a time and leaves no room to say. Picking a generation model is
/// that second case: the names are checkpoints, and the difference between them
/// is a sentence.
///
/// Shaped like a settings row rather than a radio list: a glyph tile that says
/// which one at a glance, the name and its reason, and a check that appears on
/// the one in force. Exclusivity is carried by the tint and the check together,
/// which is what a person reads before they read any word on the card.
class IiOsChoiceCard extends StatelessWidget {
  const IiOsChoiceCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onSelected,
    this.meta = const [],
    this.icon,
    this.unavailableReason = '',
    super.key,
  });

  /// The option's own name.
  final String title;

  /// What this option is for, in one sentence a person can act on.
  final String description;

  /// Short facts that decide a close call -- how fast, what it accepts.
  final List<String> meta;

  final IconData? icon;

  final bool selected;

  /// Null disables the card; say why in [unavailableReason] rather than
  /// leaving a dead control with no explanation.
  final VoidCallback? onSelected;

  final String unavailableReason;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    final available = onSelected != null;
    final titleColor = available
        ? (selected ? palette.brand.text : palette.ink)
        : palette.muted;

    return Semantics(
      container: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: available,
      child: AnimatedContainer(
        duration: IiOsMotion.of(context, IiOsMotion.quick),
        curve: IiOsMotion.standard,
        decoration: BoxDecoration(
          color: selected ? palette.brand.container : palette.surface,
          borderRadius: IiOsRadii.lgAll,
          border: Border.all(
            color: selected ? palette.brand.text : palette.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onSelected,
            borderRadius: IiOsRadii.lgAll,
            child: Padding(
              padding: const EdgeInsets.all(IiOsSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    _GlyphTile(
                      icon: icon!,
                      selected: selected,
                      available: available,
                    ),
                    IiOsGap.hSm,
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: text.titleSmall?.copyWith(color: titleColor),
                        ),
                        IiOsGap.vXxs,
                        Text(
                          description,
                          style: text.bodySmall?.copyWith(color: palette.muted),
                        ),
                        if (meta.isNotEmpty) ...[
                          IiOsGap.vXs,
                          Wrap(
                            spacing: IiOsSpacing.xxs,
                            runSpacing: IiOsSpacing.xxs,
                            children: [
                              for (final fact in meta)
                                IiOsMetaChip(label: fact),
                            ],
                          ),
                        ],
                        if (unavailableReason.isNotEmpty) ...[
                          IiOsGap.vXs,
                          Text(
                            unavailableReason,
                            style: text.bodySmall?.copyWith(
                              color: palette.warning.text,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IiOsGap.hXs,
                  _ChosenMark(selected: selected, color: palette.brand.text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The option's glyph on its own tile, so a list of models is scannable by
/// shape before it is readable by name.
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({
    required this.icon,
    required this.selected,
    required this.available,
  });

  final IconData icon;
  final bool selected;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    return AnimatedContainer(
      duration: IiOsMotion.of(context, IiOsMotion.quick),
      curve: IiOsMotion.standard,
      width: IiOsSpacing.xxl,
      height: IiOsSpacing.xxl,
      decoration: BoxDecoration(
        color: selected ? palette.brand.fill : palette.neutralTint,
        borderRadius: IiOsRadii.mdAll,
      ),
      child: Icon(
        icon,
        size: IiOsIconSize.md,
        color: selected
            ? palette.canvas
            : (available ? palette.muted : palette.border),
      ),
    );
  }
}

/// The check on the option in force.
///
/// It occupies its slot whether or not it is showing, so choosing a different
/// card never shifts the text beside it.
class _ChosenMark extends StatelessWidget {
  const _ChosenMark({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: IiOsIconSize.lg,
      child: AnimatedOpacity(
        duration: IiOsMotion.of(context, IiOsMotion.quick),
        curve: IiOsMotion.standard,
        opacity: selected ? 1 : 0,
        child: Icon(LucideIcons.check, size: IiOsIconSize.lg, color: color),
      ),
    );
  }
}
