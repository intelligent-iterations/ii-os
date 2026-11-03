import 'dart:convert';

import 'api_error.dart';

final class PromptImageReference {
  const PromptImageReference({
    required this.imageNumber,
    required this.role,
    required this.label,
  });

  final int imageNumber;
  final String role;
  final String label;
}

final class StoryboardPanelReferenceSource {
  const StoryboardPanelReferenceSource({
    required this.panelId,
    required this.sourceJobId,
    required this.selectedImage,
  });

  final String panelId;
  final String sourceJobId;
  final Map<String, Object?>? selectedImage;
}

List<String> storyboardPanelReferenceIds(Object? value) => value is List
    ? value.whereType<String>().where((id) => id.isNotEmpty).toSet().toList()
    : const [];

Map<String, Object?> storyboardReferenceWorkflowInput({
  required Map<String, Object?> requestedInput,
  required List<String> referenceAssetIds,
}) {
  if (referenceAssetIds.isEmpty || referenceAssetIds.length > 3) {
    throw const ApiError(
      409,
      'storyboard_reference_assets_invalid',
      'Storyboard generation requires between 1 and 3 reference images.',
    );
  }
  final input = {...requestedInput}
    ..remove('mode')
    ..remove('source_asset_id')
    ..remove('source_asset_id_2')
    ..remove('source_asset_id_3');
  return {
    ...input,
    'mode': 'edit',
    'source_asset_id': referenceAssetIds[0],
    if (referenceAssetIds.length > 1) 'source_asset_id_2': referenceAssetIds[1],
    if (referenceAssetIds.length > 2) 'source_asset_id_3': referenceAssetIds[2],
    'control_strength': requestedInput['control_strength'] ?? 0.65,
  };
}

String storyboardReferencePrompt(List<PromptImageReference> references) {
  if (references.isEmpty) return '';
  for (var index = 0; index < references.length; index++) {
    if (references[index].imageNumber != index + 1) {
      throw const ApiError(
        500,
        'storyboard_reference_map_invalid',
        'The storyboard reference-image map is not aligned with its inputs.',
      );
    }
  }
  final buffer = StringBuffer('Reference-image mapping (authoritative):\n');
  for (final reference in references) {
    final image = 'Image ${reference.imageNumber}';
    final label = jsonEncode(_singleLine(reference.label));
    switch (reference.role) {
      case 'source_scene':
        buffer.writeln('- $image is the source scene from $label.');
        break;
      case 'scene_reference':
        buffer.writeln(
          '- $image is a visual continuity reference from $label.',
        );
        break;
      case 'character':
        buffer.writeln('- $image refers to $label.');
        break;
      default:
        throw const ApiError(
          500,
          'storyboard_reference_map_invalid',
          'The storyboard reference-image map contains an invalid role.',
        );
    }
  }
  final characters = references
      .where((reference) => reference.role == 'character')
      .toList(growable: false);
  if (characters.isNotEmpty) {
    buffer.writeln(
      'Match each exact character name to its mapped image, including that '
      'character\u2019s actions, positions, interactions, and props.',
    );
    buffer.writeln(
      'Character references are authoritative for exact identity and design '
      'nuances. Preserve face and feature shapes, skin tone, hair, body '
      'proportions, clothing, accessories, distinctive marks, and recurring '
      'details. Maintain each character as an individual with those exact '
      'traits throughout the scene.',
    );
    buffer.writeln(
      'Use the character references as the primary art-style anchor for the '
      'whole scene, including medium, linework, rendering, color treatment, '
      'shading, and texture. Keep the frame stylistically cohesive with those '
      'references. Apply a restyle when the scene instruction explicitly '
      'requests one.',
    );
    if (references.any((reference) => reference.role == 'source_scene')) {
      buffer.writeln(
        'Preserve the source scene\u2019s composition, setting, props, and spatial '
        'continuity, but render the complete frame cohesively in the character '
        'references\u2019 visual language. Keep each character\u2019s established '
        'identity and design authoritative over differing source-scene cues.',
      );
    }
    buffer.writeln(
      'Render a complete scene composition with natural scene framing and '
      'background. Use reference sheets as identity and style sources.',
    );
  }
  if (characters.isNotEmpty) {
    buffer.writeln(
      'Match each named character only to that character\u2019s numbered reference.',
    );
  }
  buffer.write(
    'Names and reference labels are semantic metadata. The finished frame is a '
    'purely visual composition by default. Visible lettering is limited to the '
    'exact text explicitly requested by the scene instruction.',
  );
  return buffer.toString();
}

List<StoryboardPanelReferenceSource> storyboardPanelReferenceSources({
  required List<Map<String, Object?>> panels,
  required List<String> referencePanelIds,
}) {
  final panelsById = {
    for (final panel in panels)
      if (panel['id'] case final String id when id.isNotEmpty) id: panel,
  };
  return referencePanelIds
      .map((panelId) {
        final panel = panelsById[panelId];
        if (panel == null) {
          throw const ApiError(
            409,
            'storyboard_panel_reference_not_found',
            'A selected panel reference no longer exists in this storyboard.',
          );
        }
        final selectedImage = storyboardSelectedPanelImage(panel);
        final sourceJobId = selectedImage?['jobId'] ?? panel['jobId'];
        if (sourceJobId is! String || sourceJobId.isEmpty) {
          throw const ApiError(
            409,
            'storyboard_panel_reference_image_required',
            'Generate the selected panel before using it as a reference.',
          );
        }
        return StoryboardPanelReferenceSource(
          panelId: panelId,
          sourceJobId: sourceJobId,
          selectedImage: selectedImage,
        );
      })
      .toList(growable: false);
}

Map<String, Object?>? storyboardSelectedPanelImage(Map<String, Object?> panel) {
  final value = panel['selectedImage'];
  if (value is! Map) return null;
  final selected = value.cast<String, Object?>();
  return selected['jobId'] is String &&
          (selected['jobId'] as String).isNotEmpty &&
          selected['path'] is String &&
          (selected['path'] as String).isNotEmpty &&
          selected['generation'] is String &&
          (selected['generation'] as String).isNotEmpty
      ? selected
      : null;
}

String _singleLine(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');
