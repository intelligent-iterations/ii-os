import 'package:ii_os_design_system/ii_os_design_system.dart';

import '../repositories/prompt_enhancement_repository.dart';
import 'prompt_enhance_copy.dart';

/// Per-field rewrite state, independent of how a surface stores it.
///
/// Keyed by workflow input name rather than held as a single value, because a
/// page can have more than one creative field and they are enhanced
/// independently -- a song's description and its lyrics go to different guides
/// and can be rewritten in either order.
///
/// The pre-rewrite text is kept here, which is what makes replacing the field
/// in place fair: nothing the person wrote is lost by trying, and [undo] hands
/// it straight back.
///
/// Plain rather than a ViewModel mixin so the surfaces that predate the
/// ViewModel migration can offer the same affordance without being rewritten
/// first. `PromptEnhancementSupport` wraps it for the pages that have one.
final class PromptEnhancementFields {
  PromptEnhancementFields({
    required this.repository,
    required this.workspaceId,
  });

  final PromptEnhancementRepository repository;
  final String workspaceId;

  final Map<String, PromptEnhanceOutcome> _outcomes = {};
  final Map<String, String> _messages = {};
  final Map<String, String> _originals = {};

  PromptEnhanceOutcome outcome(String field) =>
      _outcomes[field] ?? PromptEnhanceOutcome.idle;

  String? message(String field) => _messages[field];

  bool canUndo(String field) => _originals.containsKey(field);

  /// True when [field] currently holds a rewrite the person kept.
  bool keptEnhancedTextFor(String field) => _originals.containsKey(field);

  /// Rewrites one field, returning the new text or null when nothing changed.
  ///
  /// [stateKey] defaults to the request's field. Pass one when a surface has
  /// several editors feeding the same workflow input -- every storyboard panel
  /// writes to `prompt`, and they each need their own undo.
  ///
  /// [onChanged] fires when the state moves, so a ViewModel can notify and a
  /// `setState` surface can rebuild, without this class knowing which it is.
  Future<String?> enhance(
    PromptEnhancementRequest request, {
    String? stateKey,
    void Function()? onChanged,
  }) async {
    final field = stateKey ?? request.field;
    if (request.prompt.trim().isEmpty) return null;
    _outcomes[field] = PromptEnhanceOutcome.running;
    _messages.remove(field);
    onChanged?.call();
    try {
      final result = await repository.preview(workspaceId, request);
      final notice = promptEnhanceNotice(result);
      _outcomes[field] = notice.outcome;
      _messages[field] = notice.message;
      if (!result.changed) return null;
      // A second pass polishes the rewrite, not the person's original. Keep
      // the first value so Undo always fulfils its promise.
      _originals.putIfAbsent(field, () => request.prompt);
      return result.prompt;
    } on Object {
      _outcomes[field] = PromptEnhanceOutcome.unchanged;
      _messages[field] =
          'Your text is unchanged. ii-os could not reach the rewriter. '
          'Try again in a moment.';
      return null;
    } finally {
      onChanged?.call();
    }
  }

  /// Restores the text as it was before the rewrite, or null when there is
  /// nothing to restore.
  String? undo(String field) {
    final original = _originals.remove(field);
    if (original == null) return null;
    _outcomes[field] = PromptEnhanceOutcome.idle;
    _messages.remove(field);
    return original;
  }

  /// Forgets the rewrite history, so a submitted form starts clean.
  void reset() {
    _outcomes.clear();
    _messages.clear();
    _originals.clear();
  }
}
