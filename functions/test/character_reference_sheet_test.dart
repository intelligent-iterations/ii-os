import 'package:ii_os_functions/src/character_reference_sheet.dart';
import 'package:test/test.dart';

void main() {
  test('selected references use the selected body sheet', () {
    final references = selectedCharacterReferenceImages(const [
      {
        'id': 'character-1',
        'name': 'Jenny',
        'selectedImage': {
          'path': 'head.png',
          'generation': '1',
          'contentType': 'image/jpeg',
        },
        'selectedBodyImage': {
          'path': 'body.png',
          'generation': '2',
          'contentType': 'image/png',
        },
      },
    ]);

    expect(references.map((item) => item.path), ['body.png']);
    expect(references.single.characterId, 'character-1');
    expect(references.single.name, 'Jenny');
    expect(references.single.contentType, 'image/png');
    expect(characterReferenceFilename(references.single.name), 'Jenny.png');
  });
}
