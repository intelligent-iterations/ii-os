import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/spec_panel.dart';

/// The measurement scales -- spacing, icons, content widths, radii -- drawn at
/// true size wherever a size can be shown rather than described.
class ScaleSection extends StatelessWidget {
  const ScaleSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecPanel(
          title: 'Spacing',
          caption:
              'A 4pt scale. The audit that motivated it found 20 distinct '
              'padding values and 20 distinct gap values in use, most of them '
              'one pixel from a neighbour.',
          children: [
            for (final (name, value) in IiOsSpacing.all)
              SpecRow(
                name: name,
                detail: '${value.toStringAsFixed(0)}px',
                // Align, not a bare Container: SpecRow expands its child, so
                // without this every bar stretches to the same width and the
                // scale it exists to demonstrate is invisible.
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: IiOsSpacing.lg,
                    width: value,
                    decoration: const BoxDecoration(
                      color: IiOsColors.green,
                      borderRadius: IiOsRadii.smAll,
                    ),
                  ),
                ),
              ),
          ],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'Icon sizes',
          caption:
              'Twenty distinct icon sizes were in use before this scale, with '
              '204 call sites clustered on 15 through 20 \u2014 six sizes inside a '
              'six-pixel band. md is the house size.',
          children: [
            for (final (name, value) in IiOsIconSize.all)
              SpecRow(
                name: name,
                detail: '${value.toStringAsFixed(0)}px',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    LucideIcons.send,
                    size: value,
                    color: IiOsColors.ink,
                  ),
                ),
              ),
          ],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'Content widths',
          caption:
              'How wide a column of content may get, which is a reading-comfort '
              'question rather than a device one. Distinct from breakpoints, '
              'which ask how wide the window is.',
          children: [
            for (final (name, value, use) in IiOsWidths.all)
              SpecRow(
                name: name,
                detail: '${value.toStringAsFixed(0)}px',
                child: Text(use, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'Radii',
          caption:
              'md is the house radius: cards, inputs, buttons, menus. Reach '
              'past it only when the shape itself carries meaning.',
          children: [
            for (final (name, value, radius) in IiOsRadii.all)
              SpecRow(
                name: name,
                detail: value == IiOsRadii.pill
                    ? 'fully rounded'
                    : '${value.toStringAsFixed(0)}px',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 44,
                    width: 96,
                    decoration: BoxDecoration(
                      color: IiOsColors.surface,
                      borderRadius: radius,
                      border: Border.all(color: IiOsColors.borderStrong),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
