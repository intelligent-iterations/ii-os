import 'package:ii_os_functions/src/character_prompt.dart';
import 'package:test/test.dart';

void main() {
  test('assembles every answer beneath the permanent three-view rules', () {
    final answers = {
      for (final key in characterAnswerKeys) key: 'Answer for $key',
    };

    final prompt = buildCharacterSheetPrompt(answers);

    expect(prompt, startsWith('Create a character sheet'));
    expect(prompt, contains('Front view \u2014 0°'));
    expect(prompt, contains('Exact side profile \u2014 90°'));
    expect(prompt, contains('Exact back view \u2014 180°'));
    expect(prompt, contains('Three equally sized portraits'));
    expect(prompt, isNot(contains('three-quarter')));
    expect(prompt, isNot(contains('four views')));
    expect(prompt, contains('Pure white seamless background'));
    expect(prompt, contains('No cropped hair or missing shoulders'));
    expect(prompt, contains('- art style: Answer for artStyle'));
    expect(
      prompt,
      contains('- character identity: Answer for characterIdentity'),
    );
    expect(prompt, contains('- nose: Answer for nose'));
    expect(prompt, contains('Clothing and accessories:'));
  });

  test('assigns a head response to its exact feature label', () {
    final prompt = buildCharacterSheetPrompt({'nose': 'long and wide'});

    expect(prompt, contains('- nose: long and wide'));
    expect(prompt, isNot(contains('- eyes: long and wide')));
    expect(prompt, isNot(contains('- overall appearance: long and wide')));
  });

  test('reports missing questionnaire answers', () {
    expect(missingCharacterAnswers({'artStyle': 'Ink drawing'}), hasLength(21));
    expect(
      missingCharacterAnswers({
        for (final key in characterAnswerKeys) key: 'Answered',
      }),
      isEmpty,
    );
  });

  test(
    'builds the body prompt from the head, body and clothing interviews',
    () {
      final head = {
        for (final key in characterAnswerKeys) key: 'Head answer for $key',
      };
      final body = {
        for (final key in characterBodyAnswerKeys) key: 'Body answer for $key',
      };
      final clothing = {
        for (final key in characterClothingAnswerKeys)
          key: 'Clothing answer for $key',
      };

      final prompt = buildCharacterBodyPrompt(head, body, clothing);

      expect(prompt, startsWith('FULL-BODY CHARACTER TURNAROUND'));
      expect(prompt, isNot(contains('REFERENCE:')));
      expect(prompt, isNot(contains('supplied approved face sheet')));
      expect(prompt, isNot(contains('input image')));
      expect(prompt, contains('HEAD:\nThe head looks like:\n'));
      expect(prompt, contains('- art style: Head answer for artStyle'));
      expect(
        prompt,
        contains('- character identity: Head answer for characterIdentity'),
      );
      expect(prompt, contains('- nose: Head answer for nose'));
      expect(
        prompt,
        contains(
          'BODY:\nThe body looks like:\n'
          '- height, build, silhouette and proportions: '
          'Body answer for heightBuildSilhouetteProportions',
        ),
      );
      expect(
        prompt,
        contains(
          'CLOTHING:\n'
          '- outfit concept, setting and silhouette: '
          'Clothing answer for outfitConceptSettingSilhouette',
        ),
      );
      expect(prompt, isNot(contains('Shoulders and head visible')));
      expect(prompt, isNot(contains('Three equally sized portraits')));
      expect(prompt, contains('Create three equally sized'));
      expect(prompt, contains('1. Direct front view, 0 degrees.'));
      expect(prompt, contains('2. Exact 90 degree side profile.'));
      expect(prompt, contains('3. Exact 180 degree back view.'));
      expect(prompt, isNot(contains('Three-quarter view')));
      expect(prompt, isNot(contains('Rear three-quarter view')));
      expect(prompt, isNot(contains('Exact 90° side profile')));
      expect(prompt, isNot(contains('Exact 180° back view')));
      expect(prompt, isNot(contains('all three views')));
      expect(prompt, contains('FULL-BODY CHARACTER TURNAROUND'));
      expect(prompt, contains('Neutral standing reference pose'));
      expect(prompt, contains('Pure white seamless background'));
      expect(
        prompt,
        endsWith('Do not crop the head, hair, hands, clothing or feet.'),
      );
      for (final answer in [
        ...head.values,
        ...body.values,
        ...clothing.values,
      ]) {
        expect(prompt, contains(answer));
      }
    },
  );

  test('keeps every head, body and clothing answer on its own feature', () {
    final featureGroups = <List<CharacterPromptFeature>>[
      for (final section in characterHeadPromptSections) section.features,
      characterBodyPromptFeatures,
      characterClothingPromptFeatures,
    ];

    for (final features in featureGroups) {
      for (final feature in features) {
        final answer = 'unique answer for ${feature.answerKey}';
        final prompt = buildCharacterBodyPrompt(
          {feature.answerKey: answer},
          {feature.answerKey: answer},
          {feature.answerKey: answer},
        );
        final matchingLines = prompt
            .split('\n')
            .where((line) => line.contains(answer))
            .toList();

        expect(
          matchingLines,
          ['- ${feature.label}: $answer'],
          reason: '${feature.answerKey} must map only to ${feature.label}',
        );
      }
    }
  });
}
