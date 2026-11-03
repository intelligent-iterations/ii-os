import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart'
    show IiOsGap, PromptingGuideButton;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/minimax_h3_generation_spec.dart';
import '../models/minimax_h3_prompting_guide.dart';
import '../view_models/video_generation_view_model.dart';
import '../widgets/prompt_enhance_bar.dart';
import '../widgets/source_image_field.dart';
import 'minimax_h3_generation_controls.dart';

class VideoGenerationSourceFields extends StatelessWidget {
  const VideoGenerationSourceFields({
    required this.viewModel,
    required this.sourceFile,
    required this.onSelectImage,
    required this.onSelectVideo,
    super.key,
  });

  final VideoGenerationViewModel viewModel;
  final XFile? sourceFile;
  final VoidCallback onSelectImage;
  final VoidCallback onSelectVideo;

  @override
  Widget build(BuildContext context) {
    if (viewModel.sourceImageRequired) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SourceImageField(
            file: sourceFile,
            bytes: viewModel.sourceBytes,
            busy: viewModel.submitting,
            onSelect: onSelectImage,
          ),
          IiOsGap.vLg,
        ],
      );
    }
    if (!viewModel.sourceVideoRequired) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SourceImageField(
          file: viewModel.sourceBytes == null ? null : sourceFile,
          bytes: viewModel.sourceBytes,
          busy: viewModel.submitting,
          onSelect: onSelectVideo,
          title: 'Source video',
          selectLabel: 'Select source video',
          replaceLabel: 'Replace video',
          showPreview: false,
        ),
        IiOsGap.vLg,
      ],
    );
  }
}

class VideoGenerationPromptFields extends StatelessWidget {
  const VideoGenerationPromptFields({
    required this.viewModel,
    required this.prompt,
    required this.onOpenPromptingGuide,
    super.key,
  });

  final VideoGenerationViewModel viewModel;
  final TextEditingController prompt;
  final Future<void> Function(Uri) onOpenPromptingGuide;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isSeedVr2) return const SizedBox.shrink();
    final fullReference = switch (viewModel.h3Mode) {
      MiniMaxH3GenerationMode.referenceToVideo ||
      MiniMaxH3GenerationMode.videoEdit ||
      MiniMaxH3GenerationMode.videoContinue => true,
      _ => false,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.isMiniMaxH3)
          Align(
            alignment: Alignment.centerRight,
            child: PromptingGuideButton(
              title: MiniMaxH3PromptingGuide.title,
              summary: MiniMaxH3PromptingGuide.summary,
              sections: fullReference
                  ? MiniMaxH3PromptingGuide.referenceSections
                  : MiniMaxH3PromptingGuide.sections,
              promptTemplate: fullReference
                  ? MiniMaxH3PromptingGuide.referencePromptTemplateFor(
                      viewModel.duration.round(),
                    )
                  : MiniMaxH3PromptingGuide.promptTemplateFor(
                      viewModel.duration.round(),
                    ),
              onOpenSource: () => onOpenPromptingGuide(
                fullReference
                    ? MiniMaxH3PromptingGuide.referenceSourceUri
                    : MiniMaxH3PromptingGuide.sourceUri,
              ),
            ),
          ),
        if (viewModel.isMiniMaxH3) ...[
          IiOsGap.vSm,
          MiniMaxH3GenerationControls(viewModel: viewModel),
        ],
        TextField(
          controller: prompt,
          enabled: !viewModel.submitting,
          minLines: 4,
          maxLines: 8,
          maxLength: viewModel.isMiniMaxH3 ? 7000 : 8000,
          decoration: InputDecoration(
            labelText: viewModel.isMiniMaxH3 ? _h3PromptLabel : 'Motion prompt',
            helperText: viewModel.isMiniMaxH3
                ? 'Describe timed shots, camera movement, soundscape, and music.'
                : null,
            alignLabelWithHint: true,
          ),
        ),
        if (viewModel.promptBinding case final binding?)
          PromptEnhanceBar(
            controller: prompt,
            binding: binding,
            enabled: !viewModel.submitting,
          ),
      ],
    );
  }

  String get _h3PromptLabel => switch (viewModel.h3Mode) {
    MiniMaxH3GenerationMode.videoEdit => 'Edit instructions',
    MiniMaxH3GenerationMode.videoContinue => 'Continuation instructions',
    _ => 'Cinematic prompt',
  };
}

class VideoGenerationSubmitButton extends StatelessWidget {
  const VideoGenerationSubmitButton({
    required this.viewModel,
    required this.onSubmit,
    super.key,
  });

  final VideoGenerationViewModel viewModel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: FilledButton.icon(
      onPressed: viewModel.canSubmit ? onSubmit : null,
      icon: viewModel.submitting
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.play, size: 17),
      label: Text(viewModel.busyLabel),
    ),
  );
}
