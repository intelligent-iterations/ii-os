import 'dart:convert';

/// One bar in a decision distribution, in the order the runtime returned it.
final class DecisionShare {
  const DecisionShare({required this.label, required this.probability});

  final String label;
  final double probability;
}

sealed class ClassificationAnswer {
  const ClassificationAnswer(this.name);

  /// The question name the person chose; the runtime answers by this key.
  final String name;
}

final class ClassificationChoiceAnswer extends ClassificationAnswer {
  const ClassificationChoiceAnswer(
    super.name, {
    required this.choice,
    required this.confidence,
    required this.distribution,
  });

  final String choice;
  final double confidence;
  final List<DecisionShare> distribution;
}

final class ClassificationYesNoAnswer extends ClassificationAnswer {
  const ClassificationYesNoAnswer(super.name, {required this.yes});

  /// Probability of yes. There is no separate confidence for yes / no.
  final double yes;
}

final class ClassificationScoreAnswer extends ClassificationAnswer {
  const ClassificationScoreAnswer(
    super.name, {
    required this.score,
    required this.confidence,
    required this.distribution,
  });

  /// Probability-weighted level on the 0-5 scale; may fall between levels.
  final double score;
  final double confidence;
  final List<DecisionShare> distribution;
}

/// Facts about the run that produced the answers.
final class ClassificationRunFacts {
  const ClassificationRunFacts({
    required this.model,
    required this.revision,
    required this.decideSeconds,
    required this.loadSeconds,
    required this.stateTokens,
    required this.stateTruncated,
    required this.device,
  });

  final String model;
  final String revision;
  final double? decideSeconds;
  final double? loadSeconds;
  final int? stateTokens;
  final bool stateTruncated;
  final String? device;

  String get shortRevision =>
      revision.length > 12 ? revision.substring(0, 12) : revision;
}

/// The decisions document a classification run writes to workspace storage.
///
/// Parsed strictly: a document that does not match the runtime contract is
/// refused as a whole instead of rendering whichever parts happen to parse.
final class ClassificationDecisions {
  const ClassificationDecisions({
    required this.answers,
    required this.run,
    required this.inputTokens,
  });

  factory ClassificationDecisions.fromDocument(Object? document) {
    final root = _map(document, 'document');
    if (root['schema_version'] != 1) _fail('schema_version');
    final response = _map(root['response'], 'response');
    final answers = _map(response['answers'], 'answers');
    if (answers.isEmpty) _fail('answers');
    final usage = _map(response['usage'], 'usage');
    final run = _map(root['run'], 'run');
    return ClassificationDecisions(
      answers: [
        for (final entry in answers.entries)
          _answer(entry.key, _map(entry.value, entry.key)),
      ],
      run: ClassificationRunFacts(
        model: _string(run['model'], 'run.model'),
        revision: _string(run['model_revision'], 'run.model_revision'),
        decideSeconds: _optionalNumber(run['decide_seconds']),
        loadSeconds: _optionalNumber(run['load_seconds']),
        stateTokens: _optionalNumber(run['state_tokens'])?.round(),
        stateTruncated: run['state_truncated'] == true,
        device: run['device'] is String ? run['device'] as String : null,
      ),
      inputTokens: _number(usage['input_tokens'], 'input_tokens').round(),
    );
  }

  final List<ClassificationAnswer> answers;
  final ClassificationRunFacts run;
  final int inputTokens;
}

ClassificationAnswer _answer(String name, Map<String, Object?> json) =>
    switch (json['type']) {
      'choice' => ClassificationChoiceAnswer(
        name,
        choice: _string(json['choice'], '$name.choice'),
        confidence: _probability(json['confidence'], '$name.confidence'),
        distribution: _shares(json['probabilities'], name, (key) => key),
      ),
      'noul' => ClassificationYesNoAnswer(
        name,
        yes: _probability(json['noul'], '$name.noul'),
      ),
      'score' => ClassificationScoreAnswer(
        name,
        score: _number(json['score'], '$name.score'),
        confidence: _probability(json['confidence'], '$name.confidence'),
        distribution: _shares(
          json['probabilities'],
          name,
          (level) => _levelLabel(level, _map(json['legend'], '$name.legend')),
        ),
      ),
      _ => _fail('$name.type'),
    };

String _levelLabel(String level, Map<String, Object?> legend) {
  final description = legend[level];
  final text = description is String ? description : jsonEncode(description);
  return description == null ? level : '$level · $text';
}

List<DecisionShare> _shares(
  Object? value,
  String name,
  String Function(String key) label,
) {
  final probabilities = _map(value, '$name.probabilities');
  if (probabilities.isEmpty) _fail('$name.probabilities');
  return [
    for (final entry in probabilities.entries)
      DecisionShare(
        label: label(entry.key),
        probability: _probability(entry.value, '$name.${entry.key}'),
      ),
  ];
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) _fail(field);
  return value.cast<String, Object?>();
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) _fail(field);
  return value;
}

double _number(Object? value, String field) {
  if (value is! num || !value.isFinite) _fail(field);
  return value.toDouble();
}

double? _optionalNumber(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

double _probability(Object? value, String field) {
  final number = _number(value, field);
  if (number < 0 || number > 1) _fail(field);
  return number;
}

Never _fail(String field) =>
    throw FormatException('The classification result is malformed ($field).');

/// A sentence for a person, from a workflow's terminal error code.
String classificationFailureMessage(String? errorCode) => switch (errorCode) {
  'classification_request_rejected' =>
    'The model could not answer these questions. Check the question types and '
        'choices, then try again.',
  'classification_fleet_allocation_failed' =>
    'No GPU host could take the classification run. Try again in a few '
        'minutes.',
  'classification_runtime_unavailable' =>
    'No runner has the classification model installed yet.',
  'classification_model_missing' =>
    'The classification model is not installed on your GPU runner yet. '
        'Install it there, then try again.',
  'classification_workflow_cancelled' =>
    'The classification run was cancelled.',
  'classification_result_unreadable' =>
    'The result could not be verified in this browser. Try running it again.',
  _ =>
    'The classification run did not finish. Try again, and check the run in '
        'Jobs if it keeps failing.',
};
