import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/spec_panel.dart';

/// Material controls as the ii-os theme dresses them.
///
/// These are not bespoke widgets -- they are what a consumer gets for free from
/// `IiOsTheme.light()`. If a button here looks wrong, the theme is wrong.
class ControlsSection extends StatefulWidget {
  const ControlsSection({super.key});

  @override
  State<ControlsSection> createState() => _ControlsSectionState();
}

class _ControlsSectionState extends State<ControlsSection> {
  // The section owns this only so the live controls below are actually
  // operable; nothing here is app state.
  bool _switched = true;
  String _model = 'Z-Image Turbo';
  double _strength = 1;
  String _shape = '1:1';
  bool _checked = true;
  double _durationSeconds = 15;
  bool _ghostMode = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecPanel(
          title: 'Chosen tick',
          caption:
              'Sits on an opaque disc rather than over the picture: a border '
              'alone is easy to miss against artwork that is bright at the '
              'edges.',
          children: [
            Row(
              children: [
                for (final hue in [
                  IiOsPalette.of(context).brand,
                  IiOsPalette.of(context).info,
                  IiOsPalette.of(context).accent,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: IiOsSpacing.sm),
                    child: IiOsChosenTick(color: hue.text),
                  ),
              ],
            ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Selection rail',
          caption:
              'A tinted pill is right for a short list and reads as hover on a '
              'rail of a dozen. The bar is a second, positional cue.',
          children: [
            for (final selected in [true, false])
              IiOsSelectionRail(
                selected: selected,
                color: IiOsPalette.of(context).brand.text,
                child: ListTile(
                  dense: true,
                  selected: selected,
                  leading: const Icon(LucideIcons.images, size: 19),
                  title: Text(selected ? 'Asset library' : 'Storyboards'),
                ),
              ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Aspect choice',
          caption:
              'Output shape drawn at the shape it produces. A list of ratios '
              'asks the reader to do the arithmetic and then imagine it.',
          children: [
            IiOsAspectChoice(
              options: _shapes,
              selected: _shape,
              onSelected: (value) => setState(() => _shape = value),
            ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Preset scale',
          caption:
              'A model parameter offered as the settings anyone wants, with '
              'the raw number still reachable underneath.',
          children: [
            IiOsPresetScale(
              label: 'How closely to follow the source',
              presets: _strengthPresets,
              value: _strength,
              minimum: 0.1,
              maximum: 1.5,
              divisions: 28,
              onChanged: (value) => setState(() => _strength = value),
            ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Choice card',
          caption:
              'For options a person picks on the strength of what each one '
              'does. A dropdown shows one at a time and no room to say why.',
          children: [
            for (final option in _modelOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: IiOsSpacing.xs),
                child: IiOsChoiceCard(
                  title: option.title,
                  description: option.description,
                  meta: option.meta,
                  icon: option.icon,
                  selected: _model == option.title,
                  unavailableReason: option.unavailableReason,
                  onSelected: option.unavailableReason.isEmpty
                      ? () => setState(() => _model = option.title)
                      : null,
                ),
              ),
          ],
        ),
        IiOsGap.vXl,
        const SpecPanel(
          title: 'Meta chip',
          caption:
              'A boundary around a fact. Not a Material Chip, which reads as '
              'interactive and invites a click that does nothing.',
          children: [
            Wrap(
              spacing: IiOsSpacing.xs,
              runSpacing: IiOsSpacing.xs,
              children: [
                IiOsMetaChip(label: 'MiniMax H3'),
                IiOsMetaChip(label: 'Z-Image Turbo'),
                IiOsMetaChip(label: '16:9', icon: LucideIcons.ratio),
                IiOsMetaChip(label: 'acme-co/example-app'),
              ],
            ),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Appearance',
          caption:
              'Takes the resolved Brightness rather than the ThemeMode: under '
              'system the mode alone does not say which the viewer is in, so a '
              'control keyed on it does nothing on first press.',
          children: [
            for (final brightness in Brightness.values)
              AppearanceToggle(brightness: brightness, onChanged: (_) {}),
          ],
        ),
        IiOsGap.vXl,
        SpecPanel(
          title: 'Ghost mode',
          caption:
              'Keeps the retention choice and its consequence together. The '
              'enabled state says when the only copy can disappear.',
          children: [
            GhostModeControl(
              enabled: _ghostMode,
              onChanged: (value) => setState(() => _ghostMode = value),
            ),
          ],
        ),
        IiOsGap.vXl,
        const SpecPanel(
          title: 'Buttons',
          caption:
              'Outlined buttons use borderStrong so their edge clears the 3:1 '
              'non-text minimum. The old shared border token was 1.34:1.',
          children: [_Buttons()],
        ),
        IiOsGap.vLg,
        const SpecPanel(
          title: 'Inputs',
          caption:
              'Resting and focused borders both come from the theme. Focus is '
              'brand green at 1.5px so it reads as a state change, not a '
              'redraw.',
          children: [_Inputs()],
        ),
        IiOsGap.vLg,
        SpecPanel(
          title: 'Selection',
          caption:
              'Switches, checkboxes, ranges, and radios on the seeded scheme.',
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Switch(
                      value: _switched,
                      onChanged: (value) => setState(() => _switched = value),
                    ),
                    IiOsGap.hMd,
                    Checkbox(
                      value: _checked,
                      onChanged: (value) =>
                          setState(() => _checked = value ?? false),
                    ),
                    IiOsGap.hMd,
                    const Icon(
                      LucideIcons.circleCheck,
                      color: IiOsColors.green,
                    ),
                  ],
                ),
                IiOsGap.vMd,
                DurationSelector(
                  value: _durationSeconds,
                  minimum: 2,
                  maximum: 20,
                  divisions: 18,
                  valueFormatter: (value) => '${value.round()} seconds',
                  onChanged: (value) =>
                      setState(() => _durationSeconds = value),
                ),
              ],
            ),
          ],
        ),
        IiOsGap.vLg,
        const SpecPanel(
          title: 'Table',
          caption:
              'Row heights and heading style are themed so every table in the '
              'app measures the same.',
          children: [_Table()],
        ),
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: IiOsSpacing.sm,
      runSpacing: IiOsSpacing.sm,
      children: [
        FilledButton(onPressed: () {}, child: const Text('Generate')),
        OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
        TextButton(onPressed: () {}, child: const Text('Learn more')),
        IconButton(
          onPressed: () {},
          tooltip: 'Refresh',
          icon: const Icon(LucideIcons.refreshCw),
        ),
        MediaDownloadButton(onPressed: _downloadDemo),
        const FilledButton(onPressed: null, child: Text('Disabled')),
      ],
    );
  }
}

Future<void> _downloadDemo() async {}

class _Inputs extends StatelessWidget {
  const _Inputs();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TextField(
          decoration: InputDecoration(
            labelText: 'Prompt',
            hintText: 'A courier crossing a rain-lit street',
          ),
        ),
        IiOsGap.vSm,
        const TextField(
          decoration: InputDecoration(
            labelText: 'Seed',
            errorText: 'Must be a whole number',
          ),
        ),
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('JOB')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('STARTED')),
        ],
        rows: const [
          DataRow(
            cells: [
              DataCell(Text('character-sheet')),
              DataCell(Text('running')),
              DataCell(Text('2 min ago')),
            ],
          ),
          DataRow(
            cells: [
              DataCell(Text('storyboard-render')),
              DataCell(Text('finished')),
              DataCell(Text('18 min ago')),
            ],
          ),
        ],
      ),
    );
  }
}

/// One gallery row for the choice card, so the section reads as a real choice
/// rather than three copies of the same card.
final class _ModelOption {
  const _ModelOption({
    required this.title,
    required this.description,
    required this.meta,
    required this.icon,
    this.unavailableReason = '',
  });

  final String title;
  final String description;
  final List<String> meta;
  final IconData icon;
  final String unavailableReason;
}

const _modelOptions = <_ModelOption>[
  _ModelOption(
    title: 'Z-Image Turbo',
    description: 'Fast, clean images from a plain description.',
    meta: ['Fastest'],
    icon: LucideIcons.zap,
  ),
  _ModelOption(
    title: 'Qwen Image',
    description: 'Follows long, specific instructions closely.',
    meta: ['Most literal', 'Up to 3 references'],
    icon: LucideIcons.listChecks,
  ),
  _ModelOption(
    title: 'FLUX.2 Klein',
    description: 'Holds detail in faces, hands, and lettering.',
    meta: ['Most detailed'],
    icon: LucideIcons.gem,
    unavailableReason: 'Not installed on this workspace.',
  ),
];

const _strengthPresets = <IiOsPreset>[
  IiOsPreset(
    label: 'Loose',
    value: 0.5,
    description: 'Treats the original as a starting point.',
  ),
  IiOsPreset(
    label: 'Balanced',
    value: 1,
    description: 'Keeps the composition and changes what you asked for.',
  ),
  IiOsPreset(
    label: 'Faithful',
    value: 1.4,
    description: 'Holds the original shapes and layout as closely as it can.',
  ),
];

const _shapes = <IiOsAspectOption>[
  IiOsAspectOption(label: '1:1', width: 1, height: 1),
  IiOsAspectOption(label: '4:3', width: 4, height: 3),
  IiOsAspectOption(label: '3:4', width: 3, height: 4),
  IiOsAspectOption(label: '16:9', width: 16, height: 9),
  IiOsAspectOption(label: '9:16', width: 9, height: 16),
];
