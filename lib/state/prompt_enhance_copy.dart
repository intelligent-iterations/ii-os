import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../repositories/prompt_enhancement_repository.dart';

/// What the person reads after an enhance attempt, and how it is toned.
final class PromptEnhanceNotice {
  const PromptEnhanceNotice({required this.outcome, required this.message});

  final PromptEnhanceOutcome outcome;
  final String message;
}

/// Turns a rewrite result into one sentence written for a person.
///
/// The status codes and guide ids the API returns are mechanism: `fallback`,
/// `key_unavailable`, `chatterbox-speech`. None of them belong on a surface a
/// customer reads, so every one of them is named here instead -- one sentence
/// stating what happened to their text and, where there is one, the named way
/// to get unblocked.
PromptEnhanceNotice promptEnhanceNotice(PromptEnhancementResult result) {
  if (result.changed) {
    return PromptEnhanceNotice(
      outcome: PromptEnhanceOutcome.rewritten,
      message: switch (result) {
        _ when result.targetModel.isEmpty =>
          'Rewritten for ${_modalityLabel(result.modality)}.',
        _ when result.modelSpecific => 'Rewritten for ${result.targetModel}.',
        _ =>
          'Rewritten for ${_modalityLabel(result.modality)}. '
              'No guide is written for ${result.targetModel} yet.',
      },
    );
  }
  return PromptEnhanceNotice(
    outcome: PromptEnhanceOutcome.unchanged,
    message: switch ((result.status, result.fallbackReason)) {
      ('disabled', _) =>
        'Your text is unchanged. Prompt enhancement is off for this project \u2014 '
            'a project admin can turn it on in Settings.',
      (_, 'key_unavailable') =>
        'Your text is unchanged. ii-os could not read this project\u2019s '
            'DeepSeek key \u2014 a project admin can replace it in Settings.',
      (_, 'provider_unavailable') =>
        'Your text is unchanged. DeepSeek did not answer. Try again in a '
            'moment.',
      (_, 'invalid_response') =>
        'Your text is unchanged. The rewriter returned empty or malformed '
            'text. Try again if you want another version.',
      _ => 'Your text is unchanged.',
    },
  );
}

/// The tooltip on the button, before anything is known about the outcome.
///
/// Falls back to naming the job rather than the model, for the surfaces where
/// the model's name is mechanism the reader did not ask for.
String promptEnhanceTooltip(String targetModel) => targetModel.isEmpty
    ? 'Rewrite this so the model follows it more closely'
    : 'Rewrite this against the prompting guide for $targetModel';

/// What ii-os calls each modality in a sentence.
String _modalityLabel(String modality) => switch (modality) {
  'image' => 'image prompts',
  'image_edit' => 'image edits',
  'inpaint' => 'inpainting',
  'video' => 'video prompts',
  'music' => 'music captions',
  'lyrics' => 'lyrics',
  'speech' => 'narration',
  _ => 'this kind of prompt',
};
