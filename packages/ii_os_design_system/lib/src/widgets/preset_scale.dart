import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/palette.dart';
import '../tokens/icons.dart';
import '../tokens/spacing.dart';

/// One named setting on a continuous scale.
@immutable
final class IiOsPreset {
  const IiOsPreset({
    required this.label,
    required this.value,
    required this.description,
  });

  /// What this setting is called, in two words at most.
  final String label;

  /// The number the model is actually given.
  final double value;

  /// What choosing it does, in one sentence.
  final String description;
}

/// A continuous model parameter, offered as the two or three settings anyone
/// actually wants -- with the exact number still reachable underneath.
///
/// A slider reading `1.00` between `0.10` and `1.50` is honest and unusable:
/// it names the unit of a diffusion graph, not an outcome, so the only way to
/// learn what it does is to spend a generation finding out. Naming the useful
/// stops turns the same parameter into a decision, and folding the raw value
/// into a disclosure keeps it available to whoever has learned the scale.
class IiOsPresetScale extends StatefulWidget {
  const IiOsPresetScale({
    required this.label,
    required this.presets,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.onChanged,
    this.exactLabel = 'Set an exact value',
    super.key,
  });

  final String label;
  final List<IiOsPreset> presets;
  final double value;
  final double minimum;
  final double maximum;
  final int divisions;

  /// Null disables the whole control.
  final ValueChanged<double>? onChanged;

  final String exactLabel;

  @override
  State<IiOsPresetScale> createState() => _IiOsPresetScaleState();
}

class _IiOsPresetScaleState extends State<IiOsPresetScale> {
  // Disclosure state, owned here because it is about this control on this
  // screen and means nothing to the caller.
  bool _showExact = false;

  IiOsPreset? get _active {
    for (final preset in widget.presets) {
      if ((preset.value - widget.value).abs() < 0.001) return preset;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    final active = _active;
    final enabled = widget.onChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: text.labelLarge),
        IiOsGap.vXs,
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<double>(
              showSelectedIcon: false,
              segments: [
                for (final preset in widget.presets)
                  ButtonSegment(value: preset.value, label: Text(preset.label)),
              ],
              selected: active == null ? const {} : {active.value},
              emptySelectionAllowed: true,
              onSelectionChanged: enabled
                  ? (values) => widget.onChanged!(values.first)
                  : null,
            ),
          ),
        ),
        IiOsGap.vXs,
        Text(
          active?.description ?? 'Custom · ${widget.value.toStringAsFixed(2)}',
          style: text.bodySmall?.copyWith(color: palette.muted),
        ),
        IiOsGap.vXs,
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled
                ? () => setState(() => _showExact = !_showExact)
                : null,
            icon: Icon(
              _showExact ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: IiOsIconSize.md,
            ),
            label: Text(widget.exactLabel),
          ),
        ),
        if (_showExact)
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: widget.value,
                  min: widget.minimum,
                  max: widget.maximum,
                  divisions: widget.divisions,
                  label: widget.value.toStringAsFixed(2),
                  onChanged: widget.onChanged,
                ),
              ),
              SizedBox(
                width: IiOsSpacing.xxxl,
                child: Text(
                  widget.value.toStringAsFixed(2),
                  textAlign: TextAlign.end,
                  style: text.bodySmall?.copyWith(
                    color: palette.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
