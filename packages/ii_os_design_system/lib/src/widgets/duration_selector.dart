import 'package:flutter/material.dart';

import '../tokens/spacing.dart';

/// A consistent bounded duration control for media generation surfaces.
class DurationSelector extends StatelessWidget {
  const DurationSelector({
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.valueFormatter,
    required this.onChanged,
    this.title = 'Duration',
    super.key,
  }) : assert(maximum > minimum),
       assert(value >= minimum && value <= maximum),
       assert(divisions > 0);

  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final String Function(double value) valueFormatter;
  final ValueChanged<double>? onChanged;
  final String title;

  @override
  Widget build(BuildContext context) {
    final step = (maximum - minimum) / divisions;
    final valueLabel = valueFormatter(value);
    return Semantics(
      container: true,
      label: title,
      value: valueLabel,
      increasedValue: valueFormatter((value + step).clamp(minimum, maximum)),
      decreasedValue: valueFormatter((value - step).clamp(minimum, maximum)),
      onIncrease: onChanged == null
          ? null
          : () => onChanged!((value + step).clamp(minimum, maximum)),
      onDecrease: onChanged == null
          ? null
          : () => onChanged!((value - step).clamp(minimum, maximum)),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                IiOsGap.hMd,
                Expanded(
                  child: Text(
                    valueLabel,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: minimum,
              max: maximum,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
