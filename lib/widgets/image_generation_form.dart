import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../models/image_workflow_capabilities.dart';
import 'prompt_enhance_bar.dart';

class ImageGenerationForm extends StatefulWidget {
  const ImageGenerationForm({
    required this.canSubmit,
    required this.submitting,
    required this.onSubmit,
    this.aspectRatios = defaultImageAspectRatios,
    this.promptMaxLength = 4000,
    this.submitLabel = 'Launch job',
    this.promptEnhance,
    super.key,
  });
  final bool canSubmit, submitting;
  final List<String> aspectRatios;
  final int promptMaxLength;
  final String submitLabel;

  final PromptEnhanceBinding? promptEnhance;
  final void Function({
    required String prompt,
    required String aspectRatio,
    required String seed,
  })
  onSubmit;
  @override
  State<ImageGenerationForm> createState() => _ImageGenerationFormState();
}

class _ImageGenerationFormState extends State<ImageGenerationForm> {
  final _prompt = TextEditingController();
  final _seed = TextEditingController();
  late String _ratio;
  @override
  void initState() {
    super.initState();
    _ratio = initialImageAspectRatio(widget.aspectRatios);
  }

  @override
  void didUpdateWidget(covariant ImageGenerationForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.aspectRatios.contains(_ratio)) {
      _ratio = initialImageAspectRatio(widget.aspectRatios);
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _seed.dispose();
    super.dispose();
  }

  void _submit() {
    if (_seed.text.trim().isEmpty) {
      _seed.text = generatedImageSeed(DateTime.now());
    }
    widget.onSubmit(
      prompt: _prompt.text,
      aspectRatio: _ratio,
      seed: _seed.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.submitting;
    final ratios = widget.aspectRatios.map((value) {
      final dimensions = imageAspectDimensions(value);
      return IiOsAspectOption(
        label: value,
        width: dimensions.width,
        height: dimensions.height,
      );
    }).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _prompt,
              enabled: enabled,
              minLines: 5,
              maxLines: 9,
              maxLength: widget.promptMaxLength,
              decoration: const InputDecoration(
                labelText: 'Image prompt',
                alignLabelWithHint: true,
              ),
            ),
            if (widget.promptEnhance case final binding?)
              PromptEnhanceBar(
                controller: _prompt,
                binding: binding,
                enabled: enabled,
              ),
            if (ratios.isNotEmpty) ...[
              IiOsGap.vSm,
              Text('Shape', style: Theme.of(context).textTheme.labelLarge),
              IiOsGap.vXs,
              IiOsAspectChoice(
                options: ratios,
                selected: _ratio,
                enabled: enabled,
                onSelected: (value) => setState(() => _ratio = value),
              ),
            ],
            IiOsGap.vMd,
            TextField(
              controller: _seed,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Seed (optional)',
                helperMaxLines: 2,
                helperText:
                    'Leave it blank and one is picked for you. It stays in '
                    'this box, so the same look can be made again.',
              ),
            ),
            IiOsGap.vLg,
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: widget.canSubmit ? _submit : null,
                icon: widget.submitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.play, size: 17),
                label: Text(widget.submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
