import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../widgets/spec_panel.dart';

/// Thresholds, live against the current window.
///
/// Resize the window and every row updates. A threshold you cannot feel is a
/// threshold nobody maintains.
class BreakpointsSection extends StatelessWidget {
  const BreakpointsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SpecPanel(
      title: 'Breakpoints',
      caption:
          'Each value is the width at which a layout gains the named '
          'capability. The first three follow the Material window size classes '
          'so the app agrees with the framework instead of inventing a '
          'parallel scale.',
      children: [
        _LiveReadout(width: width),
        IiOsGap.vMd,
        for (final (name, value, effect) in IiOsBreakpoints.all)
          _ThresholdRow(
            name: name,
            value: value,
            effect: effect,
            active: width >= value,
          ),
      ],
    );
  }
}

class _LiveReadout extends StatelessWidget {
  const _LiveReadout({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IiOsSpacing.md),
      decoration: BoxDecoration(
        color: IiOsColors.canvas,
        borderRadius: IiOsRadii.mdAll,
        border: Border.all(color: IiOsColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Reading(
              label: 'window width',
              value: '${width.toStringAsFixed(0)}px',
            ),
          ),
          Expanded(
            child: _Reading(
              label: 'size class',
              value: IiOsBreakpoints.sizeClass(width),
            ),
          ),
          Expanded(
            child: _Reading(
              label: 'page gutter',
              value: '${iiOsPageGutter(width).toStringAsFixed(0)}px',
            ),
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: text.labelSmall),
        Text(
          value,
          style: text.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.name,
    required this.value,
    required this.effect,
    required this.active,
  });

  final String name;
  final double value;
  final String effect;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(name, style: text.labelLarge),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '${value.toStringAsFixed(0)}px',
              style: text.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IiOsGap.hSm,
          Expanded(child: Text(effect, style: text.bodySmall)),
          IiOsGap.hSm,
          _ActiveDot(active: active),
        ],
      ),
    );
  }
}

class _ActiveDot extends StatelessWidget {
  const _ActiveDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Active at this width' : 'Not reached at this width',
      child: Container(
        width: IiOsSpacing.sm,
        height: IiOsSpacing.sm,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? IiOsColors.green : IiOsColors.border,
        ),
      ),
    );
  }
}
