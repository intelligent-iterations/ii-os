import 'models.dart';

enum ImageGenerationMode { prompt, references }

const defaultImageAspectRatios = ['1:1', '4:3', '3:4', '16:9', '9:16'];
const maximumImageSeed = 2147483647;

String generatedImageSeed(DateTime now) =>
    '${now.microsecondsSinceEpoch % maximumImageSeed}';

String initialImageAspectRatio(List<String> values) =>
    values.isEmpty ? '1:1' : values.first;

({double width, double height}) imageAspectDimensions(String value) {
  final dimensions = value.split(':');
  final width = dimensions.isEmpty ? null : double.tryParse(dimensions.first);
  final height = dimensions.length < 2 ? null : double.tryParse(dimensions[1]);
  return (width: width ?? 1, height: height ?? 1);
}

final class ImageWorkflowCapabilities {
  const ImageWorkflowCapabilities({
    required this.maximumReferenceImages,
    required this.supportsSourceAdherence,
    required this.aspectRatios,
  });

  final int maximumReferenceImages;
  final bool supportsSourceAdherence;
  final List<String> aspectRatios;

  bool get requiresReferenceImages => maximumReferenceImages > 0;
  int get additionalReferenceImages =>
      maximumReferenceImages > 0 ? maximumReferenceImages - 1 : 0;
}

ImageWorkflowCapabilities imageCapabilities(WorkflowTemplateModel template) =>
    ImageWorkflowCapabilities(
      maximumReferenceImages: _orderedReferenceCount(template.inputs),
      supportsSourceAdherence: template.inputs.containsKey('control_strength'),
      aspectRatios: _aspectRatios(template),
    );

List<WorkflowTemplateModel> imageGenerationTemplatesForMode(
  List<WorkflowTemplateModel> templates,
  ImageGenerationMode mode,
) => templates
    .where((template) {
      final acceptsReferences = imageCapabilities(
        template,
      ).requiresReferenceImages;
      return switch (mode) {
        ImageGenerationMode.prompt => !acceptsReferences,
        ImageGenerationMode.references => acceptsReferences,
      };
    })
    .toList(growable: false);

int _orderedReferenceCount(Map<String, WorkflowInputModel> inputs) {
  if (!inputs.containsKey('source_asset_id')) return 0;
  var count = 1;
  while (inputs.containsKey('source_asset_id_${count + 1}')) {
    count++;
  }
  return count;
}

List<String> _aspectRatios(WorkflowTemplateModel template) {
  final input = template.inputs['aspect_ratio'];
  if (input == null) return const [];
  final declared = input.allowedValues;
  if (declared.isNotEmpty) return declared;
  return defaultImageAspectRatios;
}
