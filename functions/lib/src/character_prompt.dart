final class CharacterPromptFeature {
  const CharacterPromptFeature(this.answerKey, this.label);

  final String answerKey;
  final String label;
}

final class CharacterPromptSection {
  const CharacterPromptSection(this.label, this.features);

  final String label;
  final List<CharacterPromptFeature> features;
}

const characterHeadPromptSections = <CharacterPromptSection>[
  CharacterPromptSection('Art direction', [
    CharacterPromptFeature('artStyle', 'art style'),
  ]),
  CharacterPromptSection('Character identity', [
    CharacterPromptFeature('characterIdentity', 'character identity'),
  ]),
  CharacterPromptSection('Overall appearance and complexion', [
    CharacterPromptFeature('overallAppearance', 'overall appearance'),
    CharacterPromptFeature('skinTone', 'skin tone and undertone'),
  ]),
  CharacterPromptSection('Facial structure', [
    CharacterPromptFeature('faceShape', 'face shape'),
    CharacterPromptFeature('cheekbonesAndCheeks', 'cheekbones and cheeks'),
    CharacterPromptFeature('jawAndChin', 'jaw and chin'),
  ]),
  CharacterPromptSection('Facial features', [
    CharacterPromptFeature('nose', 'nose'),
    CharacterPromptFeature('eyes', 'eyes'),
    CharacterPromptFeature('eyebrows', 'eyebrows'),
    CharacterPromptFeature('lips', 'lips'),
    CharacterPromptFeature('ears', 'ears'),
  ]),
  CharacterPromptSection('Hair', [
    CharacterPromptFeature('hairTypeAndTexture', 'hair type and texture'),
    CharacterPromptFeature('hairStyle', 'hair style'),
    CharacterPromptFeature('hairline', 'hairline'),
  ]),
  CharacterPromptSection('Distinctive features', [
    CharacterPromptFeature('physicalQuirks', 'physical quirks'),
    CharacterPromptFeature('identifiableMarks', 'identifiable marks'),
    CharacterPromptFeature('recognizableFeatures', 'recognizable features'),
  ]),
  CharacterPromptSection('Expression', [
    CharacterPromptFeature('expression', 'expression'),
  ]),
  CharacterPromptSection('Clothing and accessories', [
    CharacterPromptFeature('clothing', 'clothing'),
    CharacterPromptFeature('visibleClothing', 'visible clothing'),
    CharacterPromptFeature('accessories', 'accessories'),
  ]),
];

const characterBodyPromptFeatures = <CharacterPromptFeature>[
  CharacterPromptFeature(
    'heightBuildSilhouetteProportions',
    'height, build, silhouette and proportions',
  ),
  CharacterPromptFeature(
    'neckShouldersUpperTorso',
    'neck, shoulders and upper torso',
  ),
  CharacterPromptFeature('chestWaistAbdomen', 'chest, waist and abdomen'),
  CharacterPromptFeature('hipsPelvisSeat', 'hips, pelvis and seat'),
  CharacterPromptFeature('armsHands', 'arms and hands'),
  CharacterPromptFeature('legsFeet', 'legs and feet'),
  CharacterPromptFeature(
    'postureAsymmetries',
    'posture and bodily asymmetries',
  ),
  CharacterPromptFeature(
    'identifyingBodilyDetails',
    'identifying bodily details and important proportions',
  ),
];

const characterClothingPromptFeatures = <CharacterPromptFeature>[
  CharacterPromptFeature(
    'outfitConceptSettingSilhouette',
    'outfit concept, setting and silhouette',
  ),
  CharacterPromptFeature(
    'completeGarmentsLayering',
    'complete garments and layering',
  ),
  CharacterPromptFeature('upperGarment', 'upper garment'),
  CharacterPromptFeature('lowerGarment', 'lower garment'),
  CharacterPromptFeature(
    'outerwearDrapedGarment',
    'outerwear or draped garment',
  ),
  CharacterPromptFeature(
    'materialsColorsDecorativeDetails',
    'materials, colors and decorative details',
  ),
  CharacterPromptFeature(
    'headwearHairstyleInteraction',
    'headwear and hairstyle interaction',
  ),
  CharacterPromptFeature('legwearFootwear', 'legwear and footwear'),
  CharacterPromptFeature(
    'accessoriesClosuresCarriedObjects',
    'accessories, closures and carried objects',
  ),
];

final characterAnswerKeys = List<String>.unmodifiable(
  characterHeadPromptSections.expand(
    (section) => section.features.map((feature) => feature.answerKey),
  ),
);

final characterBodyAnswerKeys = List<String>.unmodifiable(
  characterBodyPromptFeatures.map((feature) => feature.answerKey),
);

final characterClothingAnswerKeys = List<String>.unmodifiable(
  characterClothingPromptFeatures.map((feature) => feature.answerKey),
);

const characterSheetSpecification =
    '''Create a character sheet that follows every requirement below:

- One character shown in three views.
- Shoulders and head visible, cropped at the upper chest.
- Head, neck and shoulders rotate together naturally.
- The three images represent a continuous rotation in one direction:
  1. Front view \u2014 0°. Both sides of the face are equally visible.
  2. Exact side profile \u2014 90°. Only one eye is visible, with a clear forehead, nose, lips and chin silhouette.
  3. Exact back view \u2014 180°. The back of the head, hairstyle, ears, neck and shoulders are fully visible with no facial features visible.
- Three equally sized portraits arranged in one horizontal row.
- Eye-level camera with minimal perspective distortion.
- Identical camera distance and character scale in every view.
- Soft, neutral studio lighting from the front.
- Pure white seamless background.
- Facial structure, asymmetries, skin details, hairstyle, clothing, proportions, expression and lighting remain identical between views.
- No text, angle labels, borders, props, scenery or additional characters.
- No cropped hair or missing shoulders.''';

String buildCharacterSheetPrompt(Map<String, String> answers) {
  final details = _characterHeadDetails(answers);

  return '$characterSheetSpecification\n\nCharacter details:\n\n$details';
}

String _characterHeadDetails(Map<String, String> answers) {
  final blocks = characterHeadPromptSections
      .map((section) => _block(section.label, section.features, answers))
      .where((block) => block.isNotEmpty)
      .toList();

  return blocks.join('\n\n');
}

String buildCharacterBodyPrompt(
  Map<String, String> headAnswers,
  Map<String, String> bodyAnswers,
  Map<String, String> clothingAnswers,
) {
  final head = _characterHeadDetails(headAnswers);
  final body = _lines(characterBodyPromptFeatures, bodyAnswers);
  final clothing = _lines(characterClothingPromptFeatures, clothingAnswers);
  return '''FULL-BODY CHARACTER TURNAROUND

HEAD:
The head looks like:
${head.isEmpty ? 'No additional details supplied.' : head}

BODY:
The body looks like:
$body

CLOTHING:
$clothing

COMPOSITION:
Create three equally sized, complete head-to-toe figures arranged in one horizontal row. The full figure must be visible from the top of the hair to the soles of the feet, with enough margin around the body to inspect the silhouette, outfit construction, hands and footwear.

VIEWS:
The views show one continuous rotation in the same direction:
1. Direct front view, 0 degrees. Both sides of the body equally visible.
2. Exact 90 degree side profile. Clean head-to-toe side silhouette.
3. Exact 180 degree back view. Back of the head, clothing and body fully visible.

POSE:
Neutral standing reference pose. Head level, spine naturally aligned, weight distributed evenly between both feet, feet hip-width apart, knees straight but not rigidly locked. Arms relaxed and held slightly away from the torso. Hands relaxed and completely visible.

CONSISTENCY:
Maintain exactly the same character, body proportions, height, facial identity, hairstyle, clothing construction, garment lengths, colors, materials, decorative placement and accessories described above.

CAMERA AND BACKGROUND:
Straight-on orthographic character-design presentation. Camera centred around the character\u2019s mid-body and positioned far enough away to minimize perspective distortion. Soft neutral studio lighting. Pure white seamless background.

Do not include text, labels, borders, scenery, furniture, props or additional characters. Do not crop the head, hair, hands, clothing or feet.''';
}

List<String> missingCharacterAnswers(Map<String, String> answers) {
  return characterAnswerKeys
      .where((key) => (answers[key] ?? '').trim().isEmpty)
      .toList();
}

String _lines(
  List<CharacterPromptFeature> features,
  Map<String, String> answers,
) {
  final lines = features
      .map((feature) => _field(feature, answers[feature.answerKey]))
      .where((line) => line.isNotEmpty)
      .toList();
  return lines.isEmpty ? 'No additional details supplied.' : lines.join('\n');
}

String _block(
  String label,
  List<CharacterPromptFeature> features,
  Map<String, String> answers,
) {
  final lines = features
      .map((feature) => _field(feature, answers[feature.answerKey]))
      .where((line) => line.isNotEmpty)
      .toList();
  return lines.isEmpty ? '' : '$label:\n${lines.join('\n')}';
}

String _field(CharacterPromptFeature feature, String? value) {
  final description = value?.trim() ?? '';
  if (description.isEmpty) return '';
  return '- ${feature.label}: $description';
}
