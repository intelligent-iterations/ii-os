import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../widgets/spec_panel.dart';

/// Every `TextTheme` slot, set in the brand face with its real metrics.
class TypographySection extends StatelessWidget {
  const TypographySection({super.key});

  @override
  Widget build(BuildContext context) {
    return SpecPanel(
      title: 'Type scale',
      caption:
          'All fifteen Material slots are defined. Anything left undefined '
          'falls through to a Material default with the wrong size, colour, '
          'and tracking \u2014 which is what put letterSpacing: 0 into 85 inline '
          'styles before this existed.',
      children: [
        for (final (name, style) in IiOsTypography.slots)
          _Specimen(name: name, style: style),
      ],
    );
  }
}

class _Specimen extends StatelessWidget {
  const _Specimen({required this.name, required this.style});

  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: IiOsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.labelSmall),
          IiOsGap.vXxs,
          Text('Creative operations, in motion', style: style),
          IiOsGap.vXxs,
          Text(_metrics(style), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

String _metrics(TextStyle style) {
  final size = style.fontSize?.toStringAsFixed(0) ?? '\u2014';
  final weight = style.fontWeight?.value.toString() ?? '\u2014';
  final tracking = style.letterSpacing?.toStringAsFixed(1) ?? '0.0';
  final height = style.height?.toStringAsFixed(2) ?? '\u2014';
  return '$size/$height · w$weight · tracking $tracking';
}
