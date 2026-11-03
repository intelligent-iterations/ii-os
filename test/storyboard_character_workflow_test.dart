import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/models/storyboard_character_workflow.dart';

void main() {
  test(
    'selected character sheets switch storyboard generation to image edit',
    () {
      const character = CharacterModel(
        id: 'character-1',
        workspaceId: 'workspace-1',
        name: 'Mara',
        answers: {},
        prompt: 'Mara reference',
        status: 'ready',
        thumbnailUrl: null,
        selectedImage: CharacterImageReference(
          jobId: 'job-1',
          path: 'head.png',
          generation: '1',
          contentType: 'image/png',
        ),
        createdAt: null,
        updatedAt: null,
      );
      final selected = storyboardGenerationTemplate(
        characterIds: {'character-1'},
        characters: const [character],
        templates: [
          _template('create', 'image-create'),
          _template('edit', 'image-edit'),
          _template('qwen', 'image-edit-qwen-2511'),
        ],
      );

      expect(selected?.workflowId, 'image-edit-qwen-2511');
    },
  );

  test('storyboards without selected character images use text to image', () {
    final selected = storyboardGenerationTemplate(
      characterIds: const {},
      characters: const [],
      templates: [
        _template('edit', 'image-edit'),
        _template('create', 'image-create'),
      ],
    );

    expect(selected?.workflowId, 'image-create');
  });

  test('selected panel images switch storyboard generation to Qwen edit', () {
    final selected = storyboardGenerationTemplate(
      characterIds: const {},
      characters: const [],
      hasPanelReference: true,
      templates: [
        _template('create', 'image-create'),
        _template('qwen', 'image-edit-qwen-2511'),
      ],
    );

    expect(selected?.workflowId, 'image-edit-qwen-2511');
  });

  test('character-free panels choose Z-Image, not another create model', () {
    final selected = storyboardGenerationTemplate(
      characterIds: const {},
      characters: const [],
      templates: [
        _template('qwen-create', 'image-create-qwen-2512'),
        _template('flux-create', 'image-create-flux2-klein'),
        _template('z-image', 'image-create'),
      ],
    );

    expect(selected?.id, 'z-image');
    expect(selected?.workflowId, 'image-create');
  });
}

WorkflowTemplateModel _template(String id, String workflowId) =>
    WorkflowTemplateModel(
      id: id,
      workflowId: workflowId,
      version: '1',
      displayName: id,
      model: id,
      repository: 'acme/media',
      enabled: true,
      disabledReason: '',
    );
