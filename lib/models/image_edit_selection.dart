import 'dart:ui' show Rect;

import 'image_workflow_capabilities.dart';
import 'inpaint_mask.dart';
import 'models.dart';

enum ImageEditMode { revision, inpaint }

String imageEditWorkflowId(ImageEditMode mode) =>
    mode == ImageEditMode.inpaint ? 'image-inpaint' : 'image-edit';

bool isImageEditWorkflowForMode(String workflowId, ImageEditMode mode) {
  final base = imageEditWorkflowId(mode);
  return workflowId == base || workflowId.startsWith('$base-');
}

List<WorkflowTemplateModel> imageEditTemplatesForMode(
  List<WorkflowTemplateModel> templates,
  ImageEditMode mode,
) => templates
    .where(
      (template) =>
          isImageEditWorkflowForMode(template.workflowId, mode) &&
          template.workflowId != 'image-inpaint',
    )
    .toList(growable: false);

List<WorkflowTemplateModel> enabledImageEditTemplates(
  List<WorkflowTemplateModel> templates,
  ImageEditMode mode,
) => imageEditTemplatesForMode(
  templates,
  mode,
).where((template) => template.enabled).toList(growable: false);

WorkflowTemplateModel? selectedImageEditTemplate({
  required List<WorkflowTemplateModel> templates,
  required ImageEditMode mode,
  required String? selectedId,
}) {
  final matches = imageEditTemplatesForMode(templates, mode);
  for (final template in matches) {
    if (template.id == selectedId && template.enabled) return template;
  }
  for (final template in matches) {
    if (template.enabled) return template;
  }
  return matches.firstOrNull;
}

List<WorkflowTemplateModel> imageEditSubmissionTargets({
  required List<WorkflowTemplateModel> templates,
  required ImageEditMode mode,
  required String? selectedId,
  required bool useAll,
}) {
  final enabled = enabledImageEditTemplates(templates, mode);
  if (useAll) return enabled;
  final selected = selectedImageEditTemplate(
    templates: templates,
    mode: mode,
    selectedId: selectedId,
  );
  return selected?.enabled == true ? [selected!] : const [];
}

RuntimeEstimateSnapshot? imageEditRuntimeEstimate(
  Iterable<WorkflowTemplateModel> targets,
) {
  RuntimeEstimateSnapshot? slowest;
  for (final target in targets) {
    final estimate = target.estimateRuntime(const {});
    if (estimate != null &&
        (slowest == null ||
            estimate.estimatedSeconds > slowest.estimatedSeconds)) {
      slowest = estimate;
    }
  }
  return slowest;
}

JsonMap imageEditInputForTarget({
  required WorkflowTemplateModel target,
  required JsonMap baseInput,
  required List<String> referenceAssetIds,
  List<Rect> maskRegions = const [],
}) {
  final input = <String, Object?>{
    for (final entry in baseInput.entries)
      if (target.inputs.containsKey(entry.key)) entry.key: entry.value,
  };
  final slots = imageEditReferenceSlots(target);
  for (
    var index = 0;
    index < referenceAssetIds.length && index < slots;
    index++
  ) {
    input['source_asset_id_${index + 2}'] = referenceAssetIds[index];
  }
  if (target.inputs.containsKey('mask_regions') && maskRegions.isNotEmpty) {
    input['mask_regions'] = encodeInpaintMaskRegions(maskRegions);
  }
  return input;
}

int imageEditReferenceSlots(WorkflowTemplateModel template) =>
    imageCapabilities(template).additionalReferenceImages;

int maximumImageEditReferenceSlots(Iterable<WorkflowTemplateModel> templates) =>
    templates.fold(0, (maximum, template) {
      final slots = imageEditReferenceSlots(template);
      return slots > maximum ? slots : maximum;
    });

bool imageEditSupportsSourceAdherence(WorkflowTemplateModel template) =>
    imageCapabilities(template).supportsSourceAdherence;

bool imageEditAllowsMultipleRegions(WorkflowTemplateModel template) =>
    template.inputs.containsKey('mask_regions');

final class ImageEditSubmission {
  const ImageEditSubmission.success({
    required this.template,
    required JsonMap response,
  }) : result = response,
       error = null;

  const ImageEditSubmission.failure({
    required this.template,
    required Object failure,
  }) : result = null,
       error = failure;

  final WorkflowTemplateModel template;
  final JsonMap? result;
  final Object? error;

  bool get succeeded => result != null;
}
