import 'classification_decisions.dart';

/// What a result card shows for one answer: a one-line verdict and the bars.
final class ClassificationAnswerView {
  const ClassificationAnswerView({
    required this.name,
    required this.verdict,
    required this.shares,
    this.confidence,
  });

  final String name;
  final String verdict;

  /// Null for yes / no, which has no separate confidence.
  final String? confidence;
  final List<({String label, double probability, bool chosen})> shares;
}

String percent(double value) => '${(value.clamp(0, 1) * 100).round()}%';

ClassificationAnswerView viewOfAnswer(ClassificationAnswer answer) =>
    switch (answer) {
      ClassificationChoiceAnswer(:final choice, :final confidence) =>
        ClassificationAnswerView(
          name: answer.name,
          verdict: choice,
          confidence: 'Confidence ${percent(confidence)}',
          shares: [
            for (final share in answer.distribution)
              (
                label: share.label,
                probability: share.probability,
                chosen: share.label == choice,
              ),
          ],
        ),
      ClassificationYesNoAnswer(:final yes) => ClassificationAnswerView(
        name: answer.name,
        verdict: yes >= 0.5 ? 'Yes' : 'No',
        shares: [(label: 'Yes', probability: yes, chosen: yes >= 0.5)],
      ),
      ClassificationScoreAnswer(:final score, :final confidence) =>
        ClassificationAnswerView(
          name: answer.name,
          verdict: 'Score ${score.toStringAsFixed(1)} of 5',
          confidence: 'Confidence ${percent(confidence)}',
          shares: _withLeader(answer.distribution),
        ),
    };

List<({String label, double probability, bool chosen})> _withLeader(
  List<DecisionShare> distribution,
) {
  var leader = 0;
  for (var index = 1; index < distribution.length; index++) {
    if (distribution[index].probability > distribution[leader].probability) {
      leader = index;
    }
  }
  return [
    for (var index = 0; index < distribution.length; index++)
      (
        label: distribution[index].label,
        probability: distribution[index].probability,
        chosen: index == leader,
      ),
  ];
}

/// The run facts a person can use: model, revision, timing, input, device.
List<String> runFactsOf(ClassificationDecisions decisions) {
  final run = decisions.run;
  String seconds(double value) => value < 10
      ? '${value.toStringAsFixed(2)} s'
      : '${value.toStringAsFixed(0)} s';
  return [
    '${run.model} @ ${run.shortRevision}',
    if (run.decideSeconds case final decide?) 'Answered in ${seconds(decide)}',
    if (run.loadSeconds case final load?) 'Model loaded in ${seconds(load)}',
    if (run.stateTokens case final tokens?) '$tokens text tokens',
    ?run.device,
  ];
}
