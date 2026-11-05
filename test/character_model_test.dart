import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';

void main() {
  test('parses character progress and lifecycle', () {
    final model = CharacterModel.fromJson({
      'id': 'character-1',
      'workspaceId': 'workspace-1',
      'name': 'Example hero',
      'goal': 'Lead character',
      'answers': {'artStyle': 'Concept art', 'nose': 'Broad nose'},
      'prompt': 'Saved prompt',
      'bodyAnswers': {
        'heightBuildSilhouetteProportions': 'Short and softly built',
      },
      'clothingAnswers': {'upperGarment': 'Burgundy blouse'},
      'bodyPrompt': 'Saved body prompt',
      'status': 'draft',
      'thumbnailUrl': 'https://example.test/selected.png',
      'selectedImage': {
        'jobId': 'job-122',
        'path': 'workspaces/workspace-1/runs/job-122/character.png',
        'generation': '42',
        'contentType': 'image/png',
      },
      'generationJobIds': ['job-122', 'job-123'],
      'lastGenerationJobId': 'job-123',
      'lastGenerationRequestedAt': '2026-07-14T10:04:00.000Z',
      'selectedBodyImage': {
        'jobId': 'job-124',
        'path': 'workspaces/workspace-1/runs/job-124/body.png',
        'generation': '43',
        'contentType': 'image/png',
      },
      'bodyGenerationJobIds': ['job-124'],
      'lastBodyGenerationJobId': 'job-124',
      'lastBodyGenerationRequestedAt': '2026-07-14T10:06:00.000Z',
      'createdAt': '2026-07-14T10:00:00.000Z',
      'updatedAt': '2026-07-14T10:05:00.000Z',
    });

    expect(model.name, 'Example hero');
    expect(model.isDraft, isTrue);
    expect(model.answeredQuestions, 2);
    expect(model.lastGenerationJobId, 'job-123');
    expect(model.generationJobIds, ['job-122', 'job-123']);
    expect(model.selectedImage?.generation, '42');
    expect(model.answeredBodyQuestions, 1);
    expect(model.answeredClothingQuestions, 1);
    expect(model.bodyPrompt, 'Saved body prompt');
    expect(model.selectedBodyImage?.generation, '43');
    expect(model.lastBodyGenerationJobId, 'job-124');
    expect(model.thumbnailUrl, contains('selected.png'));
    expect(model.lastGenerationRequestedAt, isNotNull);
    expect(model.updatedAt, isNotNull);
  });

  test('parses selectable generated character images', () {
    final image = CharacterImageModel.fromJson({
      'jobId': 'job-123',
      'path': 'workspaces/workspace-1/runs/job-123/character.webp',
      'generation': '99',
      'contentType': 'image/webp',
      'url': 'https://example.test/character.webp',
      'sourceImage': true,
      'editLabel': 'Area edit: Smaller chest patch',
      'urlError': {
        'code': 'workspace_not_connected',
        'message': 'Reconnect the workspace to view this sheet.',
      },
      'selected': true,
      'createdAt': '2026-07-15T10:00:00.000Z',
    });

    expect(image.filename, 'character.webp');
    expect(image.selected, isTrue);
    expect(image.isSourceImage, isTrue);
    expect(image.editLabel, 'Area edit: Smaller chest patch');
    expect(image.urlErrorCode, 'workspace_not_connected');
    expect(
      image.urlErrorMessage,
      'Reconnect the workspace to view this sheet.',
    );
    expect(image.createdAt, isNotNull);
  });

  test('parses a complete immutable character image read grant', () {
    final image = CharacterImageModel.fromJson({
      'workspaceId': 'workspace-1',
      'jobId': 'job-123',
      'path': 'workspaces/workspace-1/runs/job-123/character.png',
      'generation': '99',
      'contentType': 'image/png',
      'sizeBytes': 2048,
      'sha256': List.filled(64, 'a').join(),
      'readGrant': {
        'url': 'https://workspace-bucket.storage.googleapis.com/object',
        'expiresAt': '2026-07-23T20:00:00.000Z',
        'workspaceId': 'workspace-1',
        'jobId': 'job-123',
        'bucket': 'workspace-bucket',
        'object': 'workspaces/workspace-1/runs/job-123/character.png',
        'generation': '99',
        'sizeBytes': 2048,
        'sha256': List.filled(64, 'a').join(),
        'contentType': 'image/png',
      },
      'selected': true,
    });

    expect(image.hasReadGrant, isTrue);
    expect(image.workspaceId, 'workspace-1');
    expect(image.bucket, 'workspace-bucket');
    expect(image.sizeBytes, 2048);

    final changedObject = CharacterImageModel.fromJson({
      'workspaceId': 'workspace-1',
      'jobId': 'job-123',
      'path': 'workspaces/workspace-1/runs/job-123/character.png',
      'generation': '99',
      'contentType': 'image/png',
      'sizeBytes': 2048,
      'sha256': List.filled(64, 'a').join(),
      'readGrant': {
        'url': 'https://workspace-bucket.storage.googleapis.com/object',
        'expiresAt': '2026-07-23T20:00:00.000Z',
        'workspaceId': 'workspace-1',
        'jobId': 'job-123',
        'bucket': 'workspace-bucket',
        'object': 'workspaces/workspace-1/runs/job-123/other.png',
        'generation': '99',
        'sizeBytes': 2048,
        'sha256': List.filled(64, 'a').join(),
        'contentType': 'image/png',
      },
    });
    expect(changedObject.hasReadGrant, isFalse);
  });

  test('only scratch drafts open the interview builder', () {
    final scratch = CharacterModel.fromJson({
      'id': 'scratch-1',
      'workspaceId': 'workspace-1',
      'name': 'Scratch',
      'creationMode': 'scratch',
      'status': 'draft',
    });
    final image = CharacterModel.fromJson({
      'id': 'image-1',
      'workspaceId': 'workspace-1',
      'name': 'Image',
      'creationMode': 'image',
      'status': 'draft',
      'sourceAssetId': 'source-1',
    });

    expect(scratch.opensScratchBuilder, isTrue);
    expect(image.opensScratchBuilder, isFalse);
    expect(image.isImageBased, isTrue);
  });

  test('image character lifecycle is based on its generated artifact', () {
    CharacterModel image({
      String? jobId,
      String? generationStatus,
      CharacterImageReference? selected,
    }) => CharacterModel.fromJson({
      'id': 'image-1',
      'workspaceId': 'workspace-1',
      'name': 'Image',
      'creationMode': 'image',
      'status': 'ready',
      'sourceAssetId': 'source-1',
      'lastBodyGenerationJobId': jobId,
      'lastBodyGenerationStatus': generationStatus,
      if (selected != null)
        'selectedImage': {
          'jobId': selected.jobId,
          'path': selected.path,
          'generation': selected.generation,
          'contentType': selected.contentType,
        },
    });

    expect(image().presentationStatus, 'needs generation');
    expect(
      image(jobId: 'job-1', generationStatus: 'running').presentationStatus,
      'generating',
    );
    expect(
      image(jobId: 'job-1', generationStatus: 'failed').presentationStatus,
      'failed',
    );
    expect(
      image(jobId: 'job-1', generationStatus: 'completed').presentationStatus,
      'failed',
    );
    expect(
      image(
        jobId: 'job-1',
        generationStatus: 'completed',
        selected: const CharacterImageReference(
          jobId: 'job-1',
          path: 'workspaces/workspace-1/runs/job-1/image.png',
          generation: '42',
          contentType: 'image/png',
        ),
      ).presentationStatus,
      'ready',
    );
  });

  test('questionnaire keeps the required 22 character-sheet questions', () {
    expect(characterQuestions, hasLength(22));
    expect(characterQuestions.first.question, 'What art style should be used?');
    expect(
      characterQuestions.last.question,
      'Is there anything else that must remain recognizable?',
    );
    expect(
      characterQuestions
          .singleWhere((question) => question.key == 'physicalQuirks')
          .guidance,
      contains('anatomical direction'),
    );
  });

  test('body questionnaire keeps the condensed body and clothing interviews', () {
    expect(characterBodyQuestions, hasLength(8));
    expect(characterClothingQuestions, hasLength(9));
    expect(
      characterBodyQuestions.first.question,
      'What are the character\u2019s height, overall build, silhouette and proportions?',
    );
    expect(
      characterClothingQuestions.last.question,
      'What accessories, closures or carried objects are included?',
    );
  });
}
