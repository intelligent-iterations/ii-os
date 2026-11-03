import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../widgets/spec_panel.dart';

/// The identity vocabulary: the hues and glyphs an operator picks from to tell
/// one navigable thing apart from another.
class IdentitySection extends StatelessWidget {
  const IdentitySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecPanel(
          title: 'Identity hues',
          caption:
              'These say which one, never how is it. Green, amber, and red are '
              'already spoken for by success, warning, and error, so the '
              'identity palette avoids those hue families. Each carries the '
              '3:1 non-text duty because it tints a glyph, not a string \u2014 see '
              'the Palette section for the measured ratios.',
          children: [
            for (final token in IiOsIdentity.colorTokens)
              SpecRow(
                name: token,
                detail: 'IiOsIdentity.colorFor',
                child: Row(
                  children: [
                    for (final icon in IiOsIdentity.iconTokens.take(6))
                      Padding(
                        padding: const EdgeInsets.only(right: IiOsSpacing.sm),
                        child: IiOsIdentityGlyph(
                          colorToken: token,
                          iconToken: icon,
                          semanticLabel: '$token $icon',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        IiOsGap.vMd,
        SpecPanel(
          title: 'Identity glyphs',
          caption:
              'A curated set, not a free text field: an unknown icon name '
              'renders a missing glyph the moment the icon package changes. '
              'Twelve recognisable shapes stay legible in a sidebar where a '
              'thousand would be noise.',
          children: [
            Wrap(
              spacing: IiOsSpacing.md,
              runSpacing: IiOsSpacing.md,
              children: [
                for (final icon in IiOsIdentity.iconTokens)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IiOsIdentityGlyph(
                        colorToken: 'slate',
                        iconToken: icon,
                        size: 24,
                        semanticLabel: icon,
                      ),
                      IiOsGap.vXxs,
                      Text(icon, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
          ],
        ),
        IiOsGap.vMd,
        SpecPanel(
          title: 'In a selected row',
          caption:
              'The identity hue is set on the icon itself, so '
              'ListTile.selectedColor cannot repaint it. Without that, a line '
              'would lose its colour exactly when an operator is standing in '
              'it. The attention dot is amber because it reports state, not '
              'identity.',
          children: [
            for (final selected in [false, true])
              ListTile(
                selected: selected,
                selectedColor: IiOsColors.green,
                selectedTileColor: IiOsColors.green.withValues(alpha: 0.09),
                leading: IiOsIdentityGlyph(
                  colorToken: 'violet',
                  iconToken: 'creditCard',
                  needsAttention: selected,
                  semanticLabel: 'Payments',
                ),
                title: const Text('Payments'),
                subtitle: Text(selected ? 'selected' : 'not selected'),
              ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Brand marks',
          caption:
              'The wordmark and the startup view a consumer sees before the '
              'first frame. Both invert with the mode.',
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: IiOsSpacing.md),
              child: IiOsWordmark(),
            ),
            SizedBox(height: 220, child: IiOsStartupView()),
          ],
        ),
      ],
    );
  }
}
