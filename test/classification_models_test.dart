import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/classification_decisions.dart';
import 'package:ii_os/models/classification_presentation.dart';
import 'package:ii_os/models/classification_questions.dart';
import 'package:ii_os/models/models.dart';
import 'package:ii_os/repositories/workflow_template_repository.dart';

JsonMap _decisionsDocument({Object? answers, Object? run}) => {
  'schema_version': 1,
  'response': {
    'model': 'autotrust/JEV-9B',
    'answers':
        answers ??
        {
          'tone': {
            'type': 'choice',
            'choice': 'angry',
            'confidence': 0.7,
            'probabilities': {'angry': 0.8, 'calm': 0.15, 'excited': 0.05},
          },
          'billing': {'type': 'noul', 'noul': 0.98},
          'urgency': {
            'type': 'score',
            'score': 3.4,
            'confidence': 0.42,
            'legend': {
              '0': 'None',
              '1': 'Very low',
              '2': 'Low',
              '3': 'Moderate',
              '4': 'High',
              '5': 'Very high',
            },
            'probabilities': {
              '0': 0.01,
              '1': 0.02,
              '2': 0.1,
              '3': 0.4,
              '4': 0.37,
              '5': 0.1,
            },
          },
        },
    'usage': {'input_tokens': 412, 'output_tokens': 0},
  },
  'run':
      run ??
      {
        'model': 'autotrust/JEV-9B',
        'model_revision': '7ac669b8fb476ba926491e3d1c39f9330d68dbed',
        'template_version': 'bare-v1',
        'render_version': 'render-v1',
        'questions': 3,
        'state_tokens': 24,
        'state_truncated': false,
        'decide_seconds': 0.41,
        'load_seconds': 38.2,
        'device': 'Example 24 GB GPU',
        'peak_vram_mib': 16100,
      },
};

void main() {
  group('workflow template runtime requirement', () {
    test('parses the server runtime status for classification templates', () {
      final templates = parseWorkflowTemplates({
        'templates': [
          {
            'id': 'acme/app#classification-open-jev-9b',
            'workflowId': 'classification-open-jev-9b',
            'enabled': false,
            'disabledReason': 'Waiting for the open JEV runtime image.',
            'runtime': {
              'status': 'unavailable',
              'requiredCapabilities': ['open-jev-9b'],
            },
          },
          {'id': 'acme/app#image-create', 'workflowId': 'image-create'},
        ],
      });

      expect(
        templates.first.runtime?.status,
        WorkflowRuntimeStatus.unavailable,
      );
      expect(templates.first.runtime?.requiredCapabilities, ['open-jev-9b']);
      expect(templates.last.runtime, isNull);
    });

    test('a deployment that reports no runner capacity parses as not '
        'reported', () {
      expect(
        WorkflowRuntimeRequirement.fromJson({'status': 'notReported'})?.status,
        WorkflowRuntimeStatus.notReported,
      );
    });

    test('an unrecognised status is unknown, never available', () {
      expect(
        WorkflowRuntimeRequirement.fromJson({
          'status': 'installed-ish',
        })?.status,
        WorkflowRuntimeStatus.unknown,
      );
    });
  });

  group('classification questions', () {
    test('serialises each question in the TypeSafe System One shape', () {
      final questions = [
        ClassificationQuestionDraft.initial('k1', 'tone').copyWith(
          instructions: 'What is the tone?',
          options: const [
            ClassificationOptionDraft(name: 'angry', description: 'Upset'),
            ClassificationOptionDraft(name: 'calm'),
          ],
        ),
        ClassificationQuestionDraft.initial('k2', 'billing').copyWith(
          kind: ClassificationQuestionKind.yesNo,
          instructions: 'Is this about billing?',
          trueMeans: 'Mentions a charge',
        ),
        ClassificationQuestionDraft.initial('k3', 'urgency').copyWith(
          kind: ClassificationQuestionKind.score,
          instructions: 'How urgent?',
        ),
      ];

      final decoded = jsonDecode(encodeClassificationQuestions(questions));

      expect(decoded['tone'], {
        'type': 'choice',
        'instructions': 'What is the tone?',
        'criteria': {'angry': 'Upset', 'calm': null},
      });
      expect(decoded['billing'], {
        'type': 'noul',
        'instructions': 'Is this about billing?',
        'criteria': {'true': 'Mentions a charge'},
      });
      expect(decoded['urgency']['type'], 'score');
      expect(decoded['urgency']['criteria'], hasLength(6));
      expect(decoded['urgency']['criteria'].first, 'None');
    });

    test('a valid form has no issues', () {
      expect(
        validateClassificationForm(
          state: 'I was charged twice.',
          questions: [ClassificationQuestionDraft.initial('k1', 'q1')],
        ),
        isEmpty,
      );
    });

    test('enforces the state, question, option, and level limits', () {
      final tooManyOptions = List.generate(
        17,
        (index) => ClassificationOptionDraft(name: 'option_$index'),
      );
      final issues = validateClassificationForm(
        state: '',
        questions: [
          ClassificationQuestionDraft.initial('k1', '1bad'),
          ClassificationQuestionDraft.initial(
            'k2',
            'many',
          ).copyWith(options: tooManyOptions),
          ClassificationQuestionDraft.initial('k3', 'same').copyWith(
            options: const [
              ClassificationOptionDraft(name: 'same'),
              ClassificationOptionDraft(name: 'same'),
            ],
          ),
          ClassificationQuestionDraft.initial(
            'k4',
            'one',
          ).copyWith(options: const [ClassificationOptionDraft(name: 'only')]),
          ClassificationQuestionDraft.initial('k5', 'levels').copyWith(
            kind: ClassificationQuestionKind.score,
            scoreLevels: const ['a', 'b', '', 'd', 'e', 'f'],
          ),
          ClassificationQuestionDraft.initial('k6', 'many'),
        ],
      );
      final messages = issues.map((issue) => issue.message).toList();

      expect(messages, contains('Add the text to classify.'));
      expect(
        messages,
        contains(
          'Use a lowercase name that starts with a letter, up to 32 '
          'characters.',
        ),
      );
      expect(messages, contains('Each question needs a different name.'));
      expect(messages, contains('Use at most 16 choices.'));
      expect(messages, contains('Each choice needs a different name.'));
      expect(messages, contains('Add at least 2 choices.'));
      expect(messages, contains('Describe every score level from 0 to 5.'));
      expect(issues.where((issue) => issue.questionKey == 'k5'), hasLength(1));
    });

    test('refuses a ninth question and an oversized state', () {
      final issues = validateClassificationForm(
        state: 'x' * 8001,
        questions: [
          for (var index = 0; index < 9; index++)
            ClassificationQuestionDraft.initial('k$index', 'q$index'),
        ],
      );
      final messages = issues.map((issue) => issue.message);

      expect(messages, contains('Keep the text to 8,000 characters.'));
      expect(messages, contains('Ask at most 8 questions at a time.'));
    });
  });

  group('classification decisions document', () {
    test('parses every answer type in question order', () {
      final decisions = ClassificationDecisions.fromDocument(
        _decisionsDocument(),
      );

      expect(decisions.answers.map((answer) => answer.name), [
        'tone',
        'billing',
        'urgency',
      ]);
      final tone = decisions.answers[0] as ClassificationChoiceAnswer;
      expect(tone.choice, 'angry');
      expect(tone.confidence, 0.7);
      expect(tone.distribution.map((entry) => entry.label), [
        'angry',
        'calm',
        'excited',
      ]);
      expect((decisions.answers[1] as ClassificationYesNoAnswer).yes, 0.98);
      final urgency = decisions.answers[2] as ClassificationScoreAnswer;
      expect(urgency.score, 3.4);
      expect(urgency.distribution[3].label, '3 · Moderate');
      expect(decisions.run.shortRevision, '7ac669b8fb47');
      expect(decisions.run.device, 'Example 24 GB GPU');
      expect(decisions.run.stateTruncated, isFalse);
      expect(decisions.inputTokens, 412);
    });

    test('a malformed document is refused rather than partially shown', () {
      for (final document in <Object?>[
        null,
        {'schema_version': 2},
        _decisionsDocument(
          answers: {
            'tone': {'type': 'choice', 'choice': 'angry'},
          },
        ),
        _decisionsDocument(
          answers: {
            'billing': {'type': 'noul', 'noul': 1.5},
          },
        ),
        _decisionsDocument(
          answers: {
            'box': {'type': 'box'},
          },
        ),
        _decisionsDocument(answers: const <String, Object?>{}),
      ]) {
        expect(
          () => ClassificationDecisions.fromDocument(document),
          throwsFormatException,
          reason: '$document',
        );
      }
    });
  });

  test('failure codes map to sentences written for a person', () {
    expect(
      classificationFailureMessage('classification_request_rejected'),
      contains('could not answer'),
    );
    expect(
      classificationFailureMessage('classification_fleet_allocation_failed'),
      contains('GPU'),
    );
    expect(
      classificationFailureMessage('something_new'),
      isNot(contains('something_new')),
    );
  });

  test('a missing model names the runner the person owns, never Fleet', () {
    expect(
      classificationFailureMessage('classification_runtime_unavailable'),
      'No runner has the classification model installed yet.',
    );
    expect(
      classificationFailureMessage('classification_model_missing'),
      'The classification model is not installed on your GPU runner yet. '
      'Install it there, then try again.',
    );
    for (final code in [
      'classification_runtime_unavailable',
      'classification_model_missing',
      'classification_fleet_allocation_failed',
    ]) {
      expect(classificationFailureMessage(code), isNot(contains('Fleet')));
    }
  });

  test('result views state the verdict and mark the leading option', () {
    final decisions = ClassificationDecisions.fromDocument(
      _decisionsDocument(),
    );
    final views = decisions.answers.map(viewOfAnswer).toList();

    expect(views[0].verdict, 'angry');
    expect(views[0].confidence, 'Confidence 70%');
    expect(
      views[0].shares.where((share) => share.chosen).single.label,
      'angry',
    );
    expect(views[1].verdict, 'Yes');
    expect(views[1].confidence, isNull);
    expect(views[2].verdict, 'Score 3.4 of 5');
    expect(
      views[2].shares.where((share) => share.chosen).single.label,
      '3 · Moderate',
    );
    expect(runFactsOf(decisions), [
      'autotrust/JEV-9B @ 7ac669b8fb47',
      'Answered in 0.41 s',
      'Model loaded in 38 s',
      '24 text tokens',
      'Example 24 GB GPU',
    ]);
  });
}
