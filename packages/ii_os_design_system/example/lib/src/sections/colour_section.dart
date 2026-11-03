import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../widgets/contrast_badge.dart';
import '../widgets/spec_panel.dart';

/// The palette, with every entry measured against both surfaces it is drawn on.
class ColourSection extends StatelessWidget {
  const ColourSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SpecPanel(
      title: 'Palette',
      caption:
          'Ratios are computed live with WCAG 2.1 relative luminance, not '
          'copied from a comment. Text carries 1.4.3 at 4.5:1; interactive '
          'boundaries carry 1.4.11 at 3:1; surfaces and decorative fills carry '
          'no duty.',
      children: [
        for (final swatch in IiOsColors.all) _SwatchRow(swatch: swatch),
      ],
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({required this.swatch});

  final IiOsSwatch swatch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: IiOsSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Chip(color: swatch.color),
          IiOsGap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(swatch.name, style: text.labelLarge),
                    IiOsGap.hXs,
                    SelectableText(
                      _hex(swatch.color),
                      style: text.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                Text(swatch.role, style: text.bodySmall),
                IiOsGap.vXs,
                Wrap(
                  spacing: IiOsSpacing.xs,
                  runSpacing: IiOsSpacing.xxs,
                  children: [
                    ContrastBadge(
                      foreground: swatch.color,
                      background: IiOsColors.surface,
                      surfaceName: 'surface',
                      minimumRatio: swatch.minimumRatio,
                    ),
                    ContrastBadge(
                      foreground: swatch.color,
                      background: IiOsColors.canvas,
                      surfaceName: 'canvas',
                      minimumRatio: swatch.minimumRatio,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _hex(color),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: IiOsRadii.mdAll,
          border: Border.all(color: IiOsColors.border),
        ),
      ),
    );
  }
}

String _hex(Color color) {
  final value =
      (color.a * 255).round() << 24 |
      (color.r * 255).round() << 16 |
      (color.g * 255).round() << 8 |
      (color.b * 255).round();
  return '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
