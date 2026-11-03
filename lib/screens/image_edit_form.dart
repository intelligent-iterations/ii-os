part of 'image_edit_panel.dart';

final class _ImageEditUiState {
  const _ImageEditUiState({
    required this.mode,
    required this.modeTemplates,
    required this.enabledTemplates,
    required this.selectedTemplate,
    required this.runtimeEstimate,
    required this.referenceSlots,
    required this.showsSourceAdherence,
    required this.sourceFile,
    required this.sourceBytes,
    required this.referenceFiles,
    required this.referenceBytes,
    required this.imageAspectRatio,
    required this.maskRegions,
    required this.prompt,
    required this.seed,
    required this.promptEnhance,
    required this.controlStrength,
    required this.useAll,
    required this.busy,
    required this.loadingTemplates,
    required this.busyLabel,
    required this.onModeChanged,
    required this.onTemplateChanged,
    required this.onUseAllChanged,
    required this.onSelectSource,
    required this.onSelectReference,
    required this.onClearReference,
    required this.onMasksChanged,
    required this.onClearMasks,
    required this.onControlStrengthChanged,
    required this.onSubmit,
  });

  final ImageEditMode mode;
  final List<WorkflowTemplateModel> modeTemplates;
  final List<WorkflowTemplateModel> enabledTemplates;
  final WorkflowTemplateModel? selectedTemplate;
  final RuntimeEstimateSnapshot? runtimeEstimate;
  final int referenceSlots;
  final bool showsSourceAdherence;
  final XFile? sourceFile;
  final Uint8List? sourceBytes;
  final List<XFile?> referenceFiles;
  final List<Uint8List?> referenceBytes;
  final double imageAspectRatio;
  final List<Rect> maskRegions;
  final TextEditingController prompt;
  final TextEditingController seed;
  final PromptEnhanceBinding? promptEnhance;
  final double controlStrength;
  final bool useAll;
  final bool busy;
  final bool loadingTemplates;
  final String busyLabel;
  final ValueChanged<ImageEditMode> onModeChanged;
  final ValueChanged<String?> onTemplateChanged;
  final ValueChanged<bool> onUseAllChanged;
  final VoidCallback onSelectSource;
  final ValueChanged<int> onSelectReference;
  final ValueChanged<int> onClearReference;
  final ValueChanged<List<Rect>> onMasksChanged;
  final VoidCallback onClearMasks;
  final ValueChanged<double> onControlStrengthChanged;
  final VoidCallback onSubmit;
}

class _ImageEditPage extends StatelessWidget {
  const _ImageEditPage({
    required this.controller,
    required this.ghostMode,
    required this.onGhostModeChanged,
    required this.showUnavailable,
    required this.unavailableMessage,
    required this.data,
    required this.submissions,
  });

  final AppController controller;
  final bool ghostMode;
  final ValueChanged<bool>? onGhostModeChanged;
  final bool showUnavailable;
  final String unavailableMessage;
  final _ImageEditUiState data;
  final List<ImageEditSubmission> submissions;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Edit images',
      subtitle: 'Change the whole image or select only the area to replace.',
      actions: [
        if (onGhostModeChanged != null)
          GhostModeControl(
            key: const Key('generation-ghost-mode'),
            enabled: ghostMode,
            onChanged: onGhostModeChanged!,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showUnavailable) ...[
            ImageEditTemplateWarning(message: unavailableMessage),
            IiOsGap.vSm,
          ],
          GenerationWorkspace(
            form: _ImageEditFormCard(data: data),
            preview: _ImageEditPreviewPane(
              controller: controller,
              submissions: submissions,
              busy: data.busy,
              enabledTemplates: data.enabledTemplates,
              useAll: data.useAll,
              aspectRatio: data.imageAspectRatio,
              busyLabel: data.busyLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageEditFormCard extends StatelessWidget {
  const _ImageEditFormCard({required this.data});

  final _ImageEditUiState data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(IiOsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImageEditSetup(data: data),
            _ImageEditPromptControls(data: data),
          ],
        ),
      ),
    );
  }
}

class _ImageEditSetup extends StatelessWidget {
  const _ImageEditSetup({required this.data});

  final _ImageEditUiState data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<ImageEditMode>(
            segments: const [
              ButtonSegment(
                value: ImageEditMode.revision,
                icon: Icon(LucideIcons.brush, size: 17),
                label: Text('Whole image'),
              ),
              ButtonSegment(
                value: ImageEditMode.inpaint,
                icon: Icon(LucideIcons.scan, size: 17),
                label: Text('Selected area'),
              ),
            ],
            selected: {data.mode},
            onSelectionChanged: data.busy
                ? null
                : (value) => data.onModeChanged(value.first),
          ),
        ),
        IiOsGap.vMd,
        if (data.modeTemplates.isNotEmpty) ...[
          ImageEditModelPicker(
            templates: data.modeTemplates,
            selectedId: data.selectedTemplate?.id,
            useAll: data.useAll,
            enabled: !data.busy,
            onSelected: data.onTemplateChanged,
            onUseAllChanged: data.onUseAllChanged,
          ),
          IiOsGap.vSm,
        ],
        if (data.runtimeEstimate case final estimate?) ...[
          RuntimeEstimateNotice(estimate: estimate),
          IiOsGap.vMd,
        ],
        SourceImageField(
          title: 'Image A · the picture you are changing',
          file: data.sourceFile,
          bytes: data.sourceBytes,
          busy: data.busy,
          selectLabel: 'Choose image A',
          onSelect: data.onSelectSource,
        ),
        if (data.mode == ImageEditMode.revision && data.referenceSlots > 0)
          _ReferencePictures(
            files: data.referenceFiles,
            bytes: data.referenceBytes,
            slots: data.referenceSlots,
            busy: data.busy,
            onSelect: data.onSelectReference,
            onClear: data.onClearReference,
          ),
        if (data.sourceBytes != null) _SelectedSourcePreview(data: data),
        IiOsGap.vMd,
      ],
    );
  }
}

class _SelectedSourcePreview extends StatelessWidget {
  const _SelectedSourcePreview({required this.data});

  final _ImageEditUiState data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: IiOsSpacing.md),
      child: data.mode == ImageEditMode.inpaint
          ? InpaintRegionSelector(
              imageBytes: data.sourceBytes,
              imageUrl: null,
              aspectRatio: data.imageAspectRatio,
              masks: data.maskRegions,
              allowMultiple:
                  data.selectedTemplate != null &&
                  imageEditAllowsMultipleRegions(data.selectedTemplate!),
              enabled: !data.busy,
              onChanged: data.onMasksChanged,
              onClear: data.maskRegions.isEmpty ? null : data.onClearMasks,
            )
          : ImageEditPreview(
              imageBytes: data.sourceBytes,
              imageUrl: null,
              aspectRatio: data.imageAspectRatio,
            ),
    );
  }
}

class _ImageEditPromptControls extends StatelessWidget {
  const _ImageEditPromptControls({required this.data});

  final _ImageEditUiState data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: data.prompt,
          enabled: !data.busy,
          minLines: 4,
          maxLines: 8,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: data.mode == ImageEditMode.inpaint
                ? 'Area instruction'
                : 'Edit instruction',
            alignLabelWithHint: true,
          ),
        ),
        if (data.promptEnhance case final binding?)
          PromptEnhanceBar(
            controller: data.prompt,
            binding: binding,
            enabled: !data.busy,
          ),
        if (data.showsSourceAdherence) ...[
          IiOsGap.vSm,
          IiOsPresetScale(
            label: 'How closely to follow the original',
            presets: sourceAdherencePresets,
            value: data.controlStrength,
            minimum: sourceAdherenceMinimum,
            maximum: sourceAdherenceMaximum,
            divisions: 28,
            onChanged: data.busy ? null : data.onControlStrengthChanged,
          ),
        ],
        IiOsGap.vXs,
        TextField(
          controller: data.seed,
          enabled: !data.busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Seed (optional)'),
        ),
        IiOsGap.vLg,
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed:
                data.busy ||
                    data.loadingTemplates ||
                    data.enabledTemplates.isEmpty
                ? null
                : data.onSubmit,
            icon: data.busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.play, size: 17),
            label: Text(
              data.busy
                  ? data.busyLabel
                  : data.useAll
                  ? 'Compare ${data.enabledTemplates.length} models'
                  : 'Launch job',
            ),
          ),
        ),
      ],
    );
  }
}
