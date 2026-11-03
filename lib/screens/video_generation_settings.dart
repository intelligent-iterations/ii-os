import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show DurationSelector;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/minimax_h3_generation_spec.dart';
import '../theme/ii_os_tokens.dart';
import '../view_models/video_generation_view_model.dart';
import '../widgets/runtime_estimate_notice.dart';

class VideoGenerationSettings extends StatelessWidget {
  const VideoGenerationSettings({required this.viewModel, super.key});

  final VideoGenerationViewModel viewModel;

  String _durationHelperText(VideoGenerationViewModel viewModel) {
    final minimum = viewModel.minimumDuration.round();
    final maximum = viewModel.maximumDuration.round();
    if (viewModel.h3Mode == MiniMaxH3GenerationMode.videoContinue) {
      return 'Choose the finished length, from $minimum to $maximum seconds. '
          'The source plays first and keeps its own footage and sound; '
          'H3 renders only the seconds you add on top.';
    }
    return 'Choose a whole-second clip from $minimum to $maximum seconds.';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.isSeedVr2)
          const _SeedVr2OutputSettings()
        else if (viewModel.isMiniMaxH3)
          _MiniMaxH3OutputSettings(viewModel: viewModel)
        else
          _LtxOutputSettings(viewModel: viewModel),
        if (!viewModel.isSeedVr2) ...[
          IiOsGap.vLg,
          DurationSelector(
            value: viewModel.duration,
            minimum: viewModel.minimumDuration,
            maximum: viewModel.maximumDuration,
            divisions: viewModel.durationDivisions,
            valueFormatter: (value) => '${value.round()} seconds',
            onChanged: viewModel.submitting ? null : viewModel.setDuration,
          ),
        ],
        if (viewModel.isMiniMaxH3) ...[
          IiOsGap.vXs,
          Text(
            _durationHelperText(viewModel),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (!viewModel.isMiniMaxH3)
          if (viewModel.runtimeEstimate case final estimate?) ...[
            IiOsGap.vSm,
            RuntimeEstimateNotice(estimate: estimate),
          ],
      ],
    );
  }
}

class _SeedVr2OutputSettings extends StatelessWidget {
  const _SeedVr2OutputSettings();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Upscale output', style: Theme.of(context).textTheme.labelLarge),
        IiOsGap.vXs,
        const Wrap(
          spacing: IiOsSpacing.md,
          runSpacing: IiOsSpacing.md,
          children: [
            _ReadOnlyVideoSetting(
              label: 'Resolution',
              value: '1080 shortest edge',
              icon: LucideIcons.monitor,
            ),
            _ReadOnlyVideoSetting(
              label: 'Frame rate',
              value: 'Preserve source FPS',
              icon: LucideIcons.gauge,
            ),
            _ReadOnlyVideoSetting(
              label: 'Audio',
              value: 'Remux source audio',
              icon: LucideIcons.audioLines,
            ),
            _ReadOnlyVideoSetting(
              label: 'Preset',
              value: 'Quality · 3B FP16',
              icon: LucideIcons.sparkles,
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniMaxH3OutputSettings extends StatelessWidget {
  const _MiniMaxH3OutputSettings({required this.viewModel});

  final VideoGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Orientation', style: Theme.of(context).textTheme.labelLarge),
        IiOsGap.vXs,
        _VideoOrientationSelector(viewModel: viewModel, portraitFirst: true),
        IiOsGap.vLg,
        Text('Output', style: Theme.of(context).textTheme.labelLarge),
        IiOsGap.vXs,
        Wrap(
          spacing: IiOsSpacing.md,
          runSpacing: IiOsSpacing.md,
          children: [
            _ReadOnlyVideoSetting(
              label: 'Resolution',
              value: viewModel.resolution,
              icon: LucideIcons.monitor,
            ),
            _ReadOnlyVideoSetting(
              label: 'Frame rate',
              value: '${viewModel.fps} FPS',
              icon: LucideIcons.gauge,
            ),
            const _ReadOnlyVideoSetting(
              label: 'Audio',
              value: 'Stereo · 32 kHz',
              icon: LucideIcons.audioLines,
            ),
          ],
        ),
      ],
    );
  }
}

class _LtxOutputSettings extends StatelessWidget {
  const _LtxOutputSettings({required this.viewModel});

  final VideoGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Orientation', style: Theme.of(context).textTheme.labelLarge),
        IiOsGap.vXs,
        _VideoOrientationSelector(viewModel: viewModel),
        IiOsGap.vLg,
        Wrap(
          spacing: IiOsSpacing.md,
          runSpacing: IiOsSpacing.md,
          children: [
            _ReadOnlyVideoSetting(
              label: 'Resolution',
              value: viewModel.resolution,
              icon: LucideIcons.monitor,
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                key: ValueKey(viewModel.fps),
                initialValue: viewModel.fps,
                decoration: const InputDecoration(
                  labelText: 'Frames per second',
                  prefixIcon: Icon(LucideIcons.gauge, size: 18),
                ),
                items: const [12, 24, 30, 60]
                    .map(
                      (fps) =>
                          DropdownMenuItem(value: fps, child: Text('$fps FPS')),
                    )
                    .toList(),
                onChanged: viewModel.submitting
                    ? null
                    : (value) => viewModel.setFps(value ?? viewModel.fps),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VideoOrientationSelector extends StatelessWidget {
  const _VideoOrientationSelector({
    required this.viewModel,
    this.portraitFirst = false,
  });

  final VideoGenerationViewModel viewModel;
  final bool portraitFirst;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<String>(
        segments: portraitFirst
            ? const [
                ButtonSegment(
                  value: 'portrait',
                  icon: Icon(LucideIcons.rectangleVertical, size: 17),
                  label: Text('Portrait'),
                ),
                ButtonSegment(
                  value: 'landscape',
                  icon: Icon(LucideIcons.rectangleHorizontal, size: 17),
                  label: Text('Landscape'),
                ),
              ]
            : const [
                ButtonSegment(
                  value: 'landscape',
                  icon: Icon(LucideIcons.rectangleHorizontal, size: 17),
                  label: Text('Landscape'),
                ),
                ButtonSegment(
                  value: 'portrait',
                  icon: Icon(LucideIcons.rectangleVertical, size: 17),
                  label: Text('Portrait'),
                ),
              ],
        selected: {viewModel.orientation},
        onSelectionChanged: viewModel.submitting
            ? null
            : (value) => viewModel.setOrientation(value.first),
      ),
    );
  }
}

class _ReadOnlyVideoSetting extends StatelessWidget {
  const _ReadOnlyVideoSetting({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
        ),
        child: Text(value),
      ),
    );
  }
}
