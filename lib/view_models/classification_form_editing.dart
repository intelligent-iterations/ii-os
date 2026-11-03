import 'package:stacked/stacked.dart';

import '../models/classification_questions.dart';

/// The editable classification request: the text and its questions.
///
/// Every edit replaces an immutable draft, so the form widgets stay stateless
/// and a test can drive the whole form without pumping a widget.
mixin ClassificationFormEditing on BaseViewModel {
  String stateText = '';
  List<ClassificationQuestionDraft> questions = [
    ClassificationQuestionDraft.initial('question-1', 'q1'),
  ];
  int _nextKey = 2;
  int _nextOptionKey = 3;

  List<ClassificationFormIssue> get issues =>
      validateClassificationForm(state: stateText, questions: questions);

  String? issueFor(String questionKey) {
    for (final issue in issues) {
      if (issue.questionKey == questionKey) return issue.message;
    }
    return null;
  }

  bool get canAddQuestion =>
      questions.length < ClassificationLimits.maxQuestions;

  void setStateText(String value) {
    stateText = value;
    notifyListeners();
  }

  void addQuestion() {
    if (!canAddQuestion) return;
    final used = questions.map((question) => question.name).toSet();
    var index = questions.length + 1;
    while (used.contains('q$index')) {
      index++;
    }
    questions = [
      ...questions,
      ClassificationQuestionDraft.initial('question-${_nextKey++}', 'q$index'),
    ];
    notifyListeners();
  }

  void removeQuestion(String key) {
    if (questions.length <= 1) return;
    questions = questions.where((question) => question.key != key).toList();
    notifyListeners();
  }

  void renameQuestion(String key, String name) =>
      _edit(key, (question) => question.copyWith(name: name));

  void setKind(String key, ClassificationQuestionKind kind) =>
      _edit(key, (question) => question.copyWith(kind: kind));

  void setInstructions(String key, String value) =>
      _edit(key, (question) => question.copyWith(instructions: value));

  void setTrueMeans(String key, String value) =>
      _edit(key, (question) => question.copyWith(trueMeans: value));

  void setFalseMeans(String key, String value) =>
      _edit(key, (question) => question.copyWith(falseMeans: value));

  void setScoreLevel(String key, int level, String value) => _edit(
    key,
    (question) => question.copyWith(
      scoreLevels: [
        for (var index = 0; index < question.scoreLevels.length; index++)
          index == level ? value : question.scoreLevels[index],
      ],
    ),
  );

  void addOption(String key) => _edit(key, (question) {
    if (question.options.length >= ClassificationLimits.maxChoices) {
      return question;
    }
    return question.copyWith(
      options: [
        ...question.options,
        ClassificationOptionDraft(
          id: 'option-${_nextOptionKey++}',
          name: 'option_${question.options.length + 1}',
        ),
      ],
    );
  });

  void removeOption(String key, int index) => _edit(
    key,
    (question) => question.options.length <= ClassificationLimits.minChoices
        ? question
        : question.copyWith(options: [...question.options]..removeAt(index)),
  );

  void setOptionName(String key, int index, String value) =>
      _editOption(key, index, (option) => option.copyWith(name: value));

  void setOptionDescription(String key, int index, String value) =>
      _editOption(key, index, (option) => option.copyWith(description: value));

  void _editOption(
    String key,
    int index,
    ClassificationOptionDraft Function(ClassificationOptionDraft) change,
  ) => _edit(
    key,
    (question) => question.copyWith(
      options: [
        for (var at = 0; at < question.options.length; at++)
          at == index ? change(question.options[at]) : question.options[at],
      ],
    ),
  );

  void _edit(
    String key,
    ClassificationQuestionDraft Function(ClassificationQuestionDraft) change,
  ) {
    questions = [
      for (final question in questions)
        question.key == key ? change(question) : question,
    ];
    notifyListeners();
  }
}
