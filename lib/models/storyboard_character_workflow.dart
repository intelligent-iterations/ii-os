import 'character.dart';
import 'models.dart';

bool storyboardHasSelectedCharacterReference({
  required Set<String> characterIds,
  required List<CharacterModel> characters,
}) {
  for (final character in characters) {
    if (characterIds.contains(character.id) &&
        character.selectedImage != null) {
      return true;
    }
  }
  return false;
}

WorkflowTemplateModel? storyboardGenerationTemplate({
  required Set<String> characterIds,
  required List<CharacterModel> characters,
  required List<WorkflowTemplateModel> templates,
  bool hasPanelReference = false,
}) {
  final workflowId =
      hasPanelReference ||
          storyboardHasSelectedCharacterReference(
            characterIds: characterIds,
            characters: characters,
          )
      ? 'image-edit-qwen-2511'
      : 'image-create';
  final matches = templates
      .where((template) => template.workflowId == workflowId)
      .toList(growable: false);
  for (final template in matches) {
    if (template.enabled) return template;
  }
  return matches.isEmpty ? null : matches.first;
}

String? storyboardGenerationModelInputFor(String workflowId) =>
    switch (workflowId) {
      'image-create-flux2-klein' => 'flux2-klein',
      'image-create-qwen-2512' => 'qwen-image-2512',
      _ => null,
    };
