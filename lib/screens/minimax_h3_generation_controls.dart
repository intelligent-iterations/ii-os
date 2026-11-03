import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/minimax_h3_generation_spec.dart';
import '../services/minimax_h3_reference_file_types.dart';
import '../theme/ii_os_tokens.dart';
import '../widgets/reference_media_thumbnail.dart';
import '../view_models/video_generation_view_model.dart';
import '../widgets/common.dart';
import '../widgets/media_picker.dart';
import '../widgets/runtime_estimate_notice.dart';

part 'minimax_h3_reference_editor.dart';

class MiniMaxH3GenerationControls extends StatelessWidget {
  const MiniMaxH3GenerationControls({required this.viewModel, super.key});

  final VideoGenerationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.supportsH3PerformanceMode) ...[
          Text('Render mode', style: Theme.of(context).textTheme.labelLarge),
          IiOsGap.vXs,
          Wrap(
            spacing: IiOsSpacing.xs,
            runSpacing: IiOsSpacing.xs,
            children: [
              for (final mode in MiniMaxH3PerformanceMode.values)
                ChoiceChip(
                  key: ValueKey('h3-performance-${mode.wireValue}'),
                  label: Text(mode.label),
                  selected: viewModel.h3PerformanceMode == mode,
                  onSelected:
                      viewModel.submitting ||
                          !viewModel.h3PerformanceModeEnabled(mode)
                      ? null
                      : (_) => viewModel.setH3PerformanceMode(mode),
                ),
            ],
          ),
          IiOsGap.vSm,
          Text(
            viewModel.h3PerformanceMode.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (viewModel.runtimeEstimate case final estimate?) ...[
            IiOsGap.vSm,
            RuntimeEstimateNotice(estimate: estimate),
          ],
          IiOsGap.vLg,
        ],
        Text('Generation mode', style: Theme.of(context).textTheme.labelLarge),
        IiOsGap.vXs,
        if (viewModel.availableH3Modes.length == 1)
          Text(
            viewModel.h3Mode.label,
            style: Theme.of(context).textTheme.titleSmall,
          )
        else
          Wrap(
            spacing: IiOsSpacing.xs,
            runSpacing: IiOsSpacing.xs,
            children: [
              for (final mode in viewModel.availableH3Modes)
                ChoiceChip(
                  key: ValueKey('h3-mode-${mode.wireValue}'),
                  label: Text(mode.label),
                  selected: viewModel.h3Mode == mode,
                  onSelected: viewModel.submitting
                      ? null
                      : (_) => viewModel.setH3Mode(mode),
                ),
            ],
          ),
        IiOsGap.vSm,
        Text(
          viewModel.h3Mode.description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!viewModel.supportsH3ReferenceInputs) ...[
          IiOsGap.vSm,
          _CapabilityNotice(
            message:
                'This workspace currently supports text-to-video. Image and '
                'media-reference generation are not enabled.',
          ),
        ],
        if (viewModel.supportsH3ReferenceInputs &&
            viewModel.h3Mode != MiniMaxH3GenerationMode.textToVideo) ...[
          IiOsGap.vLg,
          _ReferenceEditor(viewModel: viewModel),
        ],
        IiOsGap.vLg,
      ],
    );
  }
}

class _CapabilityNotice extends StatelessWidget {
  const _CapabilityNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(IiOsRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.info, size: 18, color: colors.primary),
            IiOsGap.hSm,
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
