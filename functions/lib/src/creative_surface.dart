/// What a creative field is *for*, independent of what it is called.
///
/// Prompt enhancement is only trustworthy when the guide it applies matches the
/// job the field does. A narration script and an image prompt are both "text a
/// person typed into a creative box", and rewriting one under the other's rules
/// produces confident nonsense: the affirmative-description contract that makes
/// an image prompt better would strip the word "not" out of a sentence someone
/// wants read aloud. So the modality decides the guide *and* the rewriting
/// contract, and every creative field resolves to one before it is enhanced.
enum CreativeModality {
  image('image'),
  imageEdit('image_edit'),
  inpaint('inpaint'),
  video('video'),
  music('music'),
  lyrics('lyrics'),
  speech('speech');

  const CreativeModality(this.value);

  final String value;

  /// True when the field describes an artifact to synthesize, so the rewriter
  /// may restructure it freely into the target model's prompt language.
  ///
  /// False when the field carries words that reach the audience unchanged --
  /// narration and lyrics -- where rewriting the wording changes the product.
  bool get isDirection => this != speech && this != lyrics;

  static CreativeModality? tryParse(String value) {
    for (final modality in CreativeModality.values) {
      if (modality.value == value) return modality;
    }
    return null;
  }
}

/// A workflow input that carries creative intent and can be enhanced.
final class CreativeField {
  const CreativeField({
    required this.input,
    required this.modality,
    required this.label,
  });

  final String input;
  final CreativeModality modality;
  final String label;
}

/// Input keys that carry creative intent, mapped to the label a person sees.
///
/// Anything absent here is configuration -- a seed, a duration, a voice id --
/// and is never sent to the rewriter.
const Map<String, String> creativeInputLabels = <String, String>{
  'prompt': 'Prompt',
  'lyrics': 'Lyrics',
  'text': 'Narration text',
  'motion_prompt': 'Motion prompt',
  'edit_prompt': 'Edit instruction',
};

/// Resolves the modality of one creative field.
///
/// Deliberately inferred rather than keyed by workflow id: a catalog lives in
/// the customer's repository, so ii-os cannot enumerate the workflows it will
/// be asked to enhance for. The shipped catalog is pinned by a coverage test
/// so a workflow added here can never silently land on the wrong guide.
CreativeModality creativeModalityFor({
  required String field,
  required String workflowId,
  required String model,
  Iterable<String> outputKinds = const <String>[],
  int attachedImageCount = 0,
}) {
  final normalizedField = field.toLowerCase().replaceAll('-', '_').trim();
  if (normalizedField == 'lyrics') return CreativeModality.lyrics;

  final signal = '$workflowId $model'.toLowerCase().replaceAll('_', '-').trim();
  final kinds = outputKinds.map((kind) => kind.toLowerCase()).toSet();

  if (_matches(signal, const [
        'narration',
        'tts',
        'chatterbox',
        'voice-over',
      ]) ||
      (normalizedField == 'text' && kinds.contains('audio'))) {
    return CreativeModality.speech;
  }
  if (_matches(signal, const ['song', 'music', 'ace-step', 'acestep'])) {
    return CreativeModality.music;
  }
  if (kinds.contains('video') ||
      _matches(signal, const ['video', 'ltx', 'minimax-h3'])) {
    return CreativeModality.video;
  }
  if (_matches(signal, const ['inpaint'])) return CreativeModality.inpaint;
  if (normalizedField == 'edit_prompt' ||
      _matches(signal, const ['edit', 'controlnet']) ||
      attachedImageCount > 0) {
    return CreativeModality.imageEdit;
  }
  return CreativeModality.image;
}

/// The creative fields a workflow exposes, in the order a person meets them.
List<CreativeField> creativeFieldsFor({
  required String workflowId,
  required String model,
  required Iterable<String> stringInputs,
  Iterable<String> outputKinds = const <String>[],
}) {
  final fields = <CreativeField>[];
  for (final input in stringInputs) {
    final label = creativeInputLabels[input];
    if (label == null) continue;
    fields.add(
      CreativeField(
        input: input,
        label: label,
        modality: creativeModalityFor(
          field: input,
          workflowId: workflowId,
          model: model,
          outputKinds: outputKinds,
        ),
      ),
    );
  }
  return fields;
}

bool _matches(String signal, List<String> needles) =>
    needles.any(signal.contains);
