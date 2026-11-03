import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show DurationSelector, IiOsIconSize;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/song_generation_options.dart';
import '../models/song_render_profile.dart';
import '../theme/ii_os_theme.dart';
import '../theme/ii_os_tokens.dart';
import '../view_models/song_generation_view_model.dart';
import '../widgets/common.dart';
import '../widgets/runtime_estimate_notice.dart';
import '../widgets/song_creative_fields.dart';

String _formatSongDuration(double value) {
  final seconds = value.round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class SongGenerationForm extends StatefulWidget {
  const SongGenerationForm({required this.viewModel, super.key});

  final SongGenerationViewModel viewModel;

  @override
  State<SongGenerationForm> createState() => _SongGenerationFormState();
}

class _SongGenerationFormState extends State<SongGenerationForm> {
  final _prompt = TextEditingController();
  final _lyrics = TextEditingController();
  final _bpm = TextEditingController();
  final _seed = TextEditingController();

  @override
  void dispose() {
    _prompt.dispose();
    _lyrics.dispose();
    _bpm.dispose();
    _seed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SongCreativeFields(
              description: _prompt,
              lyrics: _lyrics,
              enabled: !viewModel.submitting,
              instrumental: viewModel.instrumental,
              onInstrumentalChanged: viewModel.setInstrumental,
              descriptionEnhance: viewModel.descriptionBinding,
              lyricsEnhance: viewModel.lyricsBinding,
            ),
            if (!viewModel.instrumental) ...[
              IiOsGap.vSm,
              _VocalLanguageField(viewModel: viewModel),
            ],
            IiOsGap.vLg,
            const _SectionHeading(
              title: 'Render and length',
              description:
                  'Choose a longer working draft or a shorter, cleaner finish.',
            ),
            IiOsGap.vSm,
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final profile in songRenderProfiles)
                      ButtonSegment(
                        value: profile.id,
                        label: Text(profile.label),
                      ),
                  ],
                  selected: {viewModel.generationProfile.id},
                  onSelectionChanged: viewModel.canSubmit
                      ? (values) =>
                            viewModel.selectGenerationProfile(values.first)
                      : null,
                ),
              ),
            ),
            IiOsGap.vSm,
            DurationSelector(
              value: viewModel.durationSeconds,
              minimum: minimumSongDurationSeconds,
              maximum: viewModel.generationProfile.maxDurationSeconds,
              divisions: viewModel.durationDivisions,
              valueFormatter: _formatSongDuration,
              onChanged: viewModel.submitting ? null : viewModel.setDuration,
            ),
            Text(
              viewModel.generationProfile.description,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: IiOsColors.muted),
            ),
            if (viewModel.runtimeEstimate case final estimate?) ...[
              IiOsGap.vSm,
              RuntimeEstimateNotice(estimate: estimate),
            ],
            IiOsGap.vLg,
            const _SectionHeading(
              title: 'Musical direction',
              description:
                  'Leave these on Auto unless the song needs a specific tempo, key, or meter.',
            ),
            IiOsGap.vSm,
            _SongSettingsGrid(viewModel: viewModel, bpmController: _bpm),
            IiOsGap.vXs,
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              subtitle: const Text('Use a seed to repeat a result'),
              children: [
                TextField(
                  controller: _seed,
                  enabled: !viewModel.submitting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Seed (optional)',
                    helperText: 'Leave blank for a new variation each time.',
                  ),
                ),
              ],
            ),
            IiOsGap.vSm,
            Text(
              'Describe musical traits directly and use only lyrics or styles you have the right to adapt.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: IiOsColors.muted),
            ),
            IiOsGap.vLg,
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: viewModel.canSubmit ? _submit : null,
                icon: viewModel.submitting
                    ? const SizedBox.square(
                        dimension: IiOsIconSize.sm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.music2, size: IiOsIconSize.sm),
                label: const Text('Generate song'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final result = await widget.viewModel.submit(
      prompt: _prompt.text,
      lyrics: _lyrics.text,
      bpm: _bpm.text,
      seed: _seed.text,
    );
    if (result == null && mounted && widget.viewModel.modelError != null) {
      showFailure(context, widget.viewModel.modelError!);
    }
  }
}

class _VocalLanguageField extends StatelessWidget {
  const _VocalLanguageField({required this.viewModel});

  final SongGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<String>(
      key: const Key('song-vocal-language'),
      initialSelection: viewModel.vocalLanguage,
      enabled: !viewModel.submitting,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      leadingIcon: const Icon(LucideIcons.languages, size: IiOsIconSize.md),
      label: const Text('Vocal language'),
      helperText: 'Auto follows the language in your lyrics.',
      dropdownMenuEntries: [
        for (final language in songVocalLanguages)
          DropdownMenuEntry(value: language.code, label: language.label),
      ],
      onSelected: (value) {
        if (value != null) viewModel.setVocalLanguage(value);
      },
    );
  }
}

class _SongSettingsGrid extends StatelessWidget {
  const _SongSettingsGrid({
    required this.viewModel,
    required this.bpmController,
  });

  final SongGenerationViewModel viewModel;
  final TextEditingController bpmController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth < IiOsBreakpoints.pairedFields
            ? constraints.maxWidth
            : (constraints.maxWidth - IiOsSpacing.sm) / 2;
        return Wrap(
          spacing: IiOsSpacing.sm,
          runSpacing: IiOsSpacing.sm,
          children: [
            SizedBox(
              width: fieldWidth,
              child: TextField(
                controller: bpmController,
                enabled: !viewModel.submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tempo',
                  hintText: 'Auto',
                  helperText: 'Optional · 30\u2013300 BPM',
                  prefixIcon: Icon(LucideIcons.gauge, size: IiOsIconSize.md),
                ),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: viewModel.keyScale,
                decoration: const InputDecoration(
                  labelText: 'Key and scale',
                  prefixIcon: Icon(LucideIcons.music2, size: IiOsIconSize.md),
                ),
                items: [
                  for (final value in songKeyScales)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value.isEmpty ? 'Auto' : value,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: viewModel.submitting
                    ? null
                    : (value) => viewModel.setKeyScale(value ?? ''),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: viewModel.timeSignature,
                decoration: const InputDecoration(labelText: 'Time signature'),
                items: [
                  for (final option in songTimeSignatures)
                    DropdownMenuItem(
                      value: option.value,
                      child: Text(option.label),
                    ),
                ],
                onChanged: viewModel.submitting
                    ? null
                    : (value) => viewModel.setTimeSignature(value ?? ''),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        IiOsGap.vXxs,
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: IiOsColors.muted),
        ),
      ],
    );
  }
}
