import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/character.dart';
import 'package:ii_os/models/character_generation_state.dart';

void main() {
  const oldImage = CharacterImageModel(
    jobId: 'old-job',
    path: 'old.png',
    generation: '1',
    contentType: 'image/png',
    url: '',
    selected: true,
    createdAt: null,
  );
  const editedImage = CharacterImageModel(
    jobId: 'edit-job',
    path: 'edited.png',
    generation: '2',
    contentType: 'image/png',
    url: '',
    selected: false,
    createdAt: null,
  );

  test('keeps a distinct pending image until its job artifact appears', () {
    expect(
      pendingCharacterImageJobId(
        jobId: 'edit-job',
        status: 'running',
        images: const [oldImage],
      ),
      'edit-job',
    );
    expect(
      pendingCharacterImageJobId(
        jobId: 'edit-job',
        status: 'running',
        images: const [oldImage, editedImage],
      ),
      isNull,
    );
  });

  test('finds the artifact produced by the completed edit job', () {
    expect(
      characterImageForJob(const [oldImage, editedImage], 'edit-job'),
      same(editedImage),
    );
  });

  test('switches selection locally without replacing signed image data', () {
    final images = selectCharacterImageLocally(const [
      oldImage,
      editedImage,
    ], editedImage);

    expect(images.first.selected, isFalse);
    expect(images.last.selected, isTrue);
    expect(images.last.url, editedImage.url);
    expect(images.last.path, editedImage.path);
  });

  test('only active generation states block another edit', () {
    expect(isActiveCharacterGenerationStatus('dispatched'), isTrue);
    expect(isActiveCharacterGenerationStatus('running'), isTrue);
    expect(isActiveCharacterGenerationStatus('completed'), isFalse);
    expect(isActiveCharacterGenerationStatus('failed'), isFalse);
    expect(shouldLoadCharacterImagesForGenerationStatus('dispatched'), isFalse);
    expect(shouldLoadCharacterImagesForGenerationStatus('running'), isFalse);
    expect(shouldLoadCharacterImagesForGenerationStatus('completed'), isTrue);
    expect(shouldLoadCharacterImagesForGenerationStatus('failed'), isFalse);
  });
}
