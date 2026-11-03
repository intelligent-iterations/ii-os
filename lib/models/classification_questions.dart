import 'dart:convert';

/// Bounds of the open JEV classification workflow.
///
/// They mirror what the runtime accepts -- choices are read through a 16-slot
/// head and scores on a fixed 0-5 scale -- and the catalog's input lengths, so
/// a request the runtime would refuse is caught before it costs a GPU lease.
abstract final class ClassificationLimits {
  static const maxStateChars = 8000;
  static const maxQuestions = 8;
  static const maxTextChars = 8000;
  static const minChoices = 2;
  static const maxChoices = 16;
  static const maxChoiceNameChars = 128;
  static const scoreLevels = 6;
  static const maxQuestionsJsonChars = 32000;
  static final questionName = RegExp(r'^[a-z][a-z0-9_]{0,31}$');
}

enum ClassificationQuestionKind {
  choice('choice', 'Choice'),
  yesNo('noul', 'Yes / no'),
  score('score', 'Score');

  const ClassificationQuestionKind(this.wireType, this.label);

  /// The TypeSafe System One question `type`.
  final String wireType;
  final String label;
}

const defaultClassificationScoreLevels = [
  'None',
  'Very low',
  'Low',
  'Moderate',
  'High',
  'Very high',
];

final class ClassificationOptionDraft {
  const ClassificationOptionDraft({
    required this.name,
    this.description = '',
    this.id = '',
  });

  final String name;
  final String description;

  /// The row's stable identity in the form, so removing one choice never
  /// shows another choice's text in its fields.
  final String id;

  ClassificationOptionDraft copyWith({String? name, String? description}) =>
      ClassificationOptionDraft(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
      );
}

/// One question as the person is editing it.
///
/// [key] is the card's stable identity, so renaming a question never remounts
/// its fields; [name] is the answer key the runtime returns.
final class ClassificationQuestionDraft {
  const ClassificationQuestionDraft({
    required this.key,
    required this.name,
    this.kind = ClassificationQuestionKind.choice,
    this.instructions = '',
    this.options = const [],
    this.trueMeans = '',
    this.falseMeans = '',
    this.scoreLevels = defaultClassificationScoreLevels,
  });

  factory ClassificationQuestionDraft.initial(String key, String name) =>
      ClassificationQuestionDraft(
        key: key,
        name: name,
        options: const [
          ClassificationOptionDraft(id: 'option-1', name: 'yes'),
          ClassificationOptionDraft(id: 'option-2', name: 'no'),
        ],
      );

  final String key;
  final String name;
  final ClassificationQuestionKind kind;
  final String instructions;
  final List<ClassificationOptionDraft> options;
  final String trueMeans;
  final String falseMeans;
  final List<String> scoreLevels;

  ClassificationQuestionDraft copyWith({
    String? name,
    ClassificationQuestionKind? kind,
    String? instructions,
    List<ClassificationOptionDraft>? options,
    String? trueMeans,
    String? falseMeans,
    List<String>? scoreLevels,
  }) => ClassificationQuestionDraft(
    key: key,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    instructions: instructions ?? this.instructions,
    options: options ?? this.options,
    trueMeans: trueMeans ?? this.trueMeans,
    falseMeans: falseMeans ?? this.falseMeans,
    scoreLevels: scoreLevels ?? this.scoreLevels,
  );

  /// The question object in TypeSafe's System One request shape.
  Map<String, Object?> toTypeSafe() => {
    'type': kind.wireType,
    'instructions': instructions.trim(),
    ...switch (kind) {
      ClassificationQuestionKind.choice => {
        'criteria': {
          for (final option in options)
            option.name.trim(): option.description.trim().isEmpty
                ? null
                : option.description.trim(),
        },
      },
      ClassificationQuestionKind.yesNo => {
        if (trueMeans.trim().isNotEmpty || falseMeans.trim().isNotEmpty)
          'criteria': {
            if (trueMeans.trim().isNotEmpty) 'true': trueMeans.trim(),
            if (falseMeans.trim().isNotEmpty) 'false': falseMeans.trim(),
          },
      },
      ClassificationQuestionKind.score => {
        'criteria': [for (final level in scoreLevels) level.trim()],
      },
    },
  };
}

/// A problem a person can fix before launching. [questionKey] is null for a
/// problem with the request as a whole.
final class ClassificationFormIssue {
  const ClassificationFormIssue(this.message, {this.questionKey});

  final String message;
  final String? questionKey;
}

String encodeClassificationQuestions(
  List<ClassificationQuestionDraft> questions,
) => jsonEncode({
  for (final question in questions) question.name.trim(): question.toTypeSafe(),
});

List<ClassificationFormIssue> validateClassificationForm({
  required String state,
  required List<ClassificationQuestionDraft> questions,
}) {
  final issues = <ClassificationFormIssue>[];
  final trimmed = state.trim();
  if (trimmed.isEmpty) {
    issues.add(const ClassificationFormIssue('Add the text to classify.'));
  } else if (state.length > ClassificationLimits.maxStateChars) {
    issues.add(
      const ClassificationFormIssue('Keep the text to 8,000 characters.'),
    );
  }
  if (questions.isEmpty) {
    issues.add(const ClassificationFormIssue('Add at least one question.'));
  } else if (questions.length > ClassificationLimits.maxQuestions) {
    issues.add(
      const ClassificationFormIssue('Ask at most 8 questions at a time.'),
    );
  }
  final names = <String>{};
  for (final question in questions) {
    final problem = _questionIssue(question, names);
    if (problem != null) {
      issues.add(ClassificationFormIssue(problem, questionKey: question.key));
    }
  }
  if (issues.isEmpty &&
      encodeClassificationQuestions(questions).length >
          ClassificationLimits.maxQuestionsJsonChars) {
    issues.add(
      const ClassificationFormIssue(
        'The questions are too long together. Shorten descriptions or ask '
        'fewer questions.',
      ),
    );
  }
  return issues;
}

String? _questionIssue(
  ClassificationQuestionDraft question,
  Set<String> names,
) {
  final name = question.name.trim();
  if (!ClassificationLimits.questionName.hasMatch(name)) {
    return 'Use a lowercase name that starts with a letter, up to 32 '
        'characters.';
  }
  if (!names.add(name)) return 'Each question needs a different name.';
  if (question.instructions.length > ClassificationLimits.maxTextChars) {
    return 'Keep the question to 8,000 characters.';
  }
  return switch (question.kind) {
    ClassificationQuestionKind.choice => _choiceIssue(question.options),
    ClassificationQuestionKind.yesNo =>
      question.trueMeans.length > ClassificationLimits.maxTextChars ||
              question.falseMeans.length > ClassificationLimits.maxTextChars
          ? 'Keep each yes / no description to 8,000 characters.'
          : null,
    ClassificationQuestionKind.score =>
      question.scoreLevels.length != ClassificationLimits.scoreLevels ||
              question.scoreLevels.any((level) => level.trim().isEmpty)
          ? 'Describe every score level from 0 to 5.'
          : question.scoreLevels.any(
              (level) => level.length > ClassificationLimits.maxTextChars,
            )
          ? 'Keep each score level to 8,000 characters.'
          : null,
  };
}

String? _choiceIssue(List<ClassificationOptionDraft> options) {
  if (options.length < ClassificationLimits.minChoices) {
    return 'Add at least 2 choices.';
  }
  if (options.length > ClassificationLimits.maxChoices) {
    return 'Use at most 16 choices.';
  }
  final names = <String>{};
  for (final option in options) {
    final name = option.name.trim();
    if (name.isEmpty || name.length > ClassificationLimits.maxChoiceNameChars) {
      return 'Name every choice, up to 128 characters.';
    }
    if (!names.add(name)) return 'Each choice needs a different name.';
    if (option.description.length > ClassificationLimits.maxTextChars) {
      return 'Keep each choice description to 8,000 characters.';
    }
  }
  return null;
}
