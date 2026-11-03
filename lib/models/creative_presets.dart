import 'package:ii_os_design_system/ii_os_design_system.dart';

/// The range `control_strength` accepts on every image-edit workflow.
const sourceAdherenceMinimum = 0.1;
const sourceAdherenceMaximum = 1.5;

/// What the workflows themselves default to.
const sourceAdherenceDefault = 1.0;

/// How closely an edit has to follow the picture it started from.
///
/// The parameter underneath is ControlNet strength applied to an edge map of
/// the source, so it runs the opposite way round from the denoise slider people
/// expect: turning it *up* holds the original's shapes, and turning it *down*
/// frees the model to depart from them. A raw `1.00` between `0.10` and `1.50`
/// gives no way to know that, which is why the useful stops are named and the
/// number is folded away behind them.
const sourceAdherencePresets = <IiOsPreset>[
  IiOsPreset(
    label: 'Loose',
    value: 0.5,
    description:
        'Treats the original as a starting point. Expect the biggest change, '
        'and the least of the original left.',
  ),
  IiOsPreset(
    label: 'Balanced',
    value: sourceAdherenceDefault,
    description:
        'Keeps the composition of the original and changes what you asked for.',
  ),
  IiOsPreset(
    label: 'Faithful',
    value: 1.4,
    description:
        'Holds the original shapes and layout as closely as it can. Use it '
        'when only one thing should move.',
  ),
];
